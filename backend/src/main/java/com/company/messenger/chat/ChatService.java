package com.company.messenger.chat;

import java.io.IOException;
import java.io.InputStream;
import java.time.Instant;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import com.company.messenger.chat.ChatDtos.AttachmentDto;
import com.company.messenger.chat.ChatDtos.MemberDto;
import com.company.messenger.chat.ChatDtos.MessageDto;
import com.company.messenger.chat.ChatDtos.RoomDto;
import com.company.messenger.chat.ChatDtos.SearchResultDto;
import com.company.messenger.common.ApiException;
import com.company.messenger.config.AppProperties;
import com.company.messenger.file.FileStorage;
import com.company.messenger.realtime.EventPublisher;
import com.company.messenger.user.User;
import com.company.messenger.user.UserService;

@Service
public class ChatService {

    public static final Set<String> IMAGE_TYPES = Set.of("image/png", "image/jpeg", "image/gif", "image/webp");
    private static final int MAX_TEXT_LENGTH = 10_000;
    private static final int MAX_GROUP_MEMBERS = 1_000;

    private final ChatRoomRepository rooms;
    private final RoomMemberRepository members;
    private final MessageRepository messages;
    private final AttachmentRepository attachments;
    private final UserService userService;
    private final EventPublisher events;
    private final FileStorage storage;
    private final Set<String> blockedExtensions;

    public ChatService(ChatRoomRepository rooms, RoomMemberRepository members, MessageRepository messages,
                       AttachmentRepository attachments, UserService userService, EventPublisher events,
                       FileStorage storage, AppProperties props) {
        this.rooms = rooms;
        this.members = members;
        this.messages = messages;
        this.attachments = attachments;
        this.userService = userService;
        this.events = events;
        this.storage = storage;
        this.blockedExtensions = props.files().blockedExtensions().stream()
                .map(s -> s.trim().toLowerCase(Locale.ROOT)).collect(Collectors.toSet());
    }

    // ------------------------------------------------------------------ 조회

    @Transactional(readOnly = true)
    public List<RoomDto> listRooms(Long userId) {
        List<ChatRoom> list = rooms.findByMember(userId);
        return toRoomDtos(userId, list);
    }

    @Transactional(readOnly = true)
    public RoomDto getRoom(Long userId, Long roomId) {
        ChatRoom room = requireMember(userId, roomId);
        return toRoomDtos(userId, List.of(room)).get(0);
    }

    @Transactional(readOnly = true)
    public List<MessageDto> messages(Long userId, Long roomId, Long before, int size) {
        requireMember(userId, roomId);
        long cursor = before == null ? Long.MAX_VALUE : before;
        List<Message> page = new ArrayList<>(messages.findPage(roomId, cursor, PageRequest.of(0, Math.min(size, 100))));
        page.sort(Comparator.comparing(Message::getId));
        return toMessageDtos(page);
    }

    @Transactional(readOnly = true)
    public List<SearchResultDto> search(Long userId, String q, Long roomId) {
        String query = q == null ? "" : q.trim();
        if (query.length() < 2) {
            throw ApiException.badRequest("검색어는 2자 이상 입력하세요.");
        }
        String escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_");
        List<Message> found = messages.search(userId, escaped, roomId == null ? 0 : roomId);
        if (found.isEmpty()) {
            return List.of();
        }
        Set<Long> roomIds = found.stream().map(Message::getRoomId).collect(Collectors.toSet());
        Map<Long, String> roomNames = toRoomDtos(userId, rooms.findAllById(roomIds)).stream()
                .collect(Collectors.toMap(RoomDto::id, RoomDto::name));
        List<MessageDto> dtos = toMessageDtos(found);
        return dtos.stream().map(m -> new SearchResultDto(m, roomNames.get(m.roomId()))).toList();
    }

    // ------------------------------------------------------------------ 방 관리

    @Transactional
    public RoomDto openDirect(Long userId, Long targetId) {
        User target = userService.get(targetId);
        if (!target.isActive()) {
            throw ApiException.badRequest("비활성화된 사용자입니다.");
        }
        long a = Math.min(userId, targetId);
        long b = Math.max(userId, targetId);
        String key = a + ":" + b;
        ChatRoom room = rooms.findByDirectKey(key).orElseGet(() -> {
            ChatRoom r = new ChatRoom();
            r.setType(RoomType.DIRECT);
            r.setDirectKey(key);
            r.setCreatedBy(userId);
            return rooms.save(r);
        });
        // 이전에 나간 경우 다시 참여
        ensureMember(room.getId(), userId);
        return toRoomDtos(userId, List.of(room)).get(0);
    }

    @Transactional
    public RoomDto createGroup(Long userId, String name, Collection<Long> memberIds) {
        Set<Long> ids = new LinkedHashSet<>();
        ids.add(userId);
        ids.addAll(memberIds);
        if (ids.size() < 2) {
            throw ApiException.badRequest("대화 상대를 1명 이상 선택하세요.");
        }
        if (ids.size() > MAX_GROUP_MEMBERS) {
            throw ApiException.badRequest("그룹 채팅 인원은 최대 " + MAX_GROUP_MEMBERS + "명입니다.");
        }
        Map<Long, User> users = userService.getAll(ids);
        if (users.size() != ids.size()) {
            throw ApiException.badRequest("존재하지 않는 사용자가 포함되어 있습니다.");
        }
        ChatRoom room = new ChatRoom();
        room.setType(RoomType.GROUP);
        room.setName(name == null || name.isBlank() ? null : name.trim());
        room.setCreatedBy(userId);
        room = rooms.save(room);
        for (Long id : ids) {
            members.save(new RoomMember(room.getId(), id, 0));
        }
        String names = ids.stream().filter(id -> !id.equals(userId)).map(id -> users.get(id).getName())
                .collect(Collectors.joining(", "));
        postSystem(room, users.get(userId).getName() + "님이 " + names + "님을 초대했습니다.");
        events.toUsers(ids, "ROOM_UPDATED", Map.of("roomId", room.getId()));
        return toRoomDtos(userId, List.of(room)).get(0);
    }

    @Transactional
    public RoomDto invite(Long userId, Long roomId, Collection<Long> userIds) {
        ChatRoom room = requireMember(userId, roomId);
        if (room.getType() != RoomType.GROUP) {
            throw ApiException.badRequest("1:1 대화방에는 초대할 수 없습니다. 그룹 채팅을 새로 만드세요.");
        }
        Set<Long> current = new HashSet<>(members.findUserIds(roomId));
        List<Long> newIds = userIds.stream().distinct().filter(id -> !current.contains(id)).toList();
        if (newIds.isEmpty()) {
            return getRoom(userId, roomId);
        }
        if (current.size() + newIds.size() > MAX_GROUP_MEMBERS) {
            throw ApiException.badRequest("그룹 채팅 인원은 최대 " + MAX_GROUP_MEMBERS + "명입니다.");
        }
        Map<Long, User> users = userService.getAll(newIds);
        if (users.size() != newIds.size()) {
            throw ApiException.badRequest("존재하지 않는 사용자가 포함되어 있습니다.");
        }
        // 초대된 사용자는 초대 이후의 메시지부터 안 읽음으로 계산
        long lastId = latestMessageId(roomId);
        for (Long id : newIds) {
            members.save(new RoomMember(roomId, id, lastId));
        }
        String inviter = userService.get(userId).getName();
        String names = newIds.stream().map(id -> users.get(id).getName()).collect(Collectors.joining(", "));
        postSystem(room, inviter + "님이 " + names + "님을 초대했습니다.");
        current.addAll(newIds);
        events.toUsers(current, "ROOM_UPDATED", Map.of("roomId", roomId));
        return getRoom(userId, roomId);
    }

    @Transactional
    public RoomDto rename(Long userId, Long roomId, String name) {
        ChatRoom room = requireMember(userId, roomId);
        if (room.getType() != RoomType.GROUP) {
            throw ApiException.badRequest("1:1 대화방은 이름을 변경할 수 없습니다.");
        }
        room.setName(name == null || name.isBlank() ? null : name.trim());
        events.toUsers(members.findUserIds(roomId), "ROOM_UPDATED", Map.of("roomId", roomId));
        return getRoom(userId, roomId);
    }

    @Transactional
    public void leave(Long userId, Long roomId) {
        ChatRoom room = requireMember(userId, roomId);
        members.deleteById(new RoomMember.Key(roomId, userId));
        events.toUsers(List.of(userId), "ROOM_LEFT", Map.of("roomId", roomId));
        if (room.getType() == RoomType.GROUP) {
            postSystem(room, userService.get(userId).getName() + "님이 나갔습니다.");
            events.toUsers(members.findUserIds(roomId), "ROOM_UPDATED", Map.of("roomId", roomId));
        }
    }

    // ------------------------------------------------------------------ 메시지

    @Transactional
    public MessageDto sendText(Long userId, Long roomId, String content) {
        if (content == null || content.isBlank()) {
            throw ApiException.badRequest("메시지를 입력하세요.");
        }
        if (content.length() > MAX_TEXT_LENGTH) {
            throw ApiException.badRequest("메시지는 " + MAX_TEXT_LENGTH + "자까지 보낼 수 있습니다.");
        }
        ChatRoom room = requireMember(userId, roomId);
        return post(room, userId, MessageType.TEXT, content, null);
    }

    @Transactional
    public MessageDto sendFile(Long userId, Long roomId, MultipartFile file) throws IOException {
        ChatRoom room = requireMember(userId, roomId);
        if (file == null || file.isEmpty()) {
            throw ApiException.badRequest("빈 파일은 보낼 수 없습니다.");
        }
        String name = sanitizeFileName(file.getOriginalFilename());
        int dot = name.lastIndexOf('.');
        String ext = dot >= 0 ? name.substring(dot + 1).toLowerCase(Locale.ROOT) : "";
        if (blockedExtensions.contains(ext)) {
            throw ApiException.badRequest("보안 정책상 '." + ext + "' 파일은 전송할 수 없습니다.");
        }
        String contentType = file.getContentType() == null ? "application/octet-stream" : file.getContentType();
        String key;
        try (InputStream in = file.getInputStream()) {
            key = storage.store(in);
        }
        Attachment att = attachments.save(new Attachment(roomId, userId, name, contentType, file.getSize(), key));
        MessageType type = IMAGE_TYPES.contains(contentType) ? MessageType.IMAGE : MessageType.FILE;
        return post(room, userId, type, name, att.getId());
    }

    @Transactional
    public void markRead(Long userId, Long roomId, long messageId) {
        requireMember(userId, roomId);
        long latest = latestMessageId(roomId);
        long target = Math.min(messageId, latest);
        if (members.markRead(roomId, userId, target) > 0) {
            events.toUsers(members.findUserIds(roomId), "READ",
                    Map.of("roomId", roomId, "userId", userId, "lastReadMessageId", target));
        }
    }

    @Transactional
    public void deleteMessage(Long userId, Long messageId) {
        Message m = messages.findById(messageId).orElseThrow(() -> ApiException.notFound("메시지를 찾을 수 없습니다."));
        if (!userId.equals(m.getSenderId())) {
            throw ApiException.forbidden("본인이 보낸 메시지만 삭제할 수 있습니다.");
        }
        requireMember(userId, m.getRoomId());
        m.setDeleted(true);
        m.setContent(null);
        events.toUsers(members.findUserIds(m.getRoomId()), "MESSAGE_DELETED",
                Map.of("roomId", m.getRoomId(), "messageId", messageId));
    }

    @Transactional(readOnly = true)
    public Attachment getAttachment(Long userId, Long attachmentId) {
        Attachment att = attachments.findById(attachmentId)
                .orElseThrow(() -> ApiException.notFound("파일을 찾을 수 없습니다."));
        requireMember(userId, att.getRoomId());
        return att;
    }

    // ------------------------------------------------------------------ 내부

    private MessageDto post(ChatRoom room, Long senderId, MessageType type, String content, Long attachmentId) {
        if (room.getType() == RoomType.DIRECT) {
            // 상대방이 방을 나갔더라도 새 메시지를 받으면 다시 참여시킨다
            for (Long id : directUserIds(room)) {
                ensureMember(room.getId(), id);
            }
        }
        Message m = messages.save(new Message(room.getId(), senderId, type, content, attachmentId));
        room.setLastMessageAt(Instant.now());
        if (senderId != null) {
            members.markRead(room.getId(), senderId, m.getId());
        }
        MessageDto dto = toMessageDtos(List.of(m)).get(0);
        events.toUsers(members.findUserIds(room.getId()), "MESSAGE", Map.of("message", dto));
        return dto;
    }

    private void postSystem(ChatRoom room, String text) {
        post(room, null, MessageType.SYSTEM, text, null);
    }

    private void ensureMember(Long roomId, Long userId) {
        if (!members.existsByRoomIdAndUserId(roomId, userId)) {
            members.save(new RoomMember(roomId, userId, latestMessageId(roomId)));
        }
    }

    private long latestMessageId(Long roomId) {
        List<Message> last = messages.findPage(roomId, Long.MAX_VALUE, PageRequest.of(0, 1));
        return last.isEmpty() ? 0 : last.get(0).getId();
    }

    private ChatRoom requireMember(Long userId, Long roomId) {
        if (!members.existsByRoomIdAndUserId(roomId, userId)) {
            throw ApiException.forbidden("대화방 참여자가 아닙니다.");
        }
        return rooms.findById(roomId).orElseThrow(() -> ApiException.notFound("대화방을 찾을 수 없습니다."));
    }

    private static String sanitizeFileName(String name) {
        if (name == null || name.isBlank()) {
            return "file";
        }
        String base = name.replace('\\', '/');
        base = base.substring(base.lastIndexOf('/') + 1).replaceAll("[\\p{Cntrl}]", "");
        if (base.length() > 200) {
            base = base.substring(base.length() - 200);
        }
        return base.isBlank() ? "file" : base;
    }

    private List<MessageDto> toMessageDtos(List<Message> list) {
        Set<Long> senderIds = list.stream().map(Message::getSenderId).filter(java.util.Objects::nonNull)
                .collect(Collectors.toSet());
        Map<Long, User> senders = userService.getAll(senderIds);
        Set<Long> attIds = list.stream().map(Message::getAttachmentId).filter(java.util.Objects::nonNull)
                .collect(Collectors.toSet());
        Map<Long, Attachment> atts = attachments.findAllById(attIds).stream()
                .collect(Collectors.toMap(Attachment::getId, Function.identity()));
        return list.stream().map(m -> {
            User s = m.getSenderId() == null ? null : senders.get(m.getSenderId());
            Attachment a = m.isDeleted() || m.getAttachmentId() == null ? null : atts.get(m.getAttachmentId());
            AttachmentDto ad = a == null ? null : new AttachmentDto(a.getId(), a.getOriginalName(), a.getContentType(), a.getSize());
            return new MessageDto(m.getId(), m.getRoomId(), m.getSenderId(), s == null ? null : s.getName(),
                    m.getType().name(), m.isDeleted() ? null : m.getContent(), ad, m.isDeleted(), m.getCreatedAt());
        }).toList();
    }

    private List<RoomDto> toRoomDtos(Long userId, List<ChatRoom> list) {
        if (list.isEmpty()) {
            return List.of();
        }
        List<Long> roomIds = list.stream().map(ChatRoom::getId).toList();
        Map<Long, List<RoomMember>> membersByRoom = members.findByRoomIdIn(roomIds).stream()
                .collect(Collectors.groupingBy(RoomMember::getRoomId));
        Set<Long> userIds = membersByRoom.values().stream().flatMap(List::stream).map(RoomMember::getUserId)
                .collect(Collectors.toCollection(HashSet::new));
        // 1:1 방은 상대방이 나갔어도 상대 이름으로 표시
        list.stream().filter(r -> r.getType() == RoomType.DIRECT)
                .forEach(r -> userIds.addAll(directUserIds(r)));
        Map<Long, User> users = userService.getAll(userIds);
        Map<Long, String> deptNames = userService.departmentNames();

        Map<Long, MessageDto> lastMessages = toMessageDtos(messages.findLastMessages(roomIds)).stream()
                .collect(Collectors.toMap(MessageDto::roomId, Function.identity()));
        Map<Long, Long> unread = new HashMap<>();
        for (Object[] row : messages.countUnread(userId)) {
            unread.put(((Number) row[0]).longValue(), ((Number) row[1]).longValue());
        }

        List<RoomDto> result = new ArrayList<>();
        for (ChatRoom r : list) {
            List<MemberDto> memberDtos = membersByRoom.getOrDefault(r.getId(), List.of()).stream()
                    .map(m -> {
                        User u = users.get(m.getUserId());
                        return new MemberDto(m.getUserId(), u.getName(), u.getPosition(),
                                deptNames.get(u.getDepartmentId()), m.getLastReadMessageId());
                    })
                    .sorted(Comparator.comparing(MemberDto::name))
                    .toList();
            String name = r.getType() == RoomType.DIRECT ? directName(userId, r, users) : groupName(userId, r, memberDtos);
            result.add(new RoomDto(r.getId(), r.getType().name(), name, memberDtos,
                    lastMessages.get(r.getId()), r.getLastMessageAt(), unread.getOrDefault(r.getId(), 0L)));
        }
        return result;
    }

    private static List<Long> directUserIds(ChatRoom r) {
        return java.util.Arrays.stream(r.getDirectKey().split(":")).map(Long::valueOf).toList();
    }

    private static String directName(Long userId, ChatRoom r, Map<Long, User> users) {
        return directUserIds(r).stream().filter(id -> !id.equals(userId)).findFirst()
                .map(id -> users.get(id).getName())
                .orElse("나와의 채팅");
    }

    private static String groupName(Long userId, ChatRoom r, List<MemberDto> memberDtos) {
        if (r.getName() != null) {
            return r.getName();
        }
        List<String> others = memberDtos.stream().filter(m -> !m.userId().equals(userId)).map(MemberDto::name).toList();
        if (others.isEmpty()) {
            return "(대화상대 없음)";
        }
        if (others.size() <= 4) {
            return String.join(", ", others);
        }
        return String.join(", ", others.subList(0, 4)) + " 외 " + (others.size() - 4) + "명";
    }
}

package com.company.messenger.chat;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.Principal;
import java.util.List;

import org.springframework.core.io.Resource;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.company.messenger.auth.CurrentUser;
import com.company.messenger.chat.ChatDtos.MessageDto;
import com.company.messenger.chat.ChatDtos.RoomDto;
import com.company.messenger.chat.ChatDtos.SearchResultDto;
import com.company.messenger.file.FileStorage;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

@RestController
@RequestMapping("/api")
public class ChatController {

    private final ChatService chat;
    private final FileStorage storage;

    public ChatController(ChatService chat, FileStorage storage) {
        this.chat = chat;
        this.storage = storage;
    }

    public record DirectRequest(@NotNull Long userId) {
    }

    public record GroupRequest(@Size(max = 100) String name, @NotEmpty List<Long> memberIds) {
    }

    public record InviteRequest(@NotEmpty List<Long> userIds) {
    }

    public record RenameRequest(@Size(max = 100) String name) {
    }

    public record SendRequest(@NotNull String content) {
    }

    public record ReadRequest(@NotNull Long messageId) {
    }

    @GetMapping("/rooms")
    public List<RoomDto> rooms(Principal p) {
        return chat.listRooms(CurrentUser.id(p));
    }

    @GetMapping("/rooms/{roomId}")
    public RoomDto room(Principal p, @PathVariable Long roomId) {
        return chat.getRoom(CurrentUser.id(p), roomId);
    }

    @PostMapping("/rooms/direct")
    public RoomDto openDirect(Principal p, @Valid @RequestBody DirectRequest req) {
        return chat.openDirect(CurrentUser.id(p), req.userId());
    }

    @PostMapping("/rooms/group")
    public RoomDto createGroup(Principal p, @Valid @RequestBody GroupRequest req) {
        return chat.createGroup(CurrentUser.id(p), req.name(), req.memberIds());
    }

    @PostMapping("/rooms/{roomId}/members")
    public RoomDto invite(Principal p, @PathVariable Long roomId, @Valid @RequestBody InviteRequest req) {
        return chat.invite(CurrentUser.id(p), roomId, req.userIds());
    }

    @PatchMapping("/rooms/{roomId}")
    public RoomDto rename(Principal p, @PathVariable Long roomId, @Valid @RequestBody RenameRequest req) {
        return chat.rename(CurrentUser.id(p), roomId, req.name());
    }

    @PostMapping("/rooms/{roomId}/leave")
    public void leave(Principal p, @PathVariable Long roomId) {
        chat.leave(CurrentUser.id(p), roomId);
    }

    @GetMapping("/rooms/{roomId}/messages")
    public List<MessageDto> messages(Principal p, @PathVariable Long roomId,
                                     @RequestParam(required = false) Long before,
                                     @RequestParam(defaultValue = "50") int size) {
        return chat.messages(CurrentUser.id(p), roomId, before, size);
    }

    @PostMapping("/rooms/{roomId}/messages")
    public MessageDto send(Principal p, @PathVariable Long roomId, @Valid @RequestBody SendRequest req) {
        return chat.sendText(CurrentUser.id(p), roomId, req.content());
    }

    @PostMapping(value = "/rooms/{roomId}/files", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public MessageDto upload(Principal p, @PathVariable Long roomId, @RequestPart("file") MultipartFile file)
            throws IOException {
        return chat.sendFile(CurrentUser.id(p), roomId, file);
    }

    @PostMapping("/rooms/{roomId}/read")
    public void read(Principal p, @PathVariable Long roomId, @Valid @RequestBody ReadRequest req) {
        chat.markRead(CurrentUser.id(p), roomId, req.messageId());
    }

    @DeleteMapping("/messages/{messageId}")
    public void delete(Principal p, @PathVariable Long messageId) {
        chat.deleteMessage(CurrentUser.id(p), messageId);
    }

    @GetMapping("/messages/search")
    public List<SearchResultDto> search(Principal p, @RequestParam String q,
                                        @RequestParam(required = false) Long roomId) {
        return chat.search(CurrentUser.id(p), q, roomId);
    }

    @GetMapping("/files/{attachmentId}")
    public ResponseEntity<Resource> download(Principal p, @PathVariable Long attachmentId) {
        Attachment att = chat.getAttachment(CurrentUser.id(p), attachmentId);
        Resource resource = storage.load(att.getStorageKey());
        if (!resource.exists()) {
            return ResponseEntity.notFound().build();
        }
        MediaType type = ChatService.IMAGE_TYPES.contains(att.getContentType())
                ? MediaType.parseMediaType(att.getContentType())
                : MediaType.APPLICATION_OCTET_STREAM;
        return ResponseEntity.ok()
                .contentType(type)
                .contentLength(att.getSize())
                .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                        .filename(att.getOriginalName(), StandardCharsets.UTF_8).build().toString())
                .header("X-Content-Type-Options", "nosniff")
                .header(HttpHeaders.CACHE_CONTROL, "private, max-age=86400")
                .body(resource);
    }
}

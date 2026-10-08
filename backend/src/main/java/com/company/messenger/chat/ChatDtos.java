package com.company.messenger.chat;

import java.time.Instant;
import java.util.List;

public final class ChatDtos {

    private ChatDtos() {
    }

    public record AttachmentDto(Long id, String name, String contentType, long size) {
    }

    public record MessageDto(Long id, Long roomId, Long senderId, String senderName, String type, String content,
                             AttachmentDto attachment, boolean deleted, Instant createdAt) {
    }

    public record MemberDto(Long userId, String name, String position, String departmentName, long lastReadMessageId) {
    }

    public record RoomDto(Long id, String type, String name, List<MemberDto> members, MessageDto lastMessage,
                          Instant lastMessageAt, long unreadCount) {
    }

    public record SearchResultDto(MessageDto message, String roomName) {
    }
}

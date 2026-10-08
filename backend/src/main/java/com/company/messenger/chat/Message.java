package com.company.messenger.chat;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "messages")
public class Message {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long roomId;

    /** SYSTEM 메시지는 null. */
    private Long senderId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private MessageType type;

    private String content;

    private Long attachmentId;

    private boolean deleted;

    @Column(nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    protected Message() {
    }

    public Message(Long roomId, Long senderId, MessageType type, String content, Long attachmentId) {
        this.roomId = roomId;
        this.senderId = senderId;
        this.type = type;
        this.content = content;
        this.attachmentId = attachmentId;
    }

    public Long getId() { return id; }
    public Long getRoomId() { return roomId; }
    public Long getSenderId() { return senderId; }
    public MessageType getType() { return type; }
    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }
    public Long getAttachmentId() { return attachmentId; }
    public boolean isDeleted() { return deleted; }
    public void setDeleted(boolean deleted) { this.deleted = deleted; }
    public Instant getCreatedAt() { return createdAt; }
}

package com.company.messenger.chat;

import java.time.Instant;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

@Entity
@Table(name = "attachments")
public class Attachment {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private Long roomId;

    @Column(nullable = false)
    private Long uploaderId;

    @Column(nullable = false)
    private String originalName;

    @Column(nullable = false)
    private String contentType;

    private long size;

    @Column(nullable = false)
    private String storageKey;

    @Column(nullable = false, updatable = false)
    private Instant createdAt = Instant.now();

    protected Attachment() {
    }

    public Attachment(Long roomId, Long uploaderId, String originalName, String contentType, long size, String storageKey) {
        this.roomId = roomId;
        this.uploaderId = uploaderId;
        this.originalName = originalName;
        this.contentType = contentType;
        this.size = size;
        this.storageKey = storageKey;
    }

    public Long getId() { return id; }
    public Long getRoomId() { return roomId; }
    public Long getUploaderId() { return uploaderId; }
    public String getOriginalName() { return originalName; }
    public String getContentType() { return contentType; }
    public long getSize() { return size; }
    public String getStorageKey() { return storageKey; }
    public Instant getCreatedAt() { return createdAt; }
}

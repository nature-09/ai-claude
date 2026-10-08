package com.company.messenger.chat;

import java.io.Serializable;
import java.time.Instant;
import java.util.Objects;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;

@Entity
@Table(name = "room_members")
@IdClass(RoomMember.Key.class)
public class RoomMember {

    @Id
    private Long roomId;

    @Id
    private Long userId;

    private long lastReadMessageId;

    @Column(nullable = false, updatable = false)
    private Instant joinedAt = Instant.now();

    protected RoomMember() {
    }

    public RoomMember(Long roomId, Long userId, long lastReadMessageId) {
        this.roomId = roomId;
        this.userId = userId;
        this.lastReadMessageId = lastReadMessageId;
    }

    public Long getRoomId() { return roomId; }
    public Long getUserId() { return userId; }
    public long getLastReadMessageId() { return lastReadMessageId; }
    public void setLastReadMessageId(long lastReadMessageId) { this.lastReadMessageId = lastReadMessageId; }
    public Instant getJoinedAt() { return joinedAt; }

    public static class Key implements Serializable {
        private Long roomId;
        private Long userId;

        public Key() {
        }

        public Key(Long roomId, Long userId) {
            this.roomId = roomId;
            this.userId = userId;
        }

        @Override
        public boolean equals(Object o) {
            return o instanceof Key k && Objects.equals(roomId, k.roomId) && Objects.equals(userId, k.userId);
        }

        @Override
        public int hashCode() {
            return Objects.hash(roomId, userId);
        }
    }
}

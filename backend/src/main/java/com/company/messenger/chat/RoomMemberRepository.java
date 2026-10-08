package com.company.messenger.chat;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface RoomMemberRepository extends JpaRepository<RoomMember, RoomMember.Key> {

    List<RoomMember> findByRoomId(Long roomId);

    List<RoomMember> findByRoomIdIn(Collection<Long> roomIds);

    Optional<RoomMember> findByRoomIdAndUserId(Long roomId, Long userId);

    boolean existsByRoomIdAndUserId(Long roomId, Long userId);

    @Query("select m.userId from RoomMember m where m.roomId = :roomId")
    List<Long> findUserIds(@Param("roomId") Long roomId);

    @Modifying(flushAutomatically = true, clearAutomatically = true)
    @Query("update RoomMember m set m.lastReadMessageId = :messageId "
            + "where m.roomId = :roomId and m.userId = :userId and m.lastReadMessageId < :messageId")
    int markRead(@Param("roomId") Long roomId, @Param("userId") Long userId, @Param("messageId") long messageId);
}

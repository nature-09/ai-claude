package com.company.messenger.chat;

import java.util.List;
import java.util.Optional;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ChatRoomRepository extends JpaRepository<ChatRoom, Long> {

    Optional<ChatRoom> findByDirectKey(String directKey);

    @Query("select r from ChatRoom r, RoomMember m where m.roomId = r.id and m.userId = :userId order by r.lastMessageAt desc")
    List<ChatRoom> findByMember(@Param("userId") Long userId);
}

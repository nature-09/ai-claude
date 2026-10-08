package com.company.messenger.chat;

import java.util.Collection;
import java.util.List;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface MessageRepository extends JpaRepository<Message, Long> {

    @Query("select m from Message m where m.roomId = :roomId and m.id < :before order by m.id desc")
    List<Message> findPage(@Param("roomId") Long roomId, @Param("before") long before, Pageable pageable);

    @Query(value = "select distinct on (room_id) * from messages where room_id in (:roomIds) order by room_id, id desc",
            nativeQuery = true)
    List<Message> findLastMessages(@Param("roomIds") Collection<Long> roomIds);

    /** 방별 안 읽은 메시지 수 (내가 보낸 것, 시스템 메시지 제외). [room_id, count] */
    @Query(value = """
            select rm.room_id, count(m.id)
            from room_members rm
            join messages m on m.room_id = rm.room_id
                           and m.id > rm.last_read_message_id
                           and m.type <> 'SYSTEM'
                           and m.sender_id <> rm.user_id
            where rm.user_id = :userId
            group by rm.room_id
            """, nativeQuery = true)
    List<Object[]> countUnread(@Param("userId") Long userId);

    @Query(value = """
            select m.* from messages m
            join room_members rm on rm.room_id = m.room_id and rm.user_id = :userId
            where m.deleted = false
              and m.type in ('TEXT', 'FILE', 'IMAGE')
              and m.content ilike concat('%', :q, '%')
              and (:roomId = 0 or m.room_id = :roomId)
            order by m.id desc
            limit 100
            """, nativeQuery = true)
    List<Message> search(@Param("userId") Long userId, @Param("q") String q, @Param("roomId") long roomId);
}

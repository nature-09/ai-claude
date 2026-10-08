package com.company.messenger.realtime;

import java.util.Collection;
import java.util.List;
import java.util.Map;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.Message;
import org.springframework.data.redis.connection.MessageListener;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.support.TransactionSynchronization;
import org.springframework.transaction.support.TransactionSynchronizationManager;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/**
 * 실시간 이벤트 발행기.
 * <p>
 * 이벤트를 Redis Pub/Sub 채널로 발행하고, 모든 Pod 가 이를 구독하여 자기 Pod 에 접속한 WebSocket 세션에만 전달한다.
 * 따라서 백엔드 Pod 를 여러 개로 수평 확장해도 sticky session 없이 동작한다.
 */
@Component
public class EventPublisher implements MessageListener {

    public static final String CHANNEL = "messenger:events";
    private static final Logger log = LoggerFactory.getLogger(EventPublisher.class);

    private final StringRedisTemplate redis;
    private final SimpMessagingTemplate messaging;
    private final ObjectMapper mapper;

    public EventPublisher(StringRedisTemplate redis, SimpMessagingTemplate messaging, ObjectMapper mapper) {
        this.redis = redis;
        this.messaging = messaging;
        this.mapper = mapper;
    }

    /** 이벤트 봉투. users 가 null 이면 전체 브로드캐스트. */
    record Envelope(List<Long> users, Object payload) {
    }

    /** 지정한 사용자들에게 이벤트 전송. 트랜잭션 안에서 호출되면 커밋 이후에 전송한다. */
    public void toUsers(Collection<Long> userIds, String type, Map<String, ?> data) {
        publish(new Envelope(List.copyOf(userIds), event(type, data)));
    }

    /** 접속한 모든 사용자에게 이벤트 전송. */
    public void broadcast(String type, Map<String, ?> data) {
        publish(new Envelope(null, event(type, data)));
    }

    private static Map<String, Object> event(String type, Map<String, ?> data) {
        return Map.of("type", type, "data", data);
    }

    private void publish(Envelope envelope) {
        final String json;
        try {
            json = mapper.writeValueAsString(envelope);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException(e);
        }
        if (TransactionSynchronizationManager.isSynchronizationActive()) {
            TransactionSynchronizationManager.registerSynchronization(new TransactionSynchronization() {
                @Override
                public void afterCommit() {
                    send(json);
                }
            });
        } else {
            send(json);
        }
    }

    private void send(String json) {
        try {
            redis.convertAndSend(CHANNEL, json);
        } catch (Exception e) {
            log.warn("Redis 이벤트 발행 실패: {}", e.getMessage());
        }
    }

    /** Redis 에서 수신한 이벤트를 이 Pod 의 WebSocket 세션으로 전달. */
    @Override
    public void onMessage(Message message, byte[] pattern) {
        try {
            JsonNode node = mapper.readTree(message.getBody());
            JsonNode payload = node.get("payload");
            JsonNode users = node.get("users");
            if (users == null || users.isNull()) {
                messaging.convertAndSend("/topic/events", payload);
            } else {
                for (JsonNode uid : users) {
                    messaging.convertAndSendToUser(uid.asText(), "/queue/events", payload);
                }
            }
        } catch (Exception e) {
            log.warn("이벤트 전달 실패", e);
        }
    }
}

package com.company.messenger.realtime;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.event.EventListener;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.web.socket.messaging.SessionConnectedEvent;
import org.springframework.web.socket.messaging.SessionDisconnectEvent;

import com.company.messenger.config.AppProperties;

/**
 * 접속 상태(온라인/오프라인) 관리.
 * <p>
 * Redis 구조
 * <ul>
 *   <li>presence:online (SET) - 온라인 사용자 ID</li>
 *   <li>presence:sessions:{userId} (HASH) - sessionId → 만료시각(epoch sec)</li>
 * </ul>
 * 각 Pod 는 자기 세션의 만료시각을 주기적으로 갱신하고, Pod 가 비정상 종료되어 남은 세션은 만료 후 정리된다.
 */
@Service
public class PresenceService {

    private static final Logger log = LoggerFactory.getLogger(PresenceService.class);
    private static final String ONLINE = "presence:online";

    private final StringRedisTemplate redis;
    private final EventPublisher events;
    private final int ttlSeconds;

    /** 이 Pod 에 연결된 세션: sessionId → userId */
    private final Map<String, String> localSessions = new ConcurrentHashMap<>();

    public PresenceService(StringRedisTemplate redis, EventPublisher events, AppProperties props) {
        this.redis = redis;
        this.events = events;
        this.ttlSeconds = props.presence().sessionTtlSeconds();
    }

    private static String sessionsKey(String userId) {
        return "presence:sessions:" + userId;
    }

    private String expiry() {
        return String.valueOf(Instant.now().getEpochSecond() + ttlSeconds);
    }

    @EventListener
    public void onConnected(SessionConnectedEvent event) {
        if (event.getUser() == null) {
            return;
        }
        String userId = event.getUser().getName();
        String sessionId = (String) event.getMessage().getHeaders().get("simpSessionId");
        localSessions.put(sessionId, userId);
        redis.opsForHash().put(sessionsKey(userId), sessionId, expiry());
        Long added = redis.opsForSet().add(ONLINE, userId);
        if (added != null && added > 0) {
            events.broadcast("PRESENCE", Map.of("userId", Long.valueOf(userId), "online", true));
        }
    }

    @EventListener
    public void onDisconnected(SessionDisconnectEvent event) {
        String userId = localSessions.remove(event.getSessionId());
        if (userId == null) {
            return;
        }
        redis.opsForHash().delete(sessionsKey(userId), event.getSessionId());
        markOfflineIfNoSessions(userId);
    }

    private void markOfflineIfNoSessions(String userId) {
        Long size = redis.opsForHash().size(sessionsKey(userId));
        if (size == null || size == 0) {
            Long removed = redis.opsForSet().remove(ONLINE, userId);
            if (removed != null && removed > 0) {
                events.broadcast("PRESENCE", Map.of("userId", Long.valueOf(userId), "online", false));
            }
        }
    }

    /** 이 Pod 의 세션 만료시각 갱신. */
    @Scheduled(fixedDelay = 30_000)
    public void heartbeat() {
        String exp = expiry();
        localSessions.forEach((sessionId, userId) -> redis.opsForHash().put(sessionsKey(userId), sessionId, exp));
    }

    /** 비정상 종료된 Pod 가 남긴 만료 세션 정리. */
    @Scheduled(fixedDelay = 60_000, initialDelay = 60_000)
    public void cleanup() {
        try {
            Set<String> online = redis.opsForSet().members(ONLINE);
            if (online == null) {
                return;
            }
            long now = Instant.now().getEpochSecond();
            for (String userId : online) {
                Map<Object, Object> sessions = redis.opsForHash().entries(sessionsKey(userId));
                sessions.forEach((sid, exp) -> {
                    if (Long.parseLong((String) exp) < now) {
                        redis.opsForHash().delete(sessionsKey(userId), sid);
                    }
                });
                markOfflineIfNoSessions(userId);
            }
        } catch (Exception e) {
            log.warn("presence cleanup 실패: {}", e.getMessage());
        }
    }

    public List<Long> onlineUserIds() {
        Set<String> online = redis.opsForSet().members(ONLINE);
        return online == null ? List.of() : online.stream().map(Long::valueOf).toList();
    }
}

package com.company.messenger.auth;

import java.time.Duration;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;

/** 아이디별 로그인 실패 횟수를 Redis 에 기록하여 무차별 대입을 막는다 (모든 Pod 공유). */
@Service
public class LoginAttemptService {

    private static final int MAX_FAILURES = 5;
    private static final Duration LOCK_DURATION = Duration.ofMinutes(10);

    private final StringRedisTemplate redis;

    public LoginAttemptService(StringRedisTemplate redis) {
        this.redis = redis;
    }

    private static String key(String username) {
        return "login:fail:" + username.toLowerCase();
    }

    public boolean isBlocked(String username) {
        String v = redis.opsForValue().get(key(username));
        return v != null && Integer.parseInt(v) >= MAX_FAILURES;
    }

    public void failed(String username) {
        Long count = redis.opsForValue().increment(key(username));
        if (count != null && count == 1) {
            redis.expire(key(username), LOCK_DURATION);
        }
    }

    public void succeeded(String username) {
        redis.delete(key(username));
    }
}

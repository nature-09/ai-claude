package com.company.messenger.realtime;

import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.MessageDeliveryException;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoder;
import org.springframework.security.oauth2.jwt.JwtException;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.stereotype.Component;

import com.company.messenger.user.UserRepository;

/**
 * STOMP CONNECT 시 Authorization 헤더의 JWT 를 검증하고, 구독 가능한 destination 을 제한한다.
 */
@Component
public class StompAuthInterceptor implements ChannelInterceptor {

    private final JwtDecoder jwtDecoder;
    private final JwtAuthenticationConverter converter;
    private final UserRepository users;

    public StompAuthInterceptor(JwtDecoder jwtDecoder, JwtAuthenticationConverter converter, UserRepository users) {
        this.jwtDecoder = jwtDecoder;
        this.converter = converter;
        this.users = users;
    }

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);
        if (accessor == null || accessor.getCommand() == null) {
            return message;
        }
        StompCommand command = accessor.getCommand();
        if (command == StompCommand.CONNECT) {
            String header = accessor.getFirstNativeHeader("Authorization");
            if (header == null || !header.startsWith("Bearer ")) {
                throw new MessageDeliveryException("인증 토큰이 없습니다.");
            }
            Jwt jwt;
            try {
                jwt = jwtDecoder.decode(header.substring(7));
            } catch (JwtException e) {
                throw new MessageDeliveryException("유효하지 않은 토큰입니다.");
            }
            boolean active = users.findById(Long.valueOf(jwt.getSubject())).map(u -> u.isActive()).orElse(false);
            if (!active) {
                throw new MessageDeliveryException("비활성화된 계정입니다.");
            }
            accessor.setUser(converter.convert(jwt));
        } else if (command == StompCommand.SUBSCRIBE) {
            String dest = accessor.getDestination();
            boolean allowed = "/user/queue/events".equals(dest) || "/topic/events".equals(dest);
            if (accessor.getUser() == null || !allowed) {
                throw new MessageDeliveryException("구독할 수 없는 destination 입니다: " + dest);
            }
        } else if (command == StompCommand.SEND) {
            // 메시지 전송은 REST API 를 사용한다.
            throw new MessageDeliveryException("SEND 는 지원하지 않습니다.");
        }
        return message;
    }
}

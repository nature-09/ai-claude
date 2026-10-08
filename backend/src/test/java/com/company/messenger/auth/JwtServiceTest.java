package com.company.messenger.auth;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.lang.reflect.Field;
import java.util.List;

import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtException;

import com.company.messenger.config.AppProperties;
import com.company.messenger.user.Role;
import com.company.messenger.user.User;

class JwtServiceTest {

    private static AppProperties props(String secret) {
        return new AppProperties(new AppProperties.Jwt(secret, 1), null, new AppProperties.Websocket(List.of("*")),
                null, null);
    }

    private static User user(long id) throws Exception {
        User u = new User();
        Field f = User.class.getDeclaredField("id");
        f.setAccessible(true);
        f.set(u, id);
        u.setUsername("kim");
        u.setRole(Role.ADMIN);
        return u;
    }

    @Test
    void issuedTokenDecodesWithUserIdAsSubject() throws Exception {
        JwtService service = new JwtService(props("0123456789abcdef0123456789abcdef"));
        Jwt jwt = service.decoder().decode(service.issue(user(42)));
        assertThat(jwt.getSubject()).isEqualTo("42");
        assertThat(jwt.getClaimAsString("role")).isEqualTo("ADMIN");
        assertThat(jwt.getClaimAsString("username")).isEqualTo("kim");
    }

    @Test
    void tokenSignedWithOtherSecretIsRejected() throws Exception {
        JwtService a = new JwtService(props("0123456789abcdef0123456789abcdef"));
        JwtService b = new JwtService(props("fedcba9876543210fedcba9876543210"));
        String token = a.issue(user(1));
        assertThatThrownBy(() -> b.decoder().decode(token)).isInstanceOf(JwtException.class);
    }

    @Test
    void shortSecretIsRejected() {
        assertThatThrownBy(() -> new JwtService(props("short"))).isInstanceOf(IllegalStateException.class);
    }
}

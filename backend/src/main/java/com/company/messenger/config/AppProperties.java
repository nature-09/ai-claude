package com.company.messenger.config;

import java.util.List;

import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "app")
public record AppProperties(Jwt jwt, Admin admin, Websocket websocket, Files files, Presence presence) {

    public record Jwt(String secret, int ttlHours) {
    }

    public record Admin(String username, String password) {
    }

    public record Websocket(List<String> allowedOrigins) {
    }

    public record Files(String storagePath, List<String> blockedExtensions) {
    }

    public record Presence(int sessionTtlSeconds) {
    }
}

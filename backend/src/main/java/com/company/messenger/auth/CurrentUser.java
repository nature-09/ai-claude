package com.company.messenger.auth;

import java.security.Principal;

public final class CurrentUser {

    private CurrentUser() {
    }

    /** JWT 의 subject 가 사용자 ID 이므로 Principal 이름이 곧 사용자 ID 이다. */
    public static Long id(Principal principal) {
        return Long.valueOf(principal.getName());
    }
}

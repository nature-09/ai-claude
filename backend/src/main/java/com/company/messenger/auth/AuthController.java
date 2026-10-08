package com.company.messenger.auth;

import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.company.messenger.common.ApiException;
import com.company.messenger.user.User;
import com.company.messenger.user.UserDto;
import com.company.messenger.user.UserRepository;
import com.company.messenger.user.UserService;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final UserRepository users;
    private final UserService userService;
    private final PasswordEncoder passwordEncoder;
    private final JwtService jwtService;
    private final LoginAttemptService loginAttempts;

    public AuthController(UserRepository users, UserService userService, PasswordEncoder passwordEncoder,
                          JwtService jwtService, LoginAttemptService loginAttempts) {
        this.users = users;
        this.userService = userService;
        this.passwordEncoder = passwordEncoder;
        this.jwtService = jwtService;
        this.loginAttempts = loginAttempts;
    }

    public record LoginRequest(@NotBlank String username, @NotBlank String password) {
    }

    public record LoginResponse(String token, UserDto user) {
    }

    @PostMapping("/login")
    public LoginResponse login(@Valid @RequestBody LoginRequest req) {
        String username = req.username().trim();
        if (loginAttempts.isBlocked(username)) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "로그인 시도가 너무 많습니다. 잠시 후 다시 시도하세요.");
        }
        User user = users.findByUsername(username)
                .filter(u -> passwordEncoder.matches(req.password(), u.getPasswordHash()))
                .orElse(null);
        if (user == null) {
            loginAttempts.failed(username);
            throw new ApiException(HttpStatus.UNAUTHORIZED, "아이디 또는 비밀번호가 올바르지 않습니다.");
        }
        if (!user.isActive()) {
            throw new ApiException(HttpStatus.FORBIDDEN, "비활성화된 계정입니다. 관리자에게 문의하세요.");
        }
        loginAttempts.succeeded(username);
        return new LoginResponse(jwtService.issue(user), userService.toDto(user));
    }
}

package com.company.messenger.config;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import com.company.messenger.user.Role;
import com.company.messenger.user.User;
import com.company.messenger.user.UserRepository;

/** 관리자 계정이 하나도 없으면 초기 관리자 계정을 만든다. */
@Component
public class DataInitializer implements ApplicationRunner {

    private static final Logger log = LoggerFactory.getLogger(DataInitializer.class);

    private final UserRepository users;
    private final PasswordEncoder passwordEncoder;
    private final AppProperties props;

    public DataInitializer(UserRepository users, PasswordEncoder passwordEncoder, AppProperties props) {
        this.users = users;
        this.passwordEncoder = passwordEncoder;
        this.props = props;
    }

    @Override
    public void run(ApplicationArguments args) {
        if (users.existsByRole(Role.ADMIN) || users.existsByUsername(props.admin().username())) {
            return;
        }
        User admin = new User();
        admin.setUsername(props.admin().username());
        admin.setName("관리자");
        admin.setRole(Role.ADMIN);
        admin.setPasswordHash(passwordEncoder.encode(props.admin().password()));
        try {
            users.save(admin);
            log.info("초기 관리자 계정 '{}' 생성 완료. 로그인 후 비밀번호를 변경하세요.", admin.getUsername());
        } catch (DataIntegrityViolationException e) {
            // 여러 Pod 가 동시에 기동한 경우 - 다른 Pod 가 먼저 생성함
            log.info("초기 관리자 계정이 이미 생성되었습니다.");
        }
    }
}

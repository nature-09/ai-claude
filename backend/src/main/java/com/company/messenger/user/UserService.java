package com.company.messenger.user;

import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

import org.springframework.data.domain.PageRequest;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.company.messenger.common.ApiException;

@Service
public class UserService {

    private final UserRepository users;
    private final DepartmentRepository departments;
    private final PasswordEncoder passwordEncoder;

    public UserService(UserRepository users, DepartmentRepository departments, PasswordEncoder passwordEncoder) {
        this.users = users;
        this.departments = departments;
        this.passwordEncoder = passwordEncoder;
    }

    public User get(Long id) {
        return users.findById(id).orElseThrow(() -> ApiException.notFound("사용자를 찾을 수 없습니다."));
    }

    public Map<Long, User> getAll(Collection<Long> ids) {
        return users.findAllById(ids).stream().collect(Collectors.toMap(User::getId, Function.identity()));
    }

    public Map<Long, String> departmentNames() {
        return departments.findAll().stream().collect(Collectors.toMap(Department::getId, Department::getName));
    }

    public UserDto toDto(User u) {
        String dept = u.getDepartmentId() == null ? null
                : departments.findById(u.getDepartmentId()).map(Department::getName).orElse(null);
        return UserDto.of(u, dept);
    }

    public List<UserDto> toDtos(Collection<User> list) {
        Map<Long, String> names = departmentNames();
        return list.stream().map(u -> UserDto.of(u, names.get(u.getDepartmentId()))).toList();
    }

    public List<UserDto> search(String q) {
        String query = q == null ? "" : q.trim();
        if (query.isEmpty()) {
            return List.of();
        }
        return toDtos(users.search(query, PageRequest.of(0, 50)));
    }

    public List<UserDto> byDepartment(Long departmentId) {
        return toDtos(users.findByDepartmentIdAndActiveTrueOrderByNameAsc(departmentId));
    }

    @Transactional
    public UserDto updateProfile(Long userId, String statusMessage, String phone, String email) {
        User u = get(userId);
        if (statusMessage != null) u.setStatusMessage(statusMessage.isBlank() ? null : statusMessage.trim());
        if (phone != null) u.setPhone(phone.isBlank() ? null : phone.trim());
        if (email != null) u.setEmail(email.isBlank() ? null : email.trim());
        return toDto(u);
    }

    @Transactional
    public void changePassword(Long userId, String currentPassword, String newPassword) {
        User u = get(userId);
        if (!passwordEncoder.matches(currentPassword, u.getPasswordHash())) {
            throw ApiException.badRequest("현재 비밀번호가 올바르지 않습니다.");
        }
        validatePassword(newPassword);
        u.setPasswordHash(passwordEncoder.encode(newPassword));
    }

    public static void validatePassword(String password) {
        if (password == null || password.length() < 8) {
            throw ApiException.badRequest("비밀번호는 8자 이상이어야 합니다.");
        }
    }
}

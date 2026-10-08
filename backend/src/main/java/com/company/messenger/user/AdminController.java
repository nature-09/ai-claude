package com.company.messenger.user;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import com.company.messenger.common.ApiException;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

/** 관리자 전용 API (/api/admin/** 는 ROLE_ADMIN 만 접근 가능 - SecurityConfig 참고). */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final UserRepository users;
    private final DepartmentRepository departments;
    private final UserService userService;
    private final PasswordEncoder passwordEncoder;

    public AdminController(UserRepository users, DepartmentRepository departments, UserService userService,
                           PasswordEncoder passwordEncoder) {
        this.users = users;
        this.departments = departments;
        this.userService = userService;
        this.passwordEncoder = passwordEncoder;
    }

    public record UserRequest(
            @NotBlank @Size(max = 50) @Pattern(regexp = "^[A-Za-z0-9._-]+$", message = "영문/숫자/._- 만 사용 가능합니다.") String username,
            String password,
            @NotBlank @Size(max = 50) String name,
            @Size(max = 100) String email,
            @Size(max = 30) String phone,
            @Size(max = 50) String position,
            Long departmentId,
            Role role,
            Boolean active) {
    }

    public record PasswordResetRequest(@NotBlank String password) {
    }

    public record DepartmentRequest(@NotBlank @Size(max = 100) String name, Long parentId, Integer sortOrder) {
    }

    public record PageResponse<T>(List<T> content, long totalElements, int totalPages, int page) {
    }

    public record ImportResult(int created, int skipped, List<String> errors) {
    }

    // ---------- 사용자 ----------

    @GetMapping("/users")
    public PageResponse<UserDto> listUsers(@RequestParam(defaultValue = "") String q,
                                           @RequestParam(defaultValue = "0") int page,
                                           @RequestParam(defaultValue = "50") int size) {
        Page<User> result = users.adminSearch(q.trim(), PageRequest.of(page, Math.min(size, 200), Sort.by("name")));
        return new PageResponse<>(userService.toDtos(result.getContent()), result.getTotalElements(),
                result.getTotalPages(), page);
    }

    @PostMapping("/users")
    @Transactional
    public UserDto createUser(@Valid @RequestBody UserRequest req) {
        if (users.existsByUsername(req.username())) {
            throw new ApiException(HttpStatus.CONFLICT, "이미 존재하는 아이디입니다.");
        }
        UserService.validatePassword(req.password());
        User u = new User();
        u.setUsername(req.username());
        u.setPasswordHash(passwordEncoder.encode(req.password()));
        apply(u, req);
        return userService.toDto(users.save(u));
    }

    @PutMapping("/users/{id}")
    @Transactional
    public UserDto updateUser(@PathVariable Long id, @Valid @RequestBody UserRequest req) {
        User u = userService.get(id);
        if (!u.getUsername().equals(req.username())) {
            if (users.existsByUsername(req.username())) {
                throw new ApiException(HttpStatus.CONFLICT, "이미 존재하는 아이디입니다.");
            }
            u.setUsername(req.username());
        }
        apply(u, req);
        return userService.toDto(u);
    }

    @PostMapping("/users/{id}/reset-password")
    @Transactional
    public void resetPassword(@PathVariable Long id, @Valid @RequestBody PasswordResetRequest req) {
        UserService.validatePassword(req.password());
        userService.get(id).setPasswordHash(passwordEncoder.encode(req.password()));
    }

    /**
     * CSV 일괄 등록. 헤더 1행 포함, UTF-8.
     * 컬럼: username,name,password,department,position,email,phone
     */
    @PostMapping("/users/import")
    @Transactional
    public ImportResult importUsers(@RequestPart("file") MultipartFile file) throws IOException {
        int created = 0;
        int skipped = 0;
        List<String> errors = new ArrayList<>();
        Map<String, Long> deptCache = new java.util.HashMap<>();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(file.getInputStream(), StandardCharsets.UTF_8))) {
            String line;
            int lineNo = 0;
            while ((line = reader.readLine()) != null) {
                lineNo++;
                if (lineNo == 1) {
                    continue; // header
                }
                if (line.isBlank()) {
                    continue;
                }
                String[] cols = line.replace("﻿", "").split(",", -1);
                if (cols.length < 3) {
                    errors.add(lineNo + "행: 컬럼 수 부족");
                    continue;
                }
                String username = cols[0].trim();
                if (!username.matches("^[A-Za-z0-9._-]+$")) {
                    errors.add(lineNo + "행: 잘못된 아이디 '" + username + "'");
                    continue;
                }
                if (users.existsByUsername(username)) {
                    skipped++;
                    continue;
                }
                String password = cols[2].trim();
                if (password.length() < 8) {
                    errors.add(lineNo + "행: 비밀번호는 8자 이상");
                    continue;
                }
                User u = new User();
                u.setUsername(username);
                u.setName(cols[1].trim());
                u.setPasswordHash(passwordEncoder.encode(password));
                if (cols.length > 3 && !cols[3].isBlank()) {
                    String deptName = cols[3].trim();
                    u.setDepartmentId(deptCache.computeIfAbsent(deptName, n -> departments.findFirstByName(n)
                            .orElseGet(() -> {
                                Department d = new Department();
                                d.setName(n);
                                return departments.save(d);
                            }).getId()));
                }
                if (cols.length > 4) u.setPosition(blankToNull(cols[4]));
                if (cols.length > 5) u.setEmail(blankToNull(cols[5]));
                if (cols.length > 6) u.setPhone(blankToNull(cols[6]));
                users.save(u);
                created++;
            }
        }
        return new ImportResult(created, skipped, errors);
    }

    private static String blankToNull(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private void apply(User u, UserRequest req) {
        u.setName(req.name());
        u.setEmail(blankToNull(req.email()));
        u.setPhone(blankToNull(req.phone()));
        u.setPosition(blankToNull(req.position()));
        if (req.departmentId() != null && !departments.existsById(req.departmentId())) {
            throw ApiException.badRequest("존재하지 않는 부서입니다.");
        }
        u.setDepartmentId(req.departmentId());
        if (req.role() != null) u.setRole(req.role());
        if (req.active() != null) u.setActive(req.active());
    }

    // ---------- 부서 ----------

    @PostMapping("/departments")
    @Transactional
    public UserController.DepartmentDto createDepartment(@Valid @RequestBody DepartmentRequest req) {
        Department d = new Department();
        applyDept(d, req);
        d = departments.save(d);
        return new UserController.DepartmentDto(d.getId(), d.getName(), d.getParentId(), d.getSortOrder());
    }

    @PutMapping("/departments/{id}")
    @Transactional
    public UserController.DepartmentDto updateDepartment(@PathVariable Long id, @Valid @RequestBody DepartmentRequest req) {
        Department d = departments.findById(id).orElseThrow(() -> ApiException.notFound("부서를 찾을 수 없습니다."));
        if (id.equals(req.parentId())) {
            throw ApiException.badRequest("자기 자신을 상위 부서로 지정할 수 없습니다.");
        }
        applyDept(d, req);
        return new UserController.DepartmentDto(d.getId(), d.getName(), d.getParentId(), d.getSortOrder());
    }

    @DeleteMapping("/departments/{id}")
    @Transactional
    public void deleteDepartment(@PathVariable Long id) {
        if (departments.existsByParentId(id) || users.countByDepartmentId(id) > 0) {
            throw ApiException.badRequest("하위 부서나 소속 사용자가 있는 부서는 삭제할 수 없습니다.");
        }
        departments.deleteById(id);
    }

    private void applyDept(Department d, DepartmentRequest req) {
        if (req.parentId() != null && !departments.existsById(req.parentId())) {
            throw ApiException.badRequest("존재하지 않는 상위 부서입니다.");
        }
        d.setName(req.name().trim());
        d.setParentId(req.parentId());
        d.setSortOrder(req.sortOrder() == null ? 0 : req.sortOrder());
    }
}

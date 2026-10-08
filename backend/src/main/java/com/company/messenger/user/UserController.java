package com.company.messenger.user;

import java.util.List;

import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.company.messenger.auth.CurrentUser;
import com.company.messenger.realtime.PresenceService;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

@RestController
@RequestMapping("/api")
public class UserController {

    private final UserService userService;
    private final DepartmentRepository departments;
    private final PresenceService presence;

    public UserController(UserService userService, DepartmentRepository departments, PresenceService presence) {
        this.userService = userService;
        this.departments = departments;
        this.presence = presence;
    }

    public record ProfileRequest(@Size(max = 100) String statusMessage, @Size(max = 30) String phone,
                                 @Size(max = 100) String email) {
    }

    public record PasswordRequest(@NotBlank String currentPassword, @NotBlank String newPassword) {
    }

    public record DepartmentDto(Long id, String name, Long parentId, int sortOrder) {
        static DepartmentDto of(Department d) {
            return new DepartmentDto(d.getId(), d.getName(), d.getParentId(), d.getSortOrder());
        }
    }

    @GetMapping("/users/me")
    public UserDto me(Authentication auth) {
        return userService.toDto(userService.get(CurrentUser.id(auth)));
    }

    @PatchMapping("/users/me")
    public UserDto updateMe(Authentication auth, @jakarta.validation.Valid @RequestBody ProfileRequest req) {
        return userService.updateProfile(CurrentUser.id(auth), req.statusMessage(), req.phone(), req.email());
    }

    @PostMapping("/users/me/password")
    public void changePassword(Authentication auth, @jakarta.validation.Valid @RequestBody PasswordRequest req) {
        userService.changePassword(CurrentUser.id(auth), req.currentPassword(), req.newPassword());
    }

    @GetMapping("/users")
    public List<UserDto> search(@RequestParam(defaultValue = "") String q) {
        return userService.search(q);
    }

    @GetMapping("/users/{id}")
    public UserDto get(@PathVariable Long id) {
        return userService.toDto(userService.get(id));
    }

    @GetMapping("/departments")
    public List<DepartmentDto> departments() {
        return departments.findAllByOrderBySortOrderAscNameAsc().stream().map(DepartmentDto::of).toList();
    }

    @GetMapping("/departments/{id}/users")
    public List<UserDto> departmentUsers(@PathVariable Long id) {
        return userService.byDepartment(id);
    }

    @GetMapping("/presence")
    public List<Long> onlineUsers() {
        return presence.onlineUserIds();
    }
}

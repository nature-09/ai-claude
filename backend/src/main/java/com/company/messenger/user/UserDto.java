package com.company.messenger.user;

public record UserDto(
        Long id,
        String username,
        String name,
        String email,
        String phone,
        String position,
        Long departmentId,
        String departmentName,
        String role,
        String statusMessage,
        boolean active) {

    public static UserDto of(User u, String departmentName) {
        return new UserDto(u.getId(), u.getUsername(), u.getName(), u.getEmail(), u.getPhone(), u.getPosition(),
                u.getDepartmentId(), departmentName, u.getRole().name(), u.getStatusMessage(), u.isActive());
    }
}

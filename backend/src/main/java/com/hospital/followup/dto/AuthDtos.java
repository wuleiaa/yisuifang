package com.hospital.followup.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.util.Set;

public final class AuthDtos {

    private AuthDtos() {
    }

    public record LoginRequest(
            @NotBlank(message = "请输入工号")
            @Size(max = 50, message = "工号长度不合法")
            String staffNo,

            @NotBlank(message = "请输入密码")
            @Size(min = 6, max = 100, message = "密码长度不合法")
            String password
    ) {
    }

    public record LoginResponse(
            String token,
            long expiresInSeconds,
            StaffProfile profile
    ) {
    }

    /**
     * 修改自己的密码。
     *
     * 说明：只有本人知道原密码才能改。管理员那边是"重置"（不需要原密码，
     * 但只能得到一个一次性新密码），两者是不同性质的操作用来做不同的事。
     */
    public record ChangePasswordRequest(
            @NotBlank(message = "请输入原密码")
            @Size(max = 100, message = "原密码过长")
            String oldPassword,

            @NotBlank(message = "请输入新密码")
            @Size(min = 8, max = 100, message = "新密码至少 8 位")
            String newPassword
    ) {
    }

    public record StaffProfile(
            Long staffId,
            String staffNo,
            String name,
            String title,
            Long deptId,
            String deptName,
            boolean manager,
            /** 是否为管理员（可进入管理后台） */
            boolean admin,
            /** 角色编码，如 SUPER_ADMIN / DEPT_MANAGER / DOCTOR / NURSE */
            Set<String> roles,
            boolean mustChangePassword,
            Set<String> permissions
    ) {
    }
}

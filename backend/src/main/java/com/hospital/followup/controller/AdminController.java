package com.hospital.followup.controller;

import com.hospital.followup.common.ApiResponse;
import com.hospital.followup.dto.AdminDtos;
import com.hospital.followup.service.AdminService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.List;

/**
 * 管理后台接口（员工与账号管理）。
 *
 * SecurityConfig 已限定 /api/admin/** 必须是医护身份，
 * 这里再由 AdminService 判断"是不是管理员"以及"能管哪些人"。
 */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final AdminService adminService;

    public AdminController(AdminService adminService) {
        this.adminService = adminService;
    }

    @GetMapping("/overview")
    public ApiResponse<AdminDtos.Overview> overview() {
        return ApiResponse.ok(adminService.overview());
    }

    /**
     * 账号列表 / 查找账号。
     * keyword 支持工号、姓名、手机号脱敏值；roleCode 按角色筛；status 按启用状态筛。
     */
    @GetMapping("/staff")
    public ApiResponse<AdminDtos.StaffList> staff(@RequestParam(required = false) String keyword,
                                                  @RequestParam(required = false) String roleCode,
                                                  @RequestParam(required = false) String status) {
        return ApiResponse.ok(adminService.listStaff(keyword, roleCode, status));
    }

    /** 可选角色 */
    @GetMapping("/roles")
    public ApiResponse<List<AdminDtos.RoleOption>> roles() {
        return ApiResponse.ok(adminService.roles());
    }

    /** 最近登录记录 */
    @GetMapping("/logins")
    public ApiResponse<List<AdminDtos.LoginRow>> logins(@RequestParam(required = false) String keyword,
                                                        @RequestParam(defaultValue = "50") int limit) {
        return ApiResponse.ok(adminService.recentLogins(keyword, limit));
    }

    /** 新建医护账号（返回一次性初始密码） */
    @PostMapping("/staff")
    public ApiResponse<AdminDtos.CreatedStaff> create(@Valid @RequestBody AdminDtos.CreateStaffRequest req) {
        return ApiResponse.ok(adminService.createStaff(req));
    }

    /** 重置密码（返回一次性临时密码） */
    @PostMapping("/staff/{id}/reset-password")
    public ApiResponse<AdminDtos.ResetPasswordResult> resetPassword(@PathVariable Long id) {
        return ApiResponse.ok(adminService.resetPassword(id));
    }

    /** 启用 / 停用账号 */
    @PostMapping("/staff/{id}/status")
    public ApiResponse<AdminDtos.StaffRow> setStatus(@PathVariable Long id,
                                                     @Valid @RequestBody AdminDtos.StatusRequest req) {
        return ApiResponse.ok(adminService.setStatus(id, req.status()));
    }
}

package com.hospital.followup.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.OffsetDateTime;
import java.util.List;

/**
 * 管理后台（管理员）接口出入参。
 *
 * 【关于"查看密码"】这里没有、也不会有"查出原密码"的接口。
 * 账号密码用 BCrypt 单向哈希存储（铁律：不用可逆加密，更不存明文），
 * 任何人都无法还原出原密码。管理员能做的是：
 *   - 新建账号 → 系统生成初始密码，只显示这一次
 *   - 重置密码 → 系统生成新密码，只显示这一次
 *   - 停用 / 启用账号
 * 这是安全底线，不是功能缺失。
 */
public final class AdminDtos {

    private AdminDtos() {
    }

    /** 账号列表的一行 */
    public record StaffRow(
            Long staffId,
            String staffNo,
            String name,
            String title,
            String genderText,
            boolean manager,
            String roles,
            /** 账号状态：ACTIVE / DISABLED / 未开通 */
            String accountStatus,
            OffsetDateTime lastLoginAt,
            boolean mustChangePassword
    ) {
    }

    public record StaffList(List<StaffRow> items, int total) {
    }

    public record CreateStaffRequest(
            @NotBlank(message = "请输入工号")
            @Size(max = 50, message = "工号过长")
            String staffNo,

            @NotBlank(message = "请输入姓名")
            @Size(max = 50, message = "姓名过长")
            String name,

            @NotBlank(message = "请选择角色")
            String roleCode,

            String title,
            /** 1 男 / 2 女 */
            Short gender,

            @Pattern(regexp = "^$|^1[3-9]\\d{9}$", message = "手机号格式不正确")
            String phone,

            String email
    ) {
    }

    /**
     * 新建账号的结果。
     * initialPassword 只在这一次返回，之后系统里再也查不到——
     * 请管理员当场抄给本人，并要求首次登录修改。
     */
    public record CreatedStaff(
            Long staffId,
            String staffNo,
            String name,
            String roleCode,
            String initialPassword,
            boolean mustChangePassword,
            String message
    ) {
    }

    public record ResetPasswordResult(
            Long staffId,
            String staffNo,
            String name,
            String tempPassword,
            boolean mustChangePassword,
            String message
    ) {
    }

    public record StatusRequest(
            @NotBlank(message = "缺少状态")
            String status
    ) {
    }

    public record RoleOption(String code, String name, String description) {
    }

    /** 首页概览数字 */
    public record Overview(
            int staffTotal,
            int doctorCount,
            int nurseCount,
            int managerCount,
            int disabledCount,
            int todayLogin,
            int pendingTask,
            int overdueTask
    ) {
    }

    /** 最近登录记录（用于排查"这个账号是谁在用"） */
    public record LoginRow(
            String loginNameMasked,
            String accountType,
            String loginType,
            boolean success,
            String failReason,
            OffsetDateTime createdAt
    ) {
    }

    /**
     * 质控看板（C13）：护士长/科室管理者要看的完成率、逾期与异常。
     * 统计口径写在 AdminService.qc() 的注释里，避免"这个数字怎么算的"来回问。
     */
    public record QcDashboard(
            /** 统计月份，如 2026-09 */
            String month,
            /** 本月应完成的随访任务数 */
            int monthTotal,
            /** 本月已完成 */
            int monthDone,
            /** 完成率百分比（0-100，整数） */
            int completionRate,
            /** 当前未完成（待办 + 处理中） */
            int openTotal,
            /** 当前已逾期未完成 */
            int overdueOpen,
            /** 近 30 天病理"录入→审核"平均时长（小时）；无数据时为 null */
            Double pathologyAvgHours,
            /** 按责任人拆分的本月完成情况 */
            List<DoctorQc> doctors,
            /** 近 30 天异常事件 */
            List<AbnormalEvent> abnormalEvents
    ) {
    }

    public record DoctorQc(
            Long staffId,
            String name,
            int total,
            int done,
            int rate
    ) {
    }

    /** 异常事件：回访中发现危险症状的人。护士长要能一眼看到"谁、什么时候、什么症状"。 */
    public record AbnormalEvent(
            Long recordId,
            Long patientId,
            String patientName,
            String taskTitle,
            OffsetDateTime executedAt,
            String symptomText,
            String conclusion,
            String executedByName,
            /** 是否已升级给医生 */
            boolean escalated
    ) {
    }
}

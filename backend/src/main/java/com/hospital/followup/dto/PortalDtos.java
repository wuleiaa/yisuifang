package com.hospital.followup.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

/**
 * 患者端（小程序 / H5）接口出入参。
 *
 * 设计原则：患者端返回的字段刻意比医护端少——
 * 只给患者本人需要知道的，不给科室内部信息（比如责任护士是谁、内部备注）。
 */
public final class PortalDtos {

    private PortalDtos() {
    }

    public record CodeRequest(
            @NotBlank(message = "请输入手机号")
            @Pattern(regexp = "^1[3-9]\\d{9}$", message = "手机号格式不正确")
            String phone
    ) {
    }

    public record CodeResponse(
            String phoneMask,
            int expireSeconds,
            /** 仅 dev 环境返回，方便本地联调；生产环境恒为 null */
            String devCode
    ) {
    }

    public record LoginRequest(
            @NotBlank(message = "请输入手机号")
            String phone,

            @NotBlank(message = "请输入验证码")
            String code
    ) {
    }

    public record PatientProfile(
            Long patientId,
            String name,
            String genderText,
            Integer age,
            String phoneMask,
            String medicalRecordNo
    ) {
    }

    public record LoginResponse(
            String token,
            long expiresInSeconds,
            PatientProfile profile
    ) {
    }

    /** 随访时间轴上的一条 */
    public record TimelineItem(
            Long taskId,
            String title,
            String taskType,
            String taskTypeText,
            String status,
            String statusText,
            LocalDate dueDate,
            boolean mandatory,
            int overdueDays,
            String pathwayLabel,
            String conclusion,
            OffsetDateTime doneAt
    ) {
    }

    public record Timeline(
            PatientProfile profile,
            List<TimelineItem> items,
            int doneCount,
            int pendingCount,
            int overdueCount
    ) {
    }

    /** 病理报告（患者端只能看到"已发布"的） */
    public record ReportItem(
            Long reportId,
            String reportNo,
            String specimenSite,
            LocalDate reportDate,
            String riskLevel,
            String riskText,
            String conclusion,
            String plainText,
            String advice,
            Integer recheckMonths,
            OffsetDateTime publishedAt
    ) {
    }

    public record QuestionnaireSubmit(
            @NotNull(message = "缺少问卷内容")
            Map<String, Object> answers
    ) {
    }

    /** 问卷里的一道题 */
    public record QuestionItem(
            int seqNo,
            String type,
            String title,
            List<String> options,
            boolean required
    ) {
    }

    /**
     * 随访问卷。
     *
     * 题目从数据库读，不写死在前端：
     * 护士长以后要改题目，改的是数据，不该改代码发版本。
     */
    public record Questionnaire(
            String code,
            String name,
            List<QuestionItem> questions
    ) {
    }

    public record SubmitResult(
            Long taskId,
            boolean recorded,
            String message
    ) {
    }
}

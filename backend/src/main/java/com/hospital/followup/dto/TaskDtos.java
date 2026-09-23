package com.hospital.followup.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class TaskDtos {

    private TaskDtos() {
    }

    /** 待办列表项（对应界面上的任务卡片） */
    public record TaskItem(
            Long id,
            String title,
            String taskType,
            String status,
            Short priority,
            LocalDate dueDate,
            OffsetDateTime dueAt,
            boolean mandatory,
            int overdueDays,
            Long patientId,
            String patientName,
            String genderText,
            Integer age,
            String phoneMask,
            String inpatientNo,
            String pathwayLabel,
            String procedureName,
            OffsetDateTime procedureDate,
            String urgency          // OVERDUE / TODAY / LATER
    ) {
    }

    public record TodoSummary(
            int total,
            int overdue,
            int today,
            int later,
            List<TaskItem> items
    ) {
    }

    /** 任务详情：多带一些病情信息，供回访前了解情况 */
    public record TaskDetail(
            Long id,
            String title,
            String taskType,
            String status,
            String contentHint,
            LocalDate dueDate,
            OffsetDateTime dueAt,
            boolean mandatory,
            int overdueDays,
            Long patientId,
            String patientName,
            String genderText,
            Integer age,
            String phoneMask,
            String medicalRecordNo,
            String inpatientNo,
            LocalDate admitDate,
            LocalDate dischargeDate,
            List<String> diagnoses,
            String pathwayLabel,
            String procedureName,
            OffsetDateTime procedureDate,
            boolean locked,
            Long lockedBy,
            OffsetDateTime lockedAt
    ) {
    }

    /** 任务详情里展示的联系号码（脱敏），可一键拨号 */
    public record ContactInfo(
            String label,
            String relation,
            String maskedPhone,
            boolean primary,
            boolean canCall
    ) {
    }

    /**
     * 一键拨号：交给系统拨号器的号码。
     *
     * 界面展示永远用 phoneMask（脱敏），phone 只由前端直接送给拨号器，
     * 不得渲染到页面上——"查看完整号码"另有一条需要二次验证的路径，
     * 两者的门槛刻意不同（见 docs/第08轮-界面与交互定稿.md 3.5）。
     */
    public record DialPhone(
            String phoneMask,
            String phone
    ) {
    }

    /**
     * 历史回访的一条记录（C9）：第二次回访时护士要能看到"上次说了什么"。
     */
    public record HistoryItem(
            Long recordId,
            Long taskId,
            String taskTitle,
            OffsetDateTime executedAt,
            String executedByName,
            Boolean contacted,
            String contactTarget,
            List<String> symptoms,
            String recoveryLevel,
            String recoveryLevelText,
            String medicationAdherence,
            String conclusion,
            String advice,
            String nextAction,
            boolean abnormal
    ) {
    }

    /** 历史回访列表；count = 0 表示这是首次回访 */
    public record TaskHistory(
            Long patientId,
            int count,
            List<HistoryItem> items
    ) {
    }

    public record CompleteTaskRequest(
            @NotNull(message = "缺少任务编号")
            Long taskId,

            Boolean contacted,
            String contactTarget,
            Integer durationSeconds,
            List<String> symptoms,
            String recoveryLevel,
            String medicationAdherence,
            @Size(max = 3000, message = "结论过长")
            String conclusion,
            @Size(max = 2000, message = "指导建议过长")
            String advice,
            String nextAction,

            /** 勾选危险症状时可以立即通知医生，而不必等表单填完 */
            Boolean notifyDoctorImmediately
    ) {
    }

    public record CompleteTaskResponse(
            Long taskId,
            String status,
            String message,
            boolean doctorNotified
    ) {
    }
}

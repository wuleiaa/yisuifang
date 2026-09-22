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


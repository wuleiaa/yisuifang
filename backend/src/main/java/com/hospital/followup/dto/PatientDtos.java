package com.hospital.followup.dto;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.List;

public final class PatientDtos {

    private PatientDtos() {
    }

    public record PatientItem(
            Long id,
            String name,
            String genderText,
            Integer age,
            String phoneMask,
            String medicalRecordNo,
            String status,
            int pendingTasks,
            int overdueTasks
    ) {
    }

    public record EncounterItem(
            Long id,
            String inpatientNo,
            LocalDate admitDate,
            LocalDate dischargeDate,
            Integer stayDays,
            String summary
    ) {
    }

    /** 患者详情：包含多次住院历史与并行随访路径 */
    public record PatientDetail(
            Long id,
            String name,
            String genderText,
            Integer age,
            String phoneMask,
            String medicalRecordNo,
            String address,
            String remark,
            List<ContactView> contacts,
            List<EncounterItem> encounters,
            List<PathwayView> pathways
    ) {
    }

    public record ContactView(
            Long id,
            String name,
            String relation,
            String phoneMask,
            boolean primary
    ) {
    }

    /** 一条随访路径（同一患者可能有多条并行） */
    public record PathwayView(
            Long planId,
            String label,
            String status,
            OffsetDateTime anchorProcedureAt,
            LocalDate anchorDischargeDate,
            List<PathwayStep> steps
    ) {
    }

    public record PathwayStep(
            Long taskId,
            String title,
            LocalDate dueDate,
            String status,
            boolean mandatory,
            int overdueDays,
            String taskType
    ) {
    }
}

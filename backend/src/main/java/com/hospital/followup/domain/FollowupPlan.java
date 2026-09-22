package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 患者随访计划。
 * 同一患者可以并行多条（如胆总管结石 + 胆囊结石），
 * pathwayLabel 用于界面上区分"这条路是治什么"。
 */
@Entity
@Table(name = "followup_plan")
@Getter
@Setter
public class FollowupPlan {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "encounter_id", nullable = false)
    private Long encounterId;

    @Column(name = "template_id")
    private Long templateId;

    @Column(name = "template_version")
    private Integer templateVersion;

    @Column(name = "pathway_label")
    private String pathwayLabel;

    @Column(name = "anchor_procedure_at")
    private OffsetDateTime anchorProcedureAt;

    @Column(name = "anchor_discharge_date")
    private LocalDate anchorDischargeDate;

    @Column(name = "care_team_id")
    private Long careTeamId;

    @Column(name = "doctor_id")
    private Long doctorId;

    @Column(name = "nurse_id")
    private Long nurseId;

    @Column(name = "status", nullable = false)
    private String status = "ACTIVE";

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

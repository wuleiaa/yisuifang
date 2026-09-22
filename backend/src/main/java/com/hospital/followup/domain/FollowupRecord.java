package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/** 随访执行记录 */
@Entity
@Table(name = "followup_record")
@Getter
@Setter
public class FollowupRecord {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "task_id")
    private Long taskId;

    @Column(name = "plan_id")
    private Long planId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "encounter_id")
    private Long encounterId;

    @Column(name = "record_type", nullable = false)
    private String recordType = "PHONE";

    @Column(name = "contacted")
    private Boolean contacted;

    @Column(name = "contact_target")
    private String contactTarget;

    @Column(name = "contact_phone_mask")
    private String contactPhoneMask;

    @Column(name = "duration_sec")
    private Integer durationSec;

    /** 症状勾选（JSON 数组） */
    @org.hibernate.annotations.JdbcTypeCode(org.hibernate.type.SqlTypes.JSON)
    @Column(name = "symptom_json", columnDefinition = "jsonb")
    private String symptomJson;

    @Column(name = "recovery_level")
    private String recoveryLevel;

    @Column(name = "medication_adherence")
    private String medicationAdherence;

    @Column(name = "conclusion")
    private String conclusion;

    @Column(name = "advice")
    private String advice;

    @Column(name = "next_action")
    private String nextAction;

    @Column(name = "is_abnormal", nullable = false)
    private Boolean isAbnormal = Boolean.FALSE;

    @Column(name = "escalated_to")
    private Long escalatedTo;

    @Column(name = "executed_by", nullable = false)
    private Long executedBy;

    @Column(name = "executed_at", nullable = false)
    private OffsetDateTime executedAt;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

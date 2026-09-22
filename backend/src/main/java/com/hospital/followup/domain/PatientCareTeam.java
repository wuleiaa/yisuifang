package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 患者在本次住院的主管医护关系（住院时手工指定）。
 *
 * 这张表是数据库行级安全策略的依据：
 * 只有在这张表里与某个搭档组建立了关系的患者，
 * 该组成员才能看到——真正实现"护士只看自己主管的患者"。
 */
@Entity
@Table(name = "patient_care_team")
@Getter
@Setter
public class PatientCareTeam {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "encounter_id", nullable = false)
    private Long encounterId;

    @Column(name = "team_id", nullable = false)
    private Long teamId;

    @Column(name = "doctor_id", nullable = false)
    private Long doctorId;

    @Column(name = "nurse_id")
    private Long nurseId;

    @Column(name = "assigned_by")
    private Long assignedBy;

    @Column(name = "status", nullable = false)
    private String status = "ACTIVE";

    @Column(name = "created_at", insertable = false, updatable = false)
    private OffsetDateTime createdAt;
}


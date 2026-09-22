package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/** 住院记录：一次住院一条，住院号全院唯一 */
@Entity
@Table(name = "encounter")
@Getter
@Setter
public class Encounter {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    @Column(name = "inpatient_no", nullable = false)
    private String inpatientNo;

    @Column(name = "visit_seq", nullable = false)
    private Integer visitSeq = 1;

    @Column(name = "bed_no")
    private String bedNo;

    @Column(name = "admit_date")
    private LocalDate admitDate;

    @Column(name = "discharge_date")
    private LocalDate dischargeDate;

    @Column(name = "stay_days")
    private Integer stayDays;

    @Column(name = "discharge_type")
    private String dischargeType;

    @Column(name = "discharge_summary")
    private String dischargeSummary;

    @Column(name = "care_team_id")
    private Long careTeamId;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

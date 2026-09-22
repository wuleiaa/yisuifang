package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/** 手术/操作记录。随访时间的首选锚点。 */
@Entity
@Table(name = "medical_procedure")
@Getter
@Setter
public class MedicalProcedure {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "encounter_id", nullable = false)
    private Long encounterId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "procedure_name", nullable = false)
    private String procedureName;

    @Column(name = "procedure_code")
    private String procedureCode;

    /** 精确到时分：例如 ERCP 术后 4 小时监测，差几小时就是差一个级别 */
    @Column(name = "procedure_date", nullable = false)
    private OffsetDateTime procedureDate;

    @Column(name = "is_primary", nullable = false)
    private Boolean isPrimary = Boolean.FALSE;

    @Column(name = "surgeon_id")
    private Long surgeonId;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

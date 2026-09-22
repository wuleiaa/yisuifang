package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

@Entity
@Table(name = "diagnosis")
@Getter
@Setter
public class Diagnosis {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "encounter_id", nullable = false)
    private Long encounterId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "diag_type", nullable = false)
    private String diagType;

    @Column(name = "seq_no", nullable = false)
    private Integer seqNo = 1;

    @Column(name = "is_primary", nullable = false)
    private Boolean isPrimary = Boolean.FALSE;

    @Column(name = "icd_code")
    private String icdCode;

    @Column(name = "diagnosis_name", nullable = false)
    private String diagnosisName;
}


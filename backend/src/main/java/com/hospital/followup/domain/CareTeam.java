package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 医护搭档组：1 名主管医生 + N 名护士。
 *
 * 随访任务挂在"组"上而不是个人上，好处是：
 *   - 医生休假时护士天然能接手，不需要复杂的转交流程；
 *   - 医生轮转调岗时只改组员，不用逐条改任务。
 */
@Entity
@Table(name = "care_team")
@Getter
@Setter
public class CareTeam {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    @Column(name = "code")
    private String code;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "doctor_id")
    private Long doctorId;

    @Column(name = "primary_nurse_id")
    private Long primaryNurseId;

    @Column(name = "status", nullable = false)
    private Short status = 1;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}


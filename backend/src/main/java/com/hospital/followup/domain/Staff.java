package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

@Entity
@Table(name = "staff")
@Getter
@Setter
public class Staff {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    @Column(name = "staff_no", nullable = false)
    private String staffNo;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "gender")
    private Short gender;

    @Column(name = "title")
    private String title;

    @Column(name = "phone_cipher")
    private byte[] phoneCipher;

    @Column(name = "phone_hash")
    private String phoneHash;

    @Column(name = "phone_mask")
    private String phoneMask;

    @Column(name = "status", nullable = false)
    private Short status;

    /** 科室管理者（护士长 / 科主任）：可查看本科室全部数据 */
    @Column(name = "is_manager", nullable = false)
    private Boolean isManager = Boolean.FALSE;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

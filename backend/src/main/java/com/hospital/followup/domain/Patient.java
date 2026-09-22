package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 患者主档。
 *
 * 手机号三重字段：
 *   phoneCipher  密文，用于解密后展示完整号码（需审计）
 *   phoneHash    HMAC 哈希，用于按手机号精确查找
 *   phoneMask    脱敏值，列表页直接展示，不需要解密
 */
@Entity
@Table(name = "patient")
@Getter
@Setter
public class Patient {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    /** 病案号：患者终身唯一，跨多次住院不变 */
    @Column(name = "medical_record_no")
    private String medicalRecordNo;

    @Column(name = "name", nullable = false)
    private String name;

    @Column(name = "name_pinyin")
    private String namePinyin;

    @Column(name = "gender", nullable = false)
    private Short gender;

    @Column(name = "birth_date")
    private LocalDate birthDate;

    @Column(name = "age")
    private Integer age;

    @Column(name = "phone_cipher", nullable = false)
    private byte[] phoneCipher;

    @Column(name = "phone_hash", nullable = false)
    private String phoneHash;

    @Column(name = "phone_mask", nullable = false)
    private String phoneMask;

    @Column(name = "address")
    private String address;

    @Column(name = "remark")
    private String remark;

    @Column(name = "status", nullable = false)
    private String status = "ACTIVE";

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

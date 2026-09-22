package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 统一登录账号。医护与患者共用这张表。
 *
 * 注意：login_hash 是登录名的 HMAC-SHA256，不是明文，
 * 这样即使数据库泄露也无法直接拿到工号/手机号列表。
 */
@Entity
@Table(name = "account")
@Getter
@Setter
public class Account {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "account_type", nullable = false)
    private String accountType;      // STAFF / PATIENT

    @Column(name = "login_hash", nullable = false)
    private String loginHash;

    @Column(name = "login_display")
    private String loginDisplay;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(name = "staff_id")
    private Long staffId;

    @Column(name = "patient_id")
    private Long patientId;

    @Column(name = "status", nullable = false)
    private String status;           // PENDING / ACTIVE / LOCKED / DISABLED

    @Column(name = "failed_attempts", nullable = false)
    private Integer failedAttempts = 0;

    @Column(name = "locked_until")
    private OffsetDateTime lockedUntil;

    @Column(name = "last_login_at")
    private OffsetDateTime lastLoginAt;

    @Column(name = "must_change_password", nullable = false)
    private Boolean mustChangePassword = Boolean.FALSE;

    @Column(name = "password_updated_at")
    private OffsetDateTime passwordUpdatedAt;

    @Column(name = "wechat_openid")
    private String wechatOpenid;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

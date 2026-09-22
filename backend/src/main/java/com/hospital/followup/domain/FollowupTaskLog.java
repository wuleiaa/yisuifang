package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.OffsetDateTime;

/**
 * 任务流水，只追加不修改。
 * 质控统计和医疗纠纷举证都依赖这张表。
 */
@Entity
@Table(name = "followup_task_log")
@Getter
@Setter
public class FollowupTaskLog {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "task_id", nullable = false)
    private Long taskId;

    @Column(name = "action", nullable = false)
    private String action;      // CREATE / REMIND / ESCALATE / CLAIM / REASSIGN / COMPLETE / SKIP / CANCEL

    @Column(name = "action_by")
    private Long actionBy;

    @Column(name = "action_at", nullable = false)
    private OffsetDateTime actionAt;

    @Column(name = "channel")
    private String channel;

    @org.hibernate.annotations.JdbcTypeCode(org.hibernate.type.SqlTypes.JSON)
    @Column(name = "detail", columnDefinition = "jsonb")
    private String detail;

    @Column(name = "remark")
    private String remark;
}

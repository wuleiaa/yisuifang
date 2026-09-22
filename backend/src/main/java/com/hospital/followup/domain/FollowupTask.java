package com.hospital.followup.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.Setter;

import java.time.LocalDate;
import java.time.OffsetDateTime;

/**
 * 随访任务（待办）。
 *
 * assignee 责任人 vs executor 实际执行人：
 *   护士代医生完成回访时，assignee 仍是医生，executor 是护士，
 *   这样既方便协作，又能追溯"到底谁做的"。
 */
@Entity
@Table(name = "followup_task")
@Getter
@Setter
public class FollowupTask {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "public_id", insertable = false, updatable = false)
    private java.util.UUID publicId;

    @Column(name = "dept_id", nullable = false)
    private Long deptId;

    @Column(name = "plan_id")
    private Long planId;

    @Column(name = "template_item_id")
    private Long templateItemId;

    @Column(name = "patient_id", nullable = false)
    private Long patientId;

    @Column(name = "encounter_id", nullable = false)
    private Long encounterId;

    @Column(name = "care_team_id")
    private Long careTeamId;

    @Column(name = "task_type", nullable = false)
    private String taskType;

    @Column(name = "title", nullable = false)
    private String title;

    @Column(name = "content_hint")
    private String contentHint;

    @Column(name = "due_at", nullable = false)
    private OffsetDateTime dueAt;

    @Column(name = "due_date", nullable = false)
    private LocalDate dueDate;

    @Column(name = "remind_start_at")
    private OffsetDateTime remindStartAt;

    @Column(name = "priority", nullable = false)
    private Short priority = 2;

    @Column(name = "is_mandatory", nullable = false)
    private Boolean isMandatory = Boolean.FALSE;

    @Column(name = "status", nullable = false)
    private String status = "PENDING";

    @Column(name = "assignee_staff_id")
    private Long assigneeStaffId;

    @Column(name = "executor_staff_id")
    private Long executorStaffId;

    @Column(name = "remind_count", nullable = false)
    private Integer remindCount = 0;

    @Column(name = "last_remind_at")
    private OffsetDateTime lastRemindAt;

    @Column(name = "overdue_days", nullable = false)
    private Integer overdueDays = 0;

    @Column(name = "locked_by")
    private Long lockedBy;

    @Column(name = "locked_at")
    private OffsetDateTime lockedAt;

    @Column(name = "completed_at")
    private OffsetDateTime completedAt;

    @Column(name = "remark")
    private String remark;

    @Column(name = "deleted_at")
    private OffsetDateTime deletedAt;
}

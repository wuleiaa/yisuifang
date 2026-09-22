package com.hospital.followup.repository;

import com.hospital.followup.domain.FollowupTask;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.List;

public interface FollowupTaskRepository extends JpaRepository<FollowupTask, Long> {

    /**
     * 待办列表：最核心、最高频的查询。
     *
     * 排序规则（第 8 轮定的）：逾期置顶 → 按应完成时间 → 高优先级优先。
     * SQL 走了 idx_task_due 与 idx_task_assignee 两个索引。
     */
    @Query(value = """
            SELECT t.id              AS "id",
                   t.title           AS "title",
                   t.task_type       AS "taskType",
                   t.status          AS "status",
                   t.priority        AS "priority",
                   t.due_date        AS "dueDate",
                   t.due_at          AS "dueAt",
                   t.is_mandatory    AS "mandatory",
                   t.overdue_days    AS "overdueDays",
                   t.patient_id      AS "patientId",
                   p.name            AS "patientName",
                   p.gender          AS "gender",
                   p.age             AS "age",
                   p.phone_mask      AS "phoneMask",
                   e.inpatient_no    AS "inpatientNo",
                   pl.pathway_label  AS "pathwayLabel",
                   mp.procedure_name AS "procedureName",
                   mp.procedure_date AS "procedureDate"
            FROM followup_task t
            JOIN patient p        ON p.id = t.patient_id
            JOIN encounter e      ON e.id = t.encounter_id
            LEFT JOIN followup_plan pl ON pl.id = t.plan_id
            LEFT JOIN LATERAL (
                SELECT m.procedure_name, m.procedure_date
                FROM medical_procedure m
                WHERE m.encounter_id = t.encounter_id AND m.deleted_at IS NULL
                ORDER BY m.is_primary DESC, m.procedure_date DESC
                LIMIT 1
            ) mp ON TRUE
            WHERE t.deleted_at IS NULL
              AND t.status IN ('PENDING', 'DOING')
              AND t.due_date <= :until
              AND (:assigneeId IS NULL OR t.assignee_staff_id = :assigneeId)
            ORDER BY
                CASE WHEN t.due_date < :today THEN 0 ELSE 1 END,
                t.due_date,
                t.priority
            LIMIT :limit
            """, nativeQuery = true)
    List<TaskRow> findTodo(@Param("assigneeId") Long assigneeId,
                           @Param("today") LocalDate today,
                           @Param("until") LocalDate until,
                           @Param("limit") int limit);

    /** 首页角标：待办数量。这个查询是压测发现的瓶颈，生产环境用 Redis 缓存 60 秒。 */
    @Query(value = """
            SELECT count(*)
            FROM followup_task t
            WHERE t.deleted_at IS NULL
              AND t.status = 'PENDING'
              AND t.due_date <= :until
              AND (:assigneeId IS NULL OR t.assignee_staff_id = :assigneeId)
            """, nativeQuery = true)
    long countPending(@Param("assigneeId") Long assigneeId, @Param("until") LocalDate until);

    List<FollowupTask> findByPatientIdAndDeletedAtIsNullOrderByDueDateDesc(Long patientId);

    List<FollowupTask> findByPlanIdAndDeletedAtIsNull(Long planId);

    interface TaskRow {
        Long getId();
        String getTitle();
        String getTaskType();
        String getStatus();
        Short getPriority();
        LocalDate getDueDate();
        /** PostgreSQL timestamptz 经 Spring Data 投影后是 Instant，由 Service 层转换时区 */
        java.time.Instant getDueAt();
        Boolean getMandatory();
        Integer getOverdueDays();
        Long getPatientId();
        String getPatientName();
        Short getGender();
        Integer getAge();
        String getPhoneMask();
        String getInpatientNo();
        String getPathwayLabel();
        String getProcedureName();
        java.time.Instant getProcedureDate();
    }
}

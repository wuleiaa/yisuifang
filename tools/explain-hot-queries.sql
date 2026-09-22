-- =============================================================================
--  热点查询执行计划（压测发现"待办列表"随数据量明显变慢后加的）
--
--  以 app_rw 身份 + 行级安全会话变量执行，跟生产环境走的是同一条路。
--  用法：
--    psql -U postgres -d followup_dev -f tools\explain-hot-queries.sql
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

-- 模拟 D0231（主管医生）登录后的会话
SELECT set_config('app.current_staff_id', (SELECT id::text FROM staff WHERE staff_no = 'D0231'), true);
SELECT set_config('app.is_manager', 'false', true);
SELECT set_config('app.is_system', 'false', true);
SELECT set_config('app.is_patient_portal', 'false', true);

-- 切到应用账号（非超级用户），否则行级安全不生效
SET LOCAL ROLE app_rw;

\echo '=== 1. 待办列表（最热的查询）==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT t.id, t.title, t.status, t.due_date, t.priority, t.overdue_days,
       p.name, e.inpatient_no, pl.pathway_label
  FROM followup_task t
  JOIN patient p   ON p.id = t.patient_id
  JOIN encounter e ON e.id = t.encounter_id
  LEFT JOIN followup_plan pl ON pl.id = t.plan_id
 WHERE t.deleted_at IS NULL
   AND t.status IN ('PENDING', 'DOING')
   AND t.due_date <= current_date + 30
   AND t.assignee_staff_id = (SELECT id FROM staff WHERE staff_no = 'D0231')
 ORDER BY CASE WHEN t.due_date < current_date THEN 0 ELSE 1 END, t.due_date, t.priority
 LIMIT 100;

\echo '=== 2. 患者列表（含每人待办/逾期计数）==='
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF)
SELECT p.id, p.name, p.gender, p.age, p.phone_mask, p.medical_record_no, p.status,
       (SELECT count(*) FROM followup_task t
         WHERE t.patient_id = p.id AND t.deleted_at IS NULL AND t.status IN ('PENDING','DOING')) AS pending,
       (SELECT count(*) FROM followup_task t
         WHERE t.patient_id = p.id AND t.deleted_at IS NULL AND t.status IN ('PENDING','DOING')
           AND t.due_date < current_date) AS overdue
  FROM patient p
 WHERE p.deleted_at IS NULL
   AND p.dept_id = (SELECT dept_id FROM staff WHERE staff_no = 'D0231')
 ORDER BY p.id DESC
 LIMIT 50;

ROLLBACK;

\echo ''
\echo '=== 索引使用情况（哪张表建了哪些索引）==='
SELECT tablename, indexname, indexdef
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND tablename IN ('followup_task', 'patient', 'encounter', 'followup_plan', 'patient_care_team', 'care_team_member')
 ORDER BY tablename, indexname;

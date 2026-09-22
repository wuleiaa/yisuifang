-- =============================================================================
--  性能与容量测试 · 数据准备 + 核心查询基准
--
--  目的：验证"一个科室 4 年 10 万患者"这一量级下，数据库是否真的够用。
--        用实测数据回答"要不要分库分表"这个疑问。
--
--  目标数据量（对应第 2 轮的容量测算）：
--     患者        100,000
--     住院记录    150,000
--     诊断        180,000
--     随访计划    150,000
--     随访任务    750,000   <- 最大表
--     回访记录    200,000
--     消息日志  1,000,000   <- 走分区表
--
--  用法：
--     createdb followup_perf
--     psql -d followup_perf -f db/migration/V1__init_schema.sql
--     psql -d followup_perf -f tools/perf_test.sql
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

\echo ''
\echo '################  阶段 1：生成测试数据  ################'

-- 让插入不被行级安全策略拦截（仅测试用）
SET app.is_system = 'true';

\echo '--- 1.0 测试医护账号（性能脚本自用）---'
INSERT INTO staff (dept_id, staff_no, name, gender, title,
                   phone_mask, phone_hash, phone_cipher, is_manager)
SELECT (SELECT id FROM department WHERE code = 'XHNK'),
       'PERF001', '性能测试医生', 1, '主治医师',
       '138****0000', 'perf-hash-000', '\x00'::bytea, FALSE
ON CONFLICT DO NOTHING;

\echo '--- 1.1 患者 100,000 ---'
INSERT INTO patient (dept_id, medical_record_no, name, gender, age,
                     phone_cipher, phone_hash, phone_mask)
SELECT
    (SELECT id FROM department WHERE code = 'XHNK'),
    'MRN' || lpad(i::text, 8, '0'),
    (ARRAY['张','王','李','赵','刘','陈','杨','黄','周','吴'])[(i % 10) + 1]
        || (ARRAY['伟','芳','娜','秀英','敏','静','丽','强','磊','洋'])[(i / 10 % 10) + 1],
    CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END,
    30 + (i % 50),
    '\x00'::bytea,
    encode(digest('138' || lpad(i::text, 8, '0'), 'sha256'), 'hex'),
    '138****' || lpad((i % 10000)::text, 4, '0')
FROM generate_series(1, 100000) AS i;

\echo '--- 1.2 住院记录 150,000（每患者 1–2 次）---'
INSERT INTO encounter (patient_id, dept_id, inpatient_no, visit_seq,
                       admit_date, discharge_date, stay_days, discharge_type)
SELECT p.id, p.dept_id,
       'ZY' || lpad(p.id::text, 8, '0') || '-' || v.seq,
       v.seq,
       DATE '2024-01-01' + (((p.id * 3 + v.seq * 17) % 900)::int),
       DATE '2024-01-01' + (((p.id * 3 + v.seq * 17) % 900)::int) + ((3 + (p.id % 12))::int),
       (3 + (p.id % 12))::int,
       '1'
FROM patient p
CROSS JOIN LATERAL (SELECT 1 AS seq
                    UNION ALL SELECT 2 WHERE p.id % 3 = 0) AS v;

\echo '--- 1.3 出院诊断 180,000 ---'
INSERT INTO diagnosis (encounter_id, patient_id, diag_type, seq_no, is_primary, icd_code, diagnosis_name)
SELECT e.id, e.patient_id, 'DISCHARGE', 1, TRUE,
       (ARRAY['K25.4','K92.2','K80.5','K80.2','K57.3'])[(e.id % 5) + 1],
       (ARRAY['十二指肠球部溃疡伴出血','上消化道出血','胆总管结石伴胆管炎',
              '胆囊结石伴胆囊炎','结肠息肉'])[(e.id % 5) + 1]
FROM encounter e;

\echo '--- 1.4 随访计划 150,000 ---'
INSERT INTO followup_plan (dept_id, patient_id, encounter_id, template_version,
                           pathway_label, anchor_procedure_at, anchor_discharge_date,
                           care_team_id, status)
SELECT e.dept_id, e.patient_id, e.id, 1,
       '测试路径',
       (e.discharge_date - 3)::timestamptz + interval '14 hours',
       e.discharge_date,
       NULL, 'ACTIVE'
FROM encounter e;

\echo '--- 1.5 随访任务 750,000（每计划 5 条）---'
INSERT INTO followup_task (dept_id, plan_id, template_item_id, patient_id, encounter_id,
                           care_team_id, task_type, title, due_at, due_date,
                           priority, status, assignee_staff_id)
SELECT pl.dept_id, pl.id, NULL, pl.patient_id, pl.encounter_id,
       NULL,
       CASE WHEN s.n % 3 = 0 THEN 'PHONE' ELSE 'PHONE' END,
       (ARRAY['出院 1 天症状观察','术后 3 天电话回访','出院 1 周随访',
              '出院 1 个月门诊复查','出院 3 个月电话随访'])[s.n],
       (pl.anchor_procedure_at + (ARRAY[1,3,7,30,90])[s.n] * interval '1 day'),
       ((pl.anchor_procedure_at + (ARRAY[1,3,7,30,90])[s.n] * interval '1 day')
            AT TIME ZONE 'Asia/Shanghai')::date,
       CASE WHEN s.n = 2 THEN 1 ELSE 2 END,
       CASE
           WHEN s.n <= 3 AND pl.id % 7 = 0 THEN 'PENDING'
           WHEN s.n <= 3 THEN 'DONE'
           WHEN s.n = 4 AND pl.id % 11 = 0 THEN 'PENDING'
           ELSE 'DONE'
       END,
       (SELECT id FROM staff WHERE staff_no = 'PERF001')
FROM followup_plan pl
CROSS JOIN generate_series(1, 5) AS s(n);

\echo '--- 1.6 回访记录 200,000 ---'
INSERT INTO followup_record (task_id, plan_id, patient_id, encounter_id, record_type,
                             contacted, contact_target, recovery_level,
                             conclusion, is_abnormal, executed_by, executed_at)
SELECT t.id, t.plan_id, t.patient_id, t.encounter_id, 'PHONE',
       TRUE, 'PATIENT',
       CASE WHEN t.id % 50 = 0 THEN 'MILD' ELSE 'GOOD' END,
       '测试回访结论',
       (t.id % 500 = 0),
       (SELECT id FROM staff WHERE staff_no = 'PERF001'),
       t.due_at + interval '2 hours'
FROM followup_task t
WHERE t.status = 'DONE'
LIMIT 200000;

\echo '--- 1.7 消息日志 1,000,000（分区表）---'
INSERT INTO notify_log (task_id, patient_id, staff_id, channel_code, biz_type,
                        title, content_masked, status, created_at)
SELECT NULL, NULL, NULL, 'IN_APP', 'TASK_REMIND',
       '随访待办', '您有 1 条随访任务待处理', 'SENT',
       TIMESTAMPTZ '2026-09-01 00:00+08' + (i * interval '1 minute')
FROM generate_series(1, 1000000) AS i;

\echo ''
\echo '################  阶段 2：容量与索引  ################'

SELECT
    c.relname                          AS "表名",
    to_char(c.reltuples, 'FM999,999,999') AS "估算行数",
    pg_size_pretty(pg_total_relation_size(c.oid)) AS "总大小",
    pg_size_pretty(pg_indexes_size(c.oid))        AS "索引大小"
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN ('patient','encounter','diagnosis','followup_plan',
                    'followup_task','followup_record','notify_log','audit_log')
ORDER BY pg_total_relation_size(c.oid) DESC;

SELECT
    pg_size_pretty(pg_database_size(current_database())) AS "数据库总大小";

\echo ''
\echo '################  阶段 3：核心查询性能  ################'

\echo '--- 3.1 待办列表：按责任人查询今日及逾期任务（最高频查询）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT t.id, t.title, t.due_date, t.status, p.name
FROM followup_task t
JOIN patient p ON p.id = t.patient_id
WHERE t.status IN ('PENDING','DOING')
  AND t.due_date <= DATE '2024-10-01'
ORDER BY t.due_date
LIMIT 50;

\echo '--- 3.2 患者姓名模糊搜索（trigram 索引）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name, phone_mask
FROM patient
WHERE name LIKE '%张伟%'
LIMIT 20;

\echo '--- 3.3 手机号精确查找（HMAC 哈希索引）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name, phone_mask
FROM patient
WHERE phone_hash = encode(digest('13800001234', 'sha256'), 'hex');

\echo '--- 3.4 科室随访完成率统计（质控看板）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT
    status,
    count(*)                                        AS cnt,
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM followup_task
WHERE due_date BETWEEN DATE '2024-06-01' AND DATE '2024-09-30'
GROUP BY status
ORDER BY cnt DESC;

\echo '--- 3.5 患者详情：取某患者全部随访任务（含多路径）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT t.id, t.title, t.due_date, t.status, pl.pathway_label
FROM followup_task t
JOIN followup_plan pl ON pl.id = t.plan_id
WHERE t.patient_id = (SELECT id FROM patient LIMIT 1)
ORDER BY t.due_date DESC;

\echo '--- 3.6 消息日志按月分区裁剪（归档查询）---'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT count(*)
FROM notify_log
WHERE created_at >= TIMESTAMPTZ '2026-08-01 00:00+08'
  AND created_at <  TIMESTAMPTZ '2026-09-01 00:00+08';

\echo ''
\echo '################  性能测试结束  ################'

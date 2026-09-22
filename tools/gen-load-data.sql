-- =============================================================================
--  压测数据生成（仅用于本地压测，跑完用 tools\demo-reset.ps1 清掉）
--
--  目的：验证"真实科室数据量"下的查询性能。
--  演示数据只有 3 位患者，看不出索引和行级安全策略在数据量大时的表现。
--  这里生成：1000 位患者 / 1000 次住院 / 1000 条随访路径 / 6000 个随访任务。
--
--  用法： psql -f tools\gen-load-data.sql
--  注意： 以超级用户执行（会绕过行级安全，这是刻意的）
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 清掉上次生成的压测数据（按病案号前缀识别，不影响演示数据）
DELETE FROM followup_task   WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM followup_plan   WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM patient_care_team WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM diagnosis       WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM medical_procedure WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM encounter       WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM patient_contact WHERE patient_id IN (SELECT id FROM patient WHERE medical_record_no LIKE 'LT%');
DELETE FROM patient         WHERE medical_record_no LIKE 'LT%';

-- ---------------------------------------------------------------- 患者
INSERT INTO patient (dept_id, medical_record_no, name, gender, age,
                     phone_cipher, phone_hash, phone_mask, status)
SELECT d.id,
       'LT' || lpad(i::text, 7, '0'),
       '压测患者' || i,
       (1 + (i % 2))::smallint,
       35 + (i % 50),
       '\x00'::bytea,
       encode(digest('loadtest-phone-' || i, 'sha256'), 'hex'),
       '139****' || lpad((i % 10000)::text, 4, '0'),
       'ACTIVE'
  FROM generate_series(1, 1000) AS i
  CROSS JOIN (SELECT id FROM department WHERE code = 'XHNK' LIMIT 1) AS d;

-- ---------------------------------------------------------------- 住院
INSERT INTO encounter (patient_id, dept_id, inpatient_no, visit_seq,
                       admit_date, discharge_date, stay_days, care_team_id, created_by)
SELECT p.id,
       p.dept_id,
       'LI' || lpad(row_number() OVER (ORDER BY p.id)::text, 7, '0'),
       1,
       current_date - INTERVAL '10 days',
       current_date - INTERVAL '3 days',
       7,
       t.id,
       t.doctor_id
  FROM patient p
  CROSS JOIN (SELECT id, doctor_id FROM care_team WHERE code = 'TEAM-A' LIMIT 1) AS t
 WHERE p.medical_record_no LIKE 'LT%';

-- ---------------------------------------------------------------- 诊断
INSERT INTO diagnosis (encounter_id, patient_id, diag_type, seq_no, is_primary, icd_code, diagnosis_name)
SELECT e.id, e.patient_id, 'DISCHARGE', 1, true, 'K80.5', '胆总管结石伴胆管炎'
  FROM encounter e
  JOIN patient p ON p.id = e.patient_id
 WHERE p.medical_record_no LIKE 'LT%';

-- ---------------------------------------------------------------- 患者-搭档组归属
-- 【关键】没有这条关系，行级安全策略会让医护看不到这些患者
INSERT INTO patient_care_team (patient_id, encounter_id, team_id, doctor_id, nurse_id, assigned_by, status)
SELECT e.patient_id, e.id, t.id, t.doctor_id, t.primary_nurse_id, t.doctor_id, 'ACTIVE'
  FROM encounter e
  JOIN patient p ON p.id = e.patient_id
  CROSS JOIN (SELECT id, doctor_id, primary_nurse_id FROM care_team WHERE code = 'TEAM-A' LIMIT 1) AS t
 WHERE p.medical_record_no LIKE 'LT%';

-- ---------------------------------------------------------------- 随访路径
INSERT INTO followup_plan (dept_id, patient_id, encounter_id, pathway_label,
                           anchor_discharge_date, care_team_id, doctor_id, nurse_id, status, created_by)
SELECT p.dept_id, p.id, e.id, '压测路径（胆总管结石术后）',
       e.discharge_date, t.id, t.doctor_id, t.primary_nurse_id, 'ACTIVE', t.doctor_id
  FROM patient p
  JOIN encounter e ON e.patient_id = p.id
  CROSS JOIN (SELECT id, doctor_id, primary_nurse_id FROM care_team WHERE code = 'TEAM-A' LIMIT 1) AS t
 WHERE p.medical_record_no LIKE 'LT%';

-- ---------------------------------------------------------------- 随访任务（每人 6 条）
-- 刻意让 1/3 逾期、1/3 今日、1/3 未来，模拟真实待办分布
INSERT INTO followup_task (dept_id, plan_id, patient_id, encounter_id, care_team_id,
                           task_type, title, due_at, due_date, priority, is_mandatory,
                           status, assignee_staff_id, overdue_days)
SELECT pl.dept_id, pl.id, pl.patient_id, pl.encounter_id, pl.care_team_id,
       'PHONE',
       '术后第 ' || n || ' 次电话回访',
       (current_date + (n - 3))::timestamptz + time '09:00',
       current_date + (n - 3),
       (1 + (n % 3))::smallint,
       (n = 1),
       CASE WHEN n <= 2 THEN 'PENDING' ELSE 'PENDING' END,
       CASE WHEN n % 2 = 0 THEN pl.doctor_id ELSE pl.nurse_id END,
       CASE WHEN current_date + (n - 3) < current_date
            THEN (current_date - (current_date + (n - 3)))::int ELSE 0 END
  FROM followup_plan pl
  JOIN patient p ON p.id = pl.patient_id
  CROSS JOIN generate_series(1, 6) AS n
 WHERE p.medical_record_no LIKE 'LT%';

COMMIT;

-- ---------------------------------------------------------------- 结果
SELECT 'patients' AS item, count(*)::text AS n FROM patient WHERE medical_record_no LIKE 'LT%'
UNION ALL SELECT 'encounters', count(*)::text FROM encounter e JOIN patient p ON p.id = e.patient_id WHERE p.medical_record_no LIKE 'LT%'
UNION ALL SELECT 'plans', count(*)::text FROM followup_plan pl JOIN patient p ON p.id = pl.patient_id WHERE p.medical_record_no LIKE 'LT%'
UNION ALL SELECT 'tasks', count(*)::text FROM followup_task t JOIN patient p ON p.id = t.patient_id WHERE p.medical_record_no LIKE 'LT%'
UNION ALL SELECT 'all_tasks', count(*)::text FROM followup_task;

VACUUM ANALYZE patient;
VACUUM ANALYZE encounter;
VACUUM ANALYZE followup_task;
VACUUM ANALYZE followup_plan;

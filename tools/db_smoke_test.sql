-- =============================================================================
--  数据库冒烟测试
--  目的：验证建表脚本产生的「安全闸门」是否真的拦得住
--     1) 病理报告发布闸门（未审核 / 无解读 / 高风险未告知 → 必须拒绝）
--     2) 行级安全策略（护士只能看到自己搭档组的任务）
--     3) 分区路由（日志表按月落地）
--  用法：psql -h 127.0.0.1 -p 55432 -U postgres -d followup_test -f tools/db_smoke_test.sql
-- =============================================================================

\set ON_ERROR_STOP on
\echo '=== 准备测试数据（系统上下文） ==='

SET app.is_system = 'true';

INSERT INTO staff (dept_id, staff_no, name, gender, title, phone_mask, phone_hash, phone_cipher)
SELECT d.id, 'T-D001', '测试医生', 1, '主治医师', '138****0001', 'h1', '\x00'
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO staff (dept_id, staff_no, name, gender, title, phone_mask, phone_hash, phone_cipher)
SELECT d.id, 'T-N001', '测试护士', 2, '主管护师', '138****0002', 'h2', '\x00'
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO staff (dept_id, staff_no, name, gender, title, phone_mask, phone_hash, phone_cipher)
SELECT d.id, 'T-N999', '无关护士', 2, '护士', '138****0003', 'h3', '\x00'
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO care_team (dept_id, code, name, doctor_id, primary_nurse_id)
SELECT d.id, 'T-TEAM1', '测试搭档组',
       (SELECT id FROM staff WHERE staff_no = 'T-D001'),
       (SELECT id FROM staff WHERE staff_no = 'T-N001')
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO care_team_member (team_id, staff_id, member_role, is_primary)
SELECT t.id, s.id, 'DOCTOR', TRUE
FROM care_team t, staff s
WHERE t.code = 'T-TEAM1' AND s.staff_no = 'T-D001'
ON CONFLICT DO NOTHING;

INSERT INTO care_team_member (team_id, staff_id, member_role, is_primary)
SELECT t.id, s.id, 'NURSE', TRUE
FROM care_team t, staff s
WHERE t.code = 'T-TEAM1' AND s.staff_no = 'T-N001'
ON CONFLICT DO NOTHING;

INSERT INTO patient (dept_id, name, gender, age, phone_cipher, phone_hash, phone_mask)
SELECT d.id, '测试患者', 1, 58, '\x00', 'ph-test-001', '138****9999'
FROM department d WHERE d.code = 'XHNK'
  AND NOT EXISTS (SELECT 1 FROM patient WHERE phone_hash = 'ph-test-001');

INSERT INTO encounter (patient_id, dept_id, inpatient_no, admit_date, discharge_date, discharge_type, care_team_id)
SELECT p.id, p.dept_id, 'TZY2026001', DATE '2026-09-06', DATE '2026-09-12', '1',
       (SELECT id FROM care_team WHERE code = 'T-TEAM1')
FROM patient p WHERE p.phone_hash = 'ph-test-001'
ON CONFLICT DO NOTHING;

INSERT INTO patient_care_team (patient_id, encounter_id, team_id, doctor_id, nurse_id, status)
SELECT p.id, e.id, e.care_team_id,
       (SELECT id FROM staff WHERE staff_no = 'T-D001'),
       (SELECT id FROM staff WHERE staff_no = 'T-N001'), 'ACTIVE'
FROM patient p JOIN encounter e ON e.patient_id = p.id
WHERE p.phone_hash = 'ph-test-001'
  AND NOT EXISTS (SELECT 1 FROM patient_care_team WHERE encounter_id = e.id);

INSERT INTO medical_procedure (encounter_id, patient_id, procedure_name, procedure_date, surgeon_id)
SELECT e.id, e.patient_id, '内镜下结肠息肉切除术', TIMESTAMPTZ '2026-09-10 14:00+08',
       (SELECT id FROM staff WHERE staff_no = 'T-D001')
FROM encounter e WHERE e.inpatient_no = 'TZY2026001'
  AND NOT EXISTS (SELECT 1 FROM medical_procedure WHERE encounter_id = e.id);

-- 两个测试模板，用于验证「多路径并行」
INSERT INTO followup_template (dept_id, code, name, disease_category, status, approved_by, approved_at)
SELECT d.id, 'T-TPL-ERCP', '胆总管结石（ERCP 取石术后）随访路径', '胆总管结石', 'ACTIVE',
       (SELECT id FROM staff WHERE staff_no = 'T-D001'), now()
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO followup_template (dept_id, code, name, disease_category, status, approved_by, approved_at)
SELECT d.id, 'T-TPL-GB', '胆囊结石（腹腔镜胆囊切除术后）随访路径', '胆囊结石', 'ACTIVE',
       (SELECT id FROM staff WHERE staff_no = 'T-D001'), now()
FROM department d WHERE d.code = 'XHNK'
ON CONFLICT DO NOTHING;

INSERT INTO followup_template_item (template_id, seq_no, title, anchor_event, offset_days,
                                    executor_role, channel_type, priority, is_mandatory, content_hint)
SELECT t.id, 1, '术后 3 天电话回访', 'SURGERY', 3, 'DOCTOR', 'PHONE', 1, FALSE,
       '腹痛、发热、黄疸、低脂饮食'
FROM followup_template t WHERE t.code = 'T-TPL-ERCP'
ON CONFLICT DO NOTHING;

INSERT INTO followup_template_item (template_id, seq_no, title, anchor_event, offset_days,
                                    executor_role, channel_type, priority, is_mandatory, content_hint)
SELECT t.id, 2, '术后 1 个月门诊复查', 'SURGERY', 30, 'DOCTOR', 'OUTPATIENT', 2, FALSE,
       '复查肝功能、腹部超声'
FROM followup_template t WHERE t.code = 'T-TPL-ERCP'
ON CONFLICT DO NOTHING;

INSERT INTO followup_plan (dept_id, patient_id, encounter_id, anchor_procedure_at,
                           anchor_discharge_date, care_team_id, doctor_id, nurse_id,
                           template_id, template_version, pathway_label)
SELECT e.dept_id, e.patient_id, e.id, TIMESTAMPTZ '2026-09-10 14:00+08', e.discharge_date,
       e.care_team_id,
       (SELECT id FROM staff WHERE staff_no = 'T-D001'),
       (SELECT id FROM staff WHERE staff_no = 'T-N001'),
       (SELECT id FROM followup_template WHERE code = 'T-TPL-ERCP'), 1,
       '胆总管结石（ERCP 取石术后）'
FROM encounter e WHERE e.inpatient_no = 'TZY2026001'
  AND NOT EXISTS (SELECT 1 FROM followup_plan WHERE encounter_id = e.id);

INSERT INTO followup_task (dept_id, plan_id, patient_id, encounter_id, care_team_id,
                           task_type, title, due_at, due_date, status, assignee_staff_id)
SELECT e.dept_id, (SELECT id FROM followup_plan WHERE encounter_id = e.id),
       e.patient_id, e.id, e.care_team_id,
       'PHONE', '术后 3 天电话回访',
       TIMESTAMPTZ '2026-09-13 10:00+08', DATE '2026-09-13', 'PENDING',
       (SELECT id FROM staff WHERE staff_no = 'T-D001')
FROM encounter e WHERE e.inpatient_no = 'TZY2026001'
  AND NOT EXISTS (SELECT 1 FROM followup_task WHERE encounter_id = e.id);

\echo ''
\echo '=== 测试 1：病理发布闸门 ==='

-- 1.1 未审核直接发布 → 必须失败
DO $$
BEGIN
    BEGIN
        INSERT INTO pathology_report (patient_id, encounter_id, conclusion, risk_level, status)
        SELECT e.patient_id, e.id, '测试结论', 'LOW', 'PUBLISHED'
        FROM encounter e WHERE e.inpatient_no = 'TZY2026001';
        RAISE EXCEPTION 'FAIL: 未审核的报告竟然发布成功了';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 1.1 已拦截未审核发布 -> %', SQLERRM;
    END;
END $$;

-- 建立一份待审核报告
INSERT INTO pathology_report (patient_id, encounter_id, conclusion, risk_level,
                              status, entered_by, entered_at)
SELECT e.patient_id, e.id, '（乙状结肠）管状腺瘤，低级别上皮内瘤变，切缘阴性', 'ATTENTION',
       'PENDING_REVIEW', (SELECT id FROM staff WHERE staff_no = 'T-N001'), now()
FROM encounter e WHERE e.inpatient_no = 'TZY2026001'
  AND NOT EXISTS (SELECT 1 FROM pathology_report WHERE encounter_id = e.id);

-- 1.2 医生审核（只记录审核人，暂不发布）→ 应当成功
DO $$
BEGIN
    BEGIN
        UPDATE pathology_report SET status = 'PUBLISHED',
               reviewed_by = (SELECT id FROM staff WHERE staff_no = 'T-D001'),
               reviewed_at = now()
        WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001');
        RAISE EXCEPTION 'FAIL: 没有医生解读竟然发布成功了';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 1.2 已拦截「无医生解读」发布 -> %', SQLERRM;
    END;
END $$;

-- 医生的「审核」动作本身只记录审核人，不改发布状态（审核与发布是两步）
UPDATE pathology_report
SET reviewed_by = (SELECT id FROM staff WHERE staff_no = 'T-D001'),
    reviewed_at = now()
WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001');
\echo '-- 1.2b 医生审核已记录（状态仍为 PENDING_REVIEW）'

-- 补上医生解读
INSERT INTO pathology_interpretation (report_id, plain_text, recheck_months, written_by)
SELECT r.id, '本次切除的是良性息肉，已经完整切除干净，建议 6-12 个月复查肠镜。', 6,
       (SELECT id FROM staff WHERE staff_no = 'T-D001')
FROM pathology_report r
WHERE r.encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001')
  AND NOT EXISTS (SELECT 1 FROM pathology_interpretation WHERE report_id = r.id);

-- 1.3 审核与解读齐备 → 发布应当成功
DO $$
BEGIN
    BEGIN
        UPDATE pathology_report SET status = 'PUBLISHED'
        WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001');
        RAISE NOTICE 'PASS 1.3 条件齐备后发布成功，published_at=%',
            (SELECT published_at FROM pathology_report
             WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001'));
    EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'FAIL: 条件齐备却无法发布 -> %', SQLERRM;
    END;
END $$;

-- 1.4 事后改成高风险、但未告知患者 → 必须失败
DO $$
BEGIN
    BEGIN
        UPDATE pathology_report SET risk_level = 'HIGH'
        WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001');
        RAISE EXCEPTION 'FAIL: 高风险未告知患者竟然生效了';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 1.4 已拦截「高风险未告知」-> %', SQLERRM;
    END;
END $$;

-- 1.5 登记「已告知患者」后，再改成高风险 → 应当成功
INSERT INTO pathology_notification (report_id, notified_by, notified_at, method, target, note)
SELECT r.id, (SELECT id FROM staff WHERE staff_no = 'T-D001'), now(), 'PHONE', 'PATIENT',
       '已电话向患者本人说明结果及复查安排'
FROM pathology_report r
WHERE r.encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001')
  AND NOT EXISTS (SELECT 1 FROM pathology_notification WHERE report_id = r.id);

UPDATE pathology_report SET risk_level = 'HIGH'
WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001');
\echo '-- 1.5 PASS 登记告知后高风险报告可正常流转'

\echo ''
\echo '=== 测试 2：行级安全策略（RLS） ==='
\echo '-- 注意：必须以非超级用户 app_rw 身份测试；超级用户会绕过 RLS。'

RESET ROLE;
SET ROLE app_rw;
SELECT current_user AS testing_as, (SELECT rolsuper FROM pg_roles WHERE rolname = current_user) AS is_super;
SET app.is_system = 'false';

\echo '-- 2.1 以「测试护士」身份查询待办任务（应能看到本组任务）'
SELECT set_config('app.current_staff_id', id::text, false) IS NOT NULL AS ctx_set
FROM staff WHERE staff_no = 'T-N001';
SELECT count(*) AS nurse_sees_tasks FROM followup_task;

\echo '-- 2.2 以「无关护士」身份查询待办任务（应为 0）'
SELECT set_config('app.current_staff_id', id::text, false) IS NOT NULL AS ctx_set
FROM staff WHERE staff_no = 'T-N999';
SELECT count(*) AS unrelated_nurse_sees FROM followup_task;

\echo '-- 2.3 以「无关护士」身份查询患者（应为 0）'
SELECT count(*) AS unrelated_nurse_sees_patients FROM patient;

\echo '-- 2.4 切换为科室管理者（应能看到全部）'
SELECT set_config('app.current_staff_id', '', false) IS NOT NULL AS ctx_cleared;
SELECT set_config('app.is_manager', 'true', false) IS NOT NULL AS manager_on;
SELECT count(*) AS manager_sees_tasks FROM followup_task;

\echo ''
\echo '=== 测试 3：日志分区路由 ==='

RESET ROLE;
SET ROLE app_rw;
SELECT set_config('app.is_system', 'true', false) IS NOT NULL AS sys_on;
SELECT set_config('app.is_manager', 'false', false) IS NOT NULL AS manager_off;

INSERT INTO notify_log (staff_id, channel_code, biz_type, title, content_masked, status, created_at)
VALUES ((SELECT id FROM staff WHERE staff_no = 'T-D001'), 'IN_APP', 'TASK_REMIND',
        '随访待办', '您有 1 条随访任务待处理', 'SENT', TIMESTAMPTZ '2026-09-15 10:00+08');

SELECT tableoid::regclass AS landed_partition, count(*)
FROM notify_log GROUP BY 1;

INSERT INTO audit_log (staff_id, action, resource_type, resource_id, result, created_at)
VALUES ((SELECT id FROM staff WHERE staff_no = 'T-D001'), 'VIEW_PHONE', 'patient', '1',
        'SUCCESS', TIMESTAMPTZ '2026-09-15 10:05+08');

SELECT tableoid::regclass AS landed_partition, count(*)
FROM audit_log GROUP BY 1;

\echo ''
\echo '=== 测试 4：多路径并行（同一患者可同时走多条随访路径） ==='

-- 4.1 为同一次住院再建一条「胆囊结石」路径 → 应当成功
INSERT INTO followup_plan (dept_id, patient_id, encounter_id, anchor_procedure_at,
                           anchor_discharge_date, care_team_id, doctor_id, nurse_id,
                           template_id, template_version, pathway_label)
SELECT e.dept_id, e.patient_id, e.id, TIMESTAMPTZ '2026-09-11 09:00+08', e.discharge_date,
       e.care_team_id,
       (SELECT id FROM staff WHERE staff_no = 'T-D001'),
       (SELECT id FROM staff WHERE staff_no = 'T-N001'),
       (SELECT id FROM followup_template WHERE code = 'T-TPL-GB'), 1,
       '胆囊结石（腹腔镜胆囊切除术后）'
FROM encounter e WHERE e.inpatient_no = 'TZY2026001';

SELECT count(*) AS parallel_plans,
       string_agg(pathway_label, ' | ' ORDER BY id) AS pathways
FROM followup_plan
WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001')
  AND status = 'ACTIVE';

\echo '-- 4.2 重复生成【同一模板】的路径 → 必须被拒绝'
DO $$
BEGIN
    BEGIN
        INSERT INTO followup_plan (dept_id, patient_id, encounter_id, care_team_id,
                                   doctor_id, template_id, template_version, pathway_label)
        SELECT e.dept_id, e.patient_id, e.id, e.care_team_id,
               (SELECT id FROM staff WHERE staff_no = 'T-D001'),
               (SELECT id FROM followup_template WHERE code = 'T-TPL-ERCP'), 1,
               '重复的胆总管结石路径'
        FROM encounter e WHERE e.inpatient_no = 'TZY2026001';
        RAISE EXCEPTION 'FAIL: 同一模板竟然重复生成了路径';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 4.2 已拦截同一模板重复生成 -> %', SQLERRM;
    END;
END $$;

\echo ''
\echo '=== 测试 5：任务生成幂等性（重复跑调度不产生重复待办） ==='

-- 生成任务（模拟调度器第一次执行）
INSERT INTO followup_task (dept_id, plan_id, template_item_id, patient_id, encounter_id,
                           care_team_id, task_type, title, due_at, due_date, status, assignee_staff_id)
SELECT e.dept_id, p.id, ti.id, e.patient_id, e.id, e.care_team_id,
       'PHONE', ti.title,
       (TIMESTAMPTZ '2026-09-10 14:00+08' + (ti.offset_days || ' day')::interval),
       ((TIMESTAMPTZ '2026-09-10 14:00+08' + (ti.offset_days || ' day')::interval) AT TIME ZONE 'Asia/Shanghai')::date,
       'PENDING', (SELECT id FROM staff WHERE staff_no = 'T-D001')
FROM followup_plan p
JOIN encounter e ON e.id = p.encounter_id
JOIN followup_template_item ti ON ti.template_id = p.template_id
WHERE e.inpatient_no = 'TZY2026001'
  AND ti.seq_no = 1
ON CONFLICT DO NOTHING;

SELECT count(*) AS tasks_after_first_run
FROM followup_task
WHERE plan_id = (SELECT id FROM followup_plan
                 WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001')
                   AND pathway_label LIKE '胆总管%')
  AND template_item_id IS NOT NULL;

-- 5.1 再跑一次完全相同的调度 → 任务数不应增加
INSERT INTO followup_task (dept_id, plan_id, template_item_id, patient_id, encounter_id,
                           care_team_id, task_type, title, due_at, due_date, status, assignee_staff_id)
SELECT e.dept_id, p.id, ti.id, e.patient_id, e.id, e.care_team_id,
       'PHONE', ti.title,
       (TIMESTAMPTZ '2026-09-10 14:00+08' + (ti.offset_days || ' day')::interval),
       ((TIMESTAMPTZ '2026-09-10 14:00+08' + (ti.offset_days || ' day')::interval) AT TIME ZONE 'Asia/Shanghai')::date,
       'PENDING', (SELECT id FROM staff WHERE staff_no = 'T-D001')
FROM followup_plan p
JOIN encounter e ON e.id = p.encounter_id
JOIN followup_template_item ti ON ti.template_id = p.template_id
WHERE e.inpatient_no = 'TZY2026001'
  AND ti.seq_no = 1
ON CONFLICT DO NOTHING;

SELECT count(*) AS tasks_after_second_run
FROM followup_task
WHERE plan_id = (SELECT id FROM followup_plan
                 WHERE encounter_id = (SELECT id FROM encounter WHERE inpatient_no = 'TZY2026001')
                   AND pathway_label LIKE '胆总管%')
  AND template_item_id IS NOT NULL;

\echo '-- 5.2 直接插入重复的（计划, 模板条目）任务 → 必须被拒绝'
DO $$
DECLARE
    v_plan BIGINT;
    v_item BIGINT;
BEGIN
    SELECT p.id, ti.id INTO v_plan, v_item
    FROM followup_plan p
    JOIN followup_template_item ti ON ti.template_id = p.template_id
    JOIN encounter e ON e.id = p.encounter_id
    WHERE e.inpatient_no = 'TZY2026001' AND ti.seq_no = 1 AND p.status = 'ACTIVE'
    LIMIT 1;

    BEGIN
        INSERT INTO followup_task (dept_id, plan_id, template_item_id, patient_id, encounter_id,
                                   task_type, title, due_at, due_date, status)
        SELECT dept_id, v_plan, v_item, patient_id, encounter_id,
               'PHONE', '重复任务', now(), current_date, 'PENDING'
        FROM followup_task WHERE plan_id = v_plan LIMIT 1;
        RAISE EXCEPTION 'FAIL: 重复任务竟然插入成功';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS 5.2 已拦截重复任务 -> %', SQLERRM;
    END;
END $$;

\echo ''
\echo '=== 冒烟测试结束 ==='

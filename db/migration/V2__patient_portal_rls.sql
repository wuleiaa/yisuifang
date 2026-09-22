-- =============================================================================
--  V2：补齐患者端（小程序）的行级安全策略
--
--  背景（V1 里的一处真实缺口）：
--    patient 表原本的策略里，患者端分支写成
--        OR current_setting('app.is_patient_portal', true) = 'true'
--    这一条没有限定"只能看自己"——只要请求带上患者端标记，
--    就能读到全部患者。患者端一旦上线，这是一个会直接泄露患者名单的洞。
--
--  本迁移做三件事：
--    1. 把 patient 的患者端分支收紧为"只能读到自己"；
--    2. 给 followup_task 补上患者端分支（原来完全没有，患者看不到自己的随访任务）；
--    3. 给 followup_record 补上患者端分支（患者要能回看自己填过的记录）。
--
--  说明：策略变更必须走版本化迁移脚本（铁律 4），禁止手工改线上库。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. patient：患者端只能读到自己
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_patient_access ON patient;
CREATE POLICY p_patient_access ON patient
    USING (
        current_setting('app.is_system', true)  = 'true'
        OR current_setting('app.is_manager', true) = 'true'
        OR id IN (
            SELECT pct.patient_id FROM patient_care_team pct
            JOIN care_team_member ctm ON ctm.team_id = pct.team_id
            WHERE ctm.staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
              AND pct.status = 'ACTIVE'
        )
        -- 患者端：只允许读自己那一条
        OR (
            current_setting('app.is_patient_portal', true) = 'true'
            AND id = nullif(current_setting('app.current_patient_id', true), '')::bigint
        )
    );

-- -----------------------------------------------------------------------------
-- 2. followup_task：患者端可以看自己的随访任务
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_task_access ON followup_task;
CREATE POLICY p_task_access ON followup_task
    USING (
        current_setting('app.is_system', true)  = 'true'
        OR current_setting('app.is_manager', true) = 'true'
        OR assignee_staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
        OR care_team_id IN (
            SELECT ctm.team_id FROM care_team_member ctm
            WHERE ctm.staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
        )
        -- 患者端：只允许读自己的任务
        OR (
            current_setting('app.is_patient_portal', true) = 'true'
            AND patient_id = nullif(current_setting('app.current_patient_id', true), '')::bigint
        )
    );

-- -----------------------------------------------------------------------------
-- 3. followup_record：患者端可以回看自己的记录
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS p_record_access ON followup_record;
CREATE POLICY p_record_access ON followup_record
    USING (
        current_setting('app.is_system', true)  = 'true'
        OR current_setting('app.is_manager', true) = 'true'
        OR executed_by = nullif(current_setting('app.current_staff_id', true), '')::bigint
        OR patient_id IN (
            SELECT pct.patient_id FROM patient_care_team pct
            JOIN care_team_member ctm ON ctm.team_id = pct.team_id
            WHERE ctm.staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
              AND pct.status = 'ACTIVE'
        )
        -- 患者端：只允许读自己的记录
        OR (
            current_setting('app.is_patient_portal', true) = 'true'
            AND patient_id = nullif(current_setting('app.current_patient_id', true), '')::bigint
        )
    );

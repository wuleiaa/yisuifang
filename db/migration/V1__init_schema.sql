-- =============================================================================
--  医院回访管理系统 · 数据库结构与初始化脚本
--  版本   : V1
--  数据库 : PostgreSQL 16
--  字符集 : UTF-8
--  说明   : 本脚本可重复执行（幂等），用于初始化全新数据库。
--           生产环境的后续变更请新建 V2__xxx.sql，禁止直接修改本文件。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 扩展
-- -----------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto;    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS pg_trgm;     -- 姓名 / 诊断 模糊搜索

-- 通用 updated_at 触发器函数
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- =============================================================================
-- 1. 组织与人员
-- =============================================================================

CREATE TABLE IF NOT EXISTS department (
    id          BIGSERIAL PRIMARY KEY,
    public_id   UUID         NOT NULL DEFAULT gen_random_uuid(),
    code        VARCHAR(50)  NOT NULL,
    name        VARCHAR(100) NOT NULL,
    parent_id   BIGINT       REFERENCES department(id),
    status      SMALLINT     NOT NULL DEFAULT 1,      -- 1启用 0停用
    sort_no     INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at  TIMESTAMPTZ
);
COMMENT ON TABLE  department      IS '科室';
COMMENT ON COLUMN department.status IS '1启用 0停用';
CREATE UNIQUE INDEX IF NOT EXISTS uk_department_code      ON department(code)      WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_department_public_id ON department(public_id);


CREATE TABLE IF NOT EXISTS staff (
    id            BIGSERIAL PRIMARY KEY,
    public_id     UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id       BIGINT       NOT NULL REFERENCES department(id),
    staff_no      VARCHAR(50)  NOT NULL,                       -- 工号，如 D0231 / N0455
    name          VARCHAR(50)  NOT NULL,
    gender        SMALLINT     CHECK (gender IN (1,2)),        -- 1男 2女
    title         VARCHAR(50),                                 -- 职称
    phone_cipher  BYTEA,                                       -- 手机号密文 (AES-256-GCM)
    phone_hash    VARCHAR(64),                                 -- HMAC-SHA256，用于精确查找
    phone_mask    VARCHAR(20),                                 -- 138****5678
    email         VARCHAR(100),
    status        SMALLINT     NOT NULL DEFAULT 1,             -- 1在职 0离职
    is_manager    BOOLEAN      NOT NULL DEFAULT FALSE,         -- 科室管理者（护士长/主任）
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at    TIMESTAMPTZ
);
COMMENT ON TABLE  staff           IS '医护人员；禁止自助注册，由管理员创建';
COMMENT ON COLUMN staff.staff_no  IS '工号，全院唯一，与医院人事口径一致';
COMMENT ON COLUMN staff.phone_cipher IS '手机号密文，密钥不存库';
COMMENT ON COLUMN staff.phone_hash   IS 'HMAC-SHA256(手机号, pepper)，用于等值查询';
CREATE UNIQUE INDEX IF NOT EXISTS uk_staff_no        ON staff(staff_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_staff_public_id ON staff(public_id);
CREATE INDEX        IF NOT EXISTS idx_staff_phone    ON staff(phone_hash);
CREATE INDEX        IF NOT EXISTS idx_staff_dept     ON staff(dept_id, status) WHERE deleted_at IS NULL;


-- 医护搭档组：1 名主管医生 + N 名护士。随访任务挂在组上，不挂个人。
CREATE TABLE IF NOT EXISTS care_team (
    id               BIGSERIAL PRIMARY KEY,
    public_id        UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id          BIGINT       NOT NULL REFERENCES department(id),
    code             VARCHAR(50),
    name             VARCHAR(100) NOT NULL,                    -- 如「李医生-王护士 组」
    doctor_id        BIGINT       REFERENCES staff(id),
    primary_nurse_id BIGINT       REFERENCES staff(id),
    status           SMALLINT     NOT NULL DEFAULT 1,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
COMMENT ON TABLE care_team IS '医护搭档组；调岗/轮转时只改组员，不改任务';
CREATE UNIQUE INDEX IF NOT EXISTS uk_care_team_public_id ON care_team(public_id);
CREATE INDEX        IF NOT EXISTS idx_care_team_dept     ON care_team(dept_id, status) WHERE deleted_at IS NULL;


CREATE TABLE IF NOT EXISTS care_team_member (
    id          BIGSERIAL PRIMARY KEY,
    team_id     BIGINT      NOT NULL REFERENCES care_team(id) ON DELETE CASCADE,
    staff_id    BIGINT      NOT NULL REFERENCES staff(id),
    member_role VARCHAR(20) NOT NULL CHECK (member_role IN ('DOCTOR','NURSE')),
    is_primary  BOOLEAN     NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE care_team_member IS '搭档组成员';
CREATE UNIQUE INDEX IF NOT EXISTS uk_ctm ON care_team_member(team_id, staff_id, member_role);
CREATE INDEX        IF NOT EXISTS idx_ctm_staff ON care_team_member(staff_id);


-- 离岗登记：休假/进修期间的任务归属与代理人
CREATE TABLE IF NOT EXISTS staff_absence (
    id                BIGSERIAL PRIMARY KEY,
    staff_id          BIGINT      NOT NULL REFERENCES staff(id),
    start_date        DATE        NOT NULL,
    end_date          DATE        NOT NULL,
    absence_type      VARCHAR(20) NOT NULL DEFAULT 'LEAVE',   -- LEAVE/TRAINING/OTHER
    reason            VARCHAR(200),
    delegate_staff_id BIGINT      REFERENCES staff(id),
    status            VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_by        BIGINT      REFERENCES staff(id),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ck_absence_range CHECK (end_date >= start_date)
);
COMMENT ON TABLE staff_absence IS '离岗登记，支持指定代理人';
CREATE INDEX IF NOT EXISTS idx_absence_staff ON staff_absence(staff_id, start_date, end_date);


-- =============================================================================
-- 2. 账号与权限
-- =============================================================================

CREATE TABLE IF NOT EXISTS account (
    id                   BIGSERIAL PRIMARY KEY,
    public_id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    account_type         VARCHAR(20)  NOT NULL CHECK (account_type IN ('STAFF','PATIENT')),
    login_hash           VARCHAR(64)  NOT NULL,                 -- HMAC-SHA256(登录名, pepper)
    login_display        VARCHAR(100) NOT NULL,                 -- 展示用（工号 / 脱敏手机号）
    password_hash        VARCHAR(200) NOT NULL,                 -- BCrypt
    password_updated_at  TIMESTAMPTZ,
    staff_id             BIGINT       REFERENCES staff(id),
    patient_id           BIGINT,                                -- FK 在 patient 表创建后补充
    status               VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                         CHECK (status IN ('PENDING','ACTIVE','LOCKED','DISABLED')),
    failed_attempts      INT          NOT NULL DEFAULT 0,
    locked_until         TIMESTAMPTZ,
    last_login_at        TIMESTAMPTZ,
    must_change_password BOOLEAN      NOT NULL DEFAULT FALSE,
    wechat_openid        VARCHAR(64),
    wechat_unionid       VARCHAR(64),
    created_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMPTZ
);
COMMENT ON TABLE  account             IS '统一登录账号：医护 + 患者';
COMMENT ON COLUMN account.login_hash  IS '登录名的 HMAC-SHA256，避免明文与可枚举';
COMMENT ON COLUMN account.status      IS 'PENDING=待激活（医护邀请码激活前）';
CREATE UNIQUE INDEX IF NOT EXISTS uk_account_login      ON account(login_hash) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_account_public_id  ON account(public_id);
CREATE UNIQUE INDEX IF NOT EXISTS uk_account_staff      ON account(staff_id)   WHERE staff_id IS NOT NULL AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_account_patient    ON account(patient_id) WHERE patient_id IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX        IF NOT EXISTS idx_account_openid    ON account(wechat_openid) WHERE wechat_openid IS NOT NULL;


CREATE TABLE IF NOT EXISTS role (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(50)  NOT NULL UNIQUE,     -- SUPER_ADMIN / DEPT_MANAGER / DOCTOR / NURSE / FOLLOWUP_OFFICER / AUDITOR
    name        VARCHAR(50)  NOT NULL,
    description VARCHAR(200),
    is_system   BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE role IS '角色';


CREATE TABLE IF NOT EXISTS permission (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(100) NOT NULL UNIQUE,     -- 如 patient:read / task:assign / report:publish
    name        VARCHAR(100) NOT NULL,
    module      VARCHAR(50),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE permission IS '权限点';


CREATE TABLE IF NOT EXISTS role_permission (
    role_id       BIGINT NOT NULL REFERENCES role(id)       ON DELETE CASCADE,
    permission_id BIGINT NOT NULL REFERENCES permission(id) ON DELETE CASCADE,
    PRIMARY KEY (role_id, permission_id)
);


CREATE TABLE IF NOT EXISTS staff_role (
    staff_id   BIGINT      NOT NULL REFERENCES staff(id) ON DELETE CASCADE,
    role_id    BIGINT      NOT NULL REFERENCES role(id)  ON DELETE CASCADE,
    granted_by BIGINT      REFERENCES staff(id),
    granted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (staff_id, role_id)
);
COMMENT ON TABLE staff_role IS '医护角色绑定';


-- =============================================================================
-- 3. 患者与就诊
-- =============================================================================

CREATE TABLE IF NOT EXISTS patient (
    id             BIGSERIAL PRIMARY KEY,
    public_id      UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id        BIGINT       NOT NULL REFERENCES department(id),
    medical_record_no VARCHAR(50),                            -- 病案号：患者终身唯一，跨多次住院不变
    name           VARCHAR(50)  NOT NULL,
    name_pinyin    VARCHAR(100),                              -- 拼音首字母，便于快速检索
    gender         SMALLINT     NOT NULL CHECK (gender IN (1,2)),
    birth_date     DATE,
    age            INT          CHECK (age IS NULL OR (age >= 0 AND age <= 150)),
    id_card_cipher BYTEA,
    id_card_hash   VARCHAR(64),
    id_card_mask   VARCHAR(30),
    phone_cipher   BYTEA        NOT NULL,
    phone_hash     VARCHAR(64)  NOT NULL,
    phone_mask     VARCHAR(20)  NOT NULL,
    address        VARCHAR(300),
    remark         TEXT,
    status         VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE'
                   CHECK (status IN ('ACTIVE','ARCHIVED','DECEASED')),
    created_by     BIGINT       REFERENCES staff(id),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at     TIMESTAMPTZ
);
COMMENT ON TABLE  patient              IS '患者主档；联系方式加密存储';
COMMENT ON COLUMN patient.medical_record_no IS '病案号，患者终身唯一；用于识别同一患者的多次住院（可为空）';
COMMENT ON COLUMN patient.phone_cipher IS '手机号密文 (AES-256-GCM)，密钥存于 KMS/环境变量';
COMMENT ON COLUMN patient.phone_hash   IS '手机号 HMAC-SHA256，用于等值查找（不可逆）';
COMMENT ON COLUMN patient.phone_mask   IS '脱敏展示缓存，列表页直接使用，避免解密';
CREATE UNIQUE INDEX IF NOT EXISTS uk_patient_public_id ON patient(public_id);
CREATE INDEX        IF NOT EXISTS idx_patient_phone    ON patient(phone_hash);
CREATE INDEX        IF NOT EXISTS idx_patient_mrn      ON patient(medical_record_no) WHERE medical_record_no IS NOT NULL;
CREATE INDEX        IF NOT EXISTS idx_patient_name     ON patient USING gin (name gin_trgm_ops);
CREATE INDEX        IF NOT EXISTS idx_patient_dept     ON patient(dept_id, status) WHERE deleted_at IS NULL;


-- 联系人：患者本人无手机 / 留家属号码时使用
CREATE TABLE IF NOT EXISTS patient_contact (
    id           BIGSERIAL PRIMARY KEY,
    patient_id   BIGINT       NOT NULL REFERENCES patient(id) ON DELETE CASCADE,
    name         VARCHAR(50)  NOT NULL,
    relation     VARCHAR(30),                                  -- 本人/配偶/儿子/女儿/其他
    phone_cipher BYTEA        NOT NULL,
    phone_hash   VARCHAR(64)  NOT NULL,
    phone_mask   VARCHAR(20)  NOT NULL,
    is_primary   BOOLEAN      NOT NULL DEFAULT FALSE,          -- 首选联系号码
    sort_no      INT          NOT NULL DEFAULT 0,
    remark       VARCHAR(200),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ
);
COMMENT ON TABLE patient_contact IS '患者联系人（家属号码），支持多个';
CREATE INDEX IF NOT EXISTS idx_pcontact_patient ON patient_contact(patient_id, sort_no) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_pcontact_phone   ON patient_contact(phone_hash);


-- 就诊（住院）记录
CREATE TABLE IF NOT EXISTS encounter (
    id               BIGSERIAL PRIMARY KEY,
    public_id        UUID         NOT NULL DEFAULT gen_random_uuid(),
    patient_id       BIGINT       NOT NULL REFERENCES patient(id),
    dept_id          BIGINT       NOT NULL REFERENCES department(id),
    inpatient_no     VARCHAR(50)  NOT NULL,                    -- 住院号（唯一）
    visit_seq        INT          NOT NULL DEFAULT 1,          -- 第几次住院
    bed_no           VARCHAR(20),
    admit_date       DATE,
    discharge_date   DATE,
    stay_days        INT,
    discharge_type   VARCHAR(30),                              -- 医嘱离院/转院/转科/死亡
    discharge_summary TEXT,
    care_team_id     BIGINT       REFERENCES care_team(id),
    his_patient_id   VARCHAR(64),                              -- 预留 HIS 对接
    his_visit_id     VARCHAR(64),
    import_batch_id  BIGINT,                                   -- 来源导入批次
    created_by       BIGINT       REFERENCES staff(id),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ,
    CONSTRAINT ck_encounter_dates CHECK (discharge_date IS NULL OR admit_date IS NULL OR discharge_date >= admit_date)
);
COMMENT ON TABLE  encounter              IS '住院记录；本系统只管理住院患者（门诊检查不纳入）';
COMMENT ON COLUMN encounter.inpatient_no IS '住院号，全院统一编号，每次住院一个；导入时的唯一判重键';
CREATE UNIQUE INDEX IF NOT EXISTS uk_encounter_inpatient ON encounter(inpatient_no) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS uk_encounter_public_id ON encounter(public_id);
CREATE INDEX        IF NOT EXISTS idx_encounter_patient  ON encounter(patient_id, discharge_date DESC);
CREATE INDEX        IF NOT EXISTS idx_encounter_discharge ON encounter(discharge_date DESC) WHERE deleted_at IS NULL;


-- 诊断
CREATE TABLE IF NOT EXISTS diagnosis (
    id             BIGSERIAL PRIMARY KEY,
    encounter_id   BIGINT       NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    patient_id     BIGINT       NOT NULL REFERENCES patient(id),
    diag_type      VARCHAR(20)  NOT NULL DEFAULT 'DISCHARGE',  -- ADMISSION/DISCHARGE
    seq_no         INT          NOT NULL DEFAULT 1,
    is_primary     BOOLEAN      NOT NULL DEFAULT FALSE,
    icd_code       VARCHAR(20),
    diagnosis_name VARCHAR(200) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  diagnosis                IS '诊断；出院诊断用于自动匹配随访路径';
COMMENT ON COLUMN diagnosis.diagnosis_name IS '诊断全称，如「十二指肠球部溃疡伴出血」';
CREATE INDEX IF NOT EXISTS idx_diag_encounter ON diagnosis(encounter_id);
CREATE INDEX IF NOT EXISTS idx_diag_name      ON diagnosis USING gin (diagnosis_name gin_trgm_ops);


-- 手术 / 操作
CREATE TABLE IF NOT EXISTS medical_procedure (
    id              BIGSERIAL PRIMARY KEY,
    encounter_id    BIGINT       NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    patient_id      BIGINT       NOT NULL REFERENCES patient(id),
    procedure_name  VARCHAR(200) NOT NULL,
    procedure_code  VARCHAR(50),
    procedure_date  TIMESTAMPTZ  NOT NULL,                     -- 随访时间轴的优先锚点
    is_primary      BOOLEAN      NOT NULL DEFAULT FALSE,
    surgeon_id      BIGINT       REFERENCES staff(id),         -- 主刀 / 术者
    assistant       TEXT,
    remark          TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);
COMMENT ON TABLE  medical_procedure                IS '手术/操作记录';
COMMENT ON COLUMN medical_procedure.procedure_date IS '有手术日期时按此计算随访时间，否则回退按出院日期';
CREATE INDEX IF NOT EXISTS idx_proc_encounter ON medical_procedure(encounter_id);
CREATE INDEX IF NOT EXISTS idx_proc_date      ON medical_procedure(procedure_date DESC);


-- 患者 ↔ 搭档组 归属关系（住院时手工指定）
CREATE TABLE IF NOT EXISTS patient_care_team (
    id           BIGSERIAL PRIMARY KEY,
    patient_id   BIGINT      NOT NULL REFERENCES patient(id),
    encounter_id BIGINT      NOT NULL REFERENCES encounter(id) ON DELETE CASCADE,
    team_id      BIGINT      NOT NULL REFERENCES care_team(id),
    doctor_id    BIGINT      NOT NULL REFERENCES staff(id),
    nurse_id     BIGINT      REFERENCES staff(id),
    assigned_by  BIGINT      REFERENCES staff(id),
    assigned_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status       VARCHAR(20) NOT NULL DEFAULT 'ACTIVE',
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE  patient_care_team     IS '患者在本次住院的主管医护关系（住院时手工指定）';
COMMENT ON COLUMN patient_care_team.doctor_id IS '主管医生快照，便于历史追溯';
CREATE UNIQUE INDEX IF NOT EXISTS uk_pct_active ON patient_care_team(encounter_id) WHERE status = 'ACTIVE';
CREATE INDEX        IF NOT EXISTS idx_pct_team  ON patient_care_team(team_id, status);
CREATE INDEX        IF NOT EXISTS idx_pct_patient ON patient_care_team(patient_id);

-- 补上 account.patient_id 外键
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_account_patient') THEN
        ALTER TABLE account ADD CONSTRAINT fk_account_patient
            FOREIGN KEY (patient_id) REFERENCES patient(id);
    END IF;
END $$;


-- =============================================================================
-- 4. 随访路径模板
-- =============================================================================

CREATE TABLE IF NOT EXISTS followup_template (
    id               BIGSERIAL PRIMARY KEY,
    public_id        UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id          BIGINT       NOT NULL REFERENCES department(id),
    code             VARCHAR(50)  NOT NULL,
    name             VARCHAR(150) NOT NULL,
    disease_category VARCHAR(50),
    version          INT          NOT NULL DEFAULT 1,
    is_current       BOOLEAN      NOT NULL DEFAULT TRUE,
    description      TEXT,
    status           VARCHAR(20)  NOT NULL DEFAULT 'DRAFT'
                     CHECK (status IN ('DRAFT','ACTIVE','DISABLED')),
    approved_by      BIGINT       REFERENCES staff(id),        -- 医生审核签字
    approved_at      TIMESTAMPTZ,
    created_by       BIGINT       REFERENCES staff(id),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
COMMENT ON TABLE  followup_template         IS '随访路径模板（按病种，带版本）';
COMMENT ON COLUMN followup_template.status  IS 'DRAFT=草稿 ACTIVE=启用（须经医生审核）';
COMMENT ON COLUMN followup_template.version IS '模板可版本化，历史计划固定引用旧版本';
CREATE UNIQUE INDEX IF NOT EXISTS uk_ftpl_code_ver  ON followup_template(code, version);
CREATE UNIQUE INDEX IF NOT EXISTS uk_ftpl_public_id ON followup_template(public_id);
CREATE INDEX        IF NOT EXISTS idx_ftpl_dept     ON followup_template(dept_id, status) WHERE deleted_at IS NULL;


CREATE TABLE IF NOT EXISTS followup_template_item (
    id             BIGSERIAL PRIMARY KEY,
    template_id    BIGINT       NOT NULL REFERENCES followup_template(id) ON DELETE CASCADE,
    seq_no         INT          NOT NULL,
    title          VARCHAR(200) NOT NULL,
    anchor_event   VARCHAR(30)  NOT NULL
                   CHECK (anchor_event IN ('ADMISSION','SURGERY','DISCHARGE','PATHOLOGY_REPORT','CUSTOM')),
    offset_days    INT          NOT NULL DEFAULT 0,            -- 相对锚点天数；负数为提前
    window_days    INT          NOT NULL DEFAULT 0,            -- 允许提前/延后窗口
    executor_role  VARCHAR(20)  NOT NULL
                   CHECK (executor_role IN ('DOCTOR','NURSE','SYSTEM','PATIENT')),
    channel_type   VARCHAR(30)  NOT NULL
                   CHECK (channel_type IN ('PHONE','OUTPATIENT','SYSTEM_NOTIFY','QUESTIONNAIRE','ONSITE')),
    priority       SMALLINT     NOT NULL DEFAULT 2,            -- 1高 2中 3低
    is_mandatory   BOOLEAN      NOT NULL DEFAULT FALSE,        -- 不可忽略（如胃溃疡复查胃镜）
    content_hint   TEXT,                                       -- 电话要问什么
    form_code      VARCHAR(50),                                -- 关联表单
    condition_json JSONB,                                      -- 分支条件
    remind_policy  JSONB,                                      -- 覆盖全局提醒策略
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  followup_template_item               IS '随访路径条目；一条 = 一个随访时间点';
COMMENT ON COLUMN followup_template_item.anchor_event  IS '时间锚点：入院/手术/出院/病理报告';
COMMENT ON COLUMN followup_template_item.condition_json IS '分支条件，如 {"hp":"POSITIVE"} 或 {"diagnosis_contains":"胃溃疡"}';
CREATE UNIQUE INDEX IF NOT EXISTS uk_fti_seq ON followup_template_item(template_id, seq_no);
CREATE INDEX        IF NOT EXISTS idx_fti_tpl ON followup_template_item(template_id);


-- 模板自动匹配规则（出院诊断 → 随访路径）
CREATE TABLE IF NOT EXISTS template_match_rule (
    id          BIGSERIAL PRIMARY KEY,
    template_id BIGINT       NOT NULL REFERENCES followup_template(id) ON DELETE CASCADE,
    rule_type   VARCHAR(30)  NOT NULL
                CHECK (rule_type IN ('DIAGNOSIS','ICD','PROCEDURE','FIELD')),
    rule_field  VARCHAR(50),
    rule_value  VARCHAR(200) NOT NULL,
    match_mode  VARCHAR(20)  NOT NULL DEFAULT 'CONTAINS'
                CHECK (match_mode IN ('CONTAINS','EXACT','PREFIX','REGEX')),
    weight      INT          NOT NULL DEFAULT 100,             -- 命中多个模板时取权重最高
    is_negative BOOLEAN      NOT NULL DEFAULT FALSE,           -- 排除条件
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE template_match_rule IS '出院诊断自动匹配随访模板的规则';
CREATE INDEX IF NOT EXISTS idx_tmr_tpl ON template_match_rule(template_id);


-- =============================================================================
-- 5. 随访计划与任务
-- =============================================================================

CREATE TABLE IF NOT EXISTS followup_plan (
    id               BIGSERIAL PRIMARY KEY,
    public_id        UUID        NOT NULL DEFAULT gen_random_uuid(),
    dept_id          BIGINT      NOT NULL REFERENCES department(id),
    patient_id       BIGINT      NOT NULL REFERENCES patient(id),
    encounter_id     BIGINT      NOT NULL REFERENCES encounter(id),
    template_id      BIGINT      REFERENCES followup_template(id),
    template_version INT,
    pathway_label    VARCHAR(150),                             -- 显示名，如「胆总管结石（ERCP 术后）」
    anchor_procedure_at  TIMESTAMPTZ,                          -- 锚点：手术时间
    anchor_discharge_date DATE,                                -- 锚点：出院日期
    care_team_id     BIGINT      REFERENCES care_team(id),
    doctor_id        BIGINT      REFERENCES staff(id),
    nurse_id         BIGINT      REFERENCES staff(id),
    status           VARCHAR(20) NOT NULL DEFAULT 'ACTIVE'
                     CHECK (status IN ('ACTIVE','PAUSED','CLOSED')),
    started_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    closed_at        TIMESTAMPTZ,
    close_reason     VARCHAR(100),
    created_by       BIGINT      REFERENCES staff(id),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at       TIMESTAMPTZ
);
COMMENT ON TABLE  followup_plan                     IS '患者随访计划（由模板实例化）';
COMMENT ON COLUMN followup_plan.anchor_procedure_at IS '优先锚点：手术/操作时间';
COMMENT ON COLUMN followup_plan.pathway_label       IS '并行路径的显示名；一个患者可同时存在多条未关闭计划';
CREATE UNIQUE INDEX IF NOT EXISTS uk_plan_public_id ON followup_plan(public_id);
-- 允许同一患者并行多条随访路径（如胆总管结石 + 胆囊结石），但同一模板不可重复生成
CREATE UNIQUE INDEX IF NOT EXISTS uk_plan_enc_tpl ON followup_plan(encounter_id, template_id)
    WHERE status <> 'CLOSED' AND template_id IS NOT NULL;
CREATE INDEX        IF NOT EXISTS idx_plan_patient  ON followup_plan(patient_id, status);


CREATE TABLE IF NOT EXISTS followup_task (
    id                BIGSERIAL PRIMARY KEY,
    public_id         UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id           BIGINT       NOT NULL REFERENCES department(id),
    plan_id           BIGINT       REFERENCES followup_plan(id),
    template_item_id  BIGINT       REFERENCES followup_template_item(id),
    patient_id        BIGINT       NOT NULL REFERENCES patient(id),
    encounter_id      BIGINT       NOT NULL REFERENCES encounter(id),
    care_team_id      BIGINT       REFERENCES care_team(id),
    task_type         VARCHAR(30)  NOT NULL
                      CHECK (task_type IN ('PHONE','OUTPATIENT','SYSTEM_NOTIFY','QUESTIONNAIRE','ONSITE')),
    title             VARCHAR(200) NOT NULL,
    content_hint      TEXT,
    due_at            TIMESTAMPTZ  NOT NULL,                   -- 应完成时间点
    due_date          DATE         NOT NULL,                   -- 冗余，便于按日索引与统计
    remind_start_at   TIMESTAMPTZ,                             -- 开始提醒时间
    priority          SMALLINT     NOT NULL DEFAULT 2,
    is_mandatory      BOOLEAN      NOT NULL DEFAULT FALSE,
    status            VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                      CHECK (status IN ('PENDING','DOING','DONE','SKIPPED','CANCELLED','EXPIRED')),
    assignee_staff_id BIGINT       REFERENCES staff(id),       -- 责任人
    executor_staff_id BIGINT       REFERENCES staff(id),       -- 实际执行人（护士代录时与责任人不同）
    remind_count      INT          NOT NULL DEFAULT 0,
    last_remind_at    TIMESTAMPTZ,
    overdue_days      INT          NOT NULL DEFAULT 0,
    locked_by         BIGINT       REFERENCES staff(id),       -- 抢占锁，防止两人同时处理
    locked_at         TIMESTAMPTZ,
    completed_at      TIMESTAMPTZ,
    remark            TEXT,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at        TIMESTAMPTZ
);
COMMENT ON TABLE  followup_task                   IS '随访任务（待办）';
COMMENT ON COLUMN followup_task.assignee_staff_id IS '责任人（主管医生或主管护士）';
COMMENT ON COLUMN followup_task.executor_staff_id IS '实际执行人；护士代录时记录护士，责任可追溯';
COMMENT ON COLUMN followup_task.is_mandatory      IS '不可忽略任务，如胃溃疡 6-8 周复查胃镜';
CREATE UNIQUE INDEX IF NOT EXISTS uk_task_public_id ON followup_task(public_id);
CREATE INDEX IF NOT EXISTS idx_task_assignee ON followup_task(assignee_staff_id, status, due_at);
CREATE INDEX IF NOT EXISTS idx_task_due      ON followup_task(due_date) WHERE status IN ('PENDING','DOING');
CREATE INDEX IF NOT EXISTS idx_task_patient  ON followup_task(patient_id, due_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_team     ON followup_task(care_team_id, status);
CREATE INDEX IF NOT EXISTS idx_task_plan     ON followup_task(plan_id);
-- 幂等性保证：同一计划下的同一模板条目只会生成一条任务，重复跑调度不会产生重复待办
CREATE UNIQUE INDEX IF NOT EXISTS uk_task_plan_item ON followup_task(plan_id, template_item_id)
    WHERE template_item_id IS NOT NULL AND deleted_at IS NULL;


-- 任务流水（只追加）：创建 / 提醒 / 升级 / 改派 / 完成
CREATE TABLE IF NOT EXISTS followup_task_log (
    id         BIGSERIAL PRIMARY KEY,
    task_id    BIGINT       NOT NULL REFERENCES followup_task(id) ON DELETE CASCADE,
    action     VARCHAR(30)  NOT NULL
               CHECK (action IN ('CREATE','REMIND','ESCALATE','CLAIM','REASSIGN','COMPLETE','SKIP','CANCEL','EXPIRE','REOPEN')),
    action_by  BIGINT       REFERENCES staff(id),
    action_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    channel    VARCHAR(30),
    detail     JSONB,
    remark     VARCHAR(300)
);
COMMENT ON TABLE followup_task_log IS '任务生命周期流水，只追加不修改；质控与纠纷举证依据';
CREATE INDEX IF NOT EXISTS idx_tasklog_task ON followup_task_log(task_id, action_at DESC);


-- =============================================================================
-- 6. 随访记录与问卷
-- =============================================================================

CREATE TABLE IF NOT EXISTS followup_record (
    id                   BIGSERIAL PRIMARY KEY,
    public_id            UUID        NOT NULL DEFAULT gen_random_uuid(),
    task_id              BIGINT      REFERENCES followup_task(id),
    plan_id              BIGINT      REFERENCES followup_plan(id),
    patient_id           BIGINT      NOT NULL REFERENCES patient(id),
    encounter_id         BIGINT      REFERENCES encounter(id),
    record_type          VARCHAR(30) NOT NULL DEFAULT 'PHONE',
    contacted            BOOLEAN,                              -- 是否接通
    contact_target       VARCHAR(30),                          -- PATIENT/FAMILY
    contact_phone_mask   VARCHAR(20),
    duration_sec         INT,
    symptom_json         JSONB,                                -- 症状勾选
    recovery_level       VARCHAR(20)
                         CHECK (recovery_level IS NULL OR recovery_level IN ('GOOD','MILD','ABNORMAL')),
    medication_adherence VARCHAR(20),
    conclusion           TEXT,                                 -- 回访结论
    advice               TEXT,                                 -- 指导建议
    next_action          VARCHAR(30)
                         CHECK (next_action IS NULL OR next_action IN ('CONTINUE','ADVANCE_VISIT','ESCALATE','CLOSE')),
    is_abnormal          BOOLEAN     NOT NULL DEFAULT FALSE,
    escalated_to         BIGINT      REFERENCES staff(id),
    executed_by          BIGINT      NOT NULL REFERENCES staff(id),
    executed_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMPTZ
);
COMMENT ON TABLE  followup_record            IS '随访执行记录';
COMMENT ON COLUMN followup_record.is_abnormal IS '是否异常；异常记录需立即推送主管医生';
CREATE UNIQUE INDEX IF NOT EXISTS uk_record_public_id ON followup_record(public_id);
CREATE INDEX IF NOT EXISTS idx_record_patient ON followup_record(patient_id, executed_at DESC);
CREATE INDEX IF NOT EXISTS idx_record_task    ON followup_record(task_id);
CREATE INDEX IF NOT EXISTS idx_record_abn     ON followup_record(is_abnormal, executed_at DESC) WHERE is_abnormal = TRUE;


CREATE TABLE IF NOT EXISTS questionnaire (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(50)  NOT NULL UNIQUE,
    name        VARCHAR(150) NOT NULL,
    version     INT          NOT NULL DEFAULT 1,
    description TEXT,
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);


CREATE TABLE IF NOT EXISTS questionnaire_question (
    id               BIGSERIAL PRIMARY KEY,
    questionnaire_id BIGINT       NOT NULL REFERENCES questionnaire(id) ON DELETE CASCADE,
    seq_no           INT          NOT NULL,
    question_type    VARCHAR(20)  NOT NULL
                     CHECK (question_type IN ('SINGLE','MULTI','TEXT','NUMBER','DATE','FILE')),
    title            VARCHAR(300) NOT NULL,
    options          JSONB,
    is_required      BOOLEAN      NOT NULL DEFAULT FALSE,
    min_value        NUMERIC,
    max_value        NUMERIC,
    validate_regex   VARCHAR(200),
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uk_qq_seq ON questionnaire_question(questionnaire_id, seq_no);


CREATE TABLE IF NOT EXISTS questionnaire_answer (
    id               BIGSERIAL PRIMARY KEY,
    questionnaire_id BIGINT      NOT NULL REFERENCES questionnaire(id),
    patient_id       BIGINT      NOT NULL REFERENCES patient(id),
    task_id          BIGINT      REFERENCES followup_task(id),
    answers          JSONB       NOT NULL,
    submitted_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_qa_patient ON questionnaire_answer(patient_id, submitted_at DESC);


-- =============================================================================
-- 7. 病理报告闭环
-- =============================================================================

CREATE TABLE IF NOT EXISTS pathology_report (
    id           BIGSERIAL PRIMARY KEY,
    public_id    UUID         NOT NULL DEFAULT gen_random_uuid(),
    patient_id   BIGINT       NOT NULL REFERENCES patient(id),
    encounter_id BIGINT       NOT NULL REFERENCES encounter(id),
    procedure_id BIGINT       REFERENCES medical_procedure(id),
    report_no    VARCHAR(50),
    specimen_site VARCHAR(200),
    report_date  DATE,
    conclusion   TEXT         NOT NULL,                        -- 病理结论原文
    risk_level   VARCHAR(20)  NOT NULL DEFAULT 'LOW'
                 CHECK (risk_level IN ('LOW','ATTENTION','HIGH')),
    status       VARCHAR(30)  NOT NULL DEFAULT 'DRAFT'
                 CHECK (status IN ('DRAFT','PENDING_REVIEW','PUBLISHED','RETRACTED')),
    version_no   INT          NOT NULL DEFAULT 1,
    is_final     BOOLEAN      NOT NULL DEFAULT TRUE,           -- 是否为最终报告
    entered_by   BIGINT       REFERENCES staff(id),
    entered_at   TIMESTAMPTZ,
    reviewed_by  BIGINT       REFERENCES staff(id),
    reviewed_at  TIMESTAMPTZ,
    published_at TIMESTAMPTZ,
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    deleted_at   TIMESTAMPTZ
);
COMMENT ON TABLE  pathology_report            IS '病理报告（仅文字结论，不上传 PDF）';
COMMENT ON COLUMN pathology_report.risk_level IS 'LOW/ATTENTION/HIGH；HIGH 必须先告知患者才能发布';
COMMENT ON COLUMN pathology_report.status     IS 'DRAFT→PENDING_REVIEW→PUBLISHED';
CREATE UNIQUE INDEX IF NOT EXISTS uk_path_public_id ON pathology_report(public_id);
CREATE INDEX IF NOT EXISTS idx_path_patient ON pathology_report(patient_id, report_date DESC);
CREATE INDEX IF NOT EXISTS idx_path_todo    ON pathology_report(status) WHERE status = 'PENDING_REVIEW';


-- 医生解读：患者看到的第一句话
CREATE TABLE IF NOT EXISTS pathology_interpretation (
    id              BIGSERIAL PRIMARY KEY,
    report_id       BIGINT       NOT NULL REFERENCES pathology_report(id) ON DELETE CASCADE,
    plain_text      TEXT         NOT NULL,                     -- 白话解读，必填
    followup_advice VARCHAR(300),
    recheck_months  INT,
    written_by      BIGINT       NOT NULL REFERENCES staff(id),
    written_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE pathology_interpretation IS '病理报告的患者版解读，由主管医生撰写';
CREATE INDEX IF NOT EXISTS idx_pinterp_report ON pathology_interpretation(report_id);


-- 告知闸门记录：高风险报告必须已告知患者才能发布
CREATE TABLE IF NOT EXISTS pathology_notification (
    id          BIGSERIAL PRIMARY KEY,
    report_id   BIGINT      NOT NULL REFERENCES pathology_report(id) ON DELETE CASCADE,
    notified_by BIGINT      NOT NULL REFERENCES staff(id),
    notified_at TIMESTAMPTZ NOT NULL,
    method      VARCHAR(20) NOT NULL CHECK (method IN ('PHONE','ONSITE','OTHER')),
    target      VARCHAR(20) NOT NULL CHECK (target IN ('PATIENT','FAMILY')),
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE pathology_notification IS '患者告知记录（告知闸门凭证）';
CREATE INDEX IF NOT EXISTS idx_pnotify_report ON pathology_notification(report_id);


-- 纸质报告领取登记
CREATE TABLE IF NOT EXISTS pathology_pickup (
    id            BIGSERIAL PRIMARY KEY,
    report_id     BIGINT      NOT NULL REFERENCES pathology_report(id),
    patient_id    BIGINT      NOT NULL REFERENCES patient(id),
    pickup_code   VARCHAR(20),
    requested_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    status        VARCHAR(20) NOT NULL DEFAULT 'REQUESTED'
                  CHECK (status IN ('REQUESTED','PICKED','EXPIRED','CANCELLED')),
    picked_at     TIMESTAMPTZ,
    picked_by_name VARCHAR(50),
    released_by   BIGINT      REFERENCES staff(id),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE pathology_pickup IS '纸质病理报告来院领取登记';
CREATE INDEX IF NOT EXISTS idx_pickup_status ON pathology_pickup(status, requested_at DESC);


-- 发布闸门：数据库层强制，应用层改不动
CREATE OR REPLACE FUNCTION trg_pathology_publish_gate() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status = 'PUBLISHED' THEN
        IF NEW.reviewed_by IS NULL THEN
            RAISE EXCEPTION '病理报告必须经主管医生审核（reviewed_by）后才能发布';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM pathology_interpretation WHERE report_id = NEW.id) THEN
            RAISE EXCEPTION '病理报告必须填写医生解读（pathology_interpretation）后才能发布';
        END IF;
        IF NEW.risk_level = 'HIGH'
           AND NOT EXISTS (SELECT 1 FROM pathology_notification WHERE report_id = NEW.id) THEN
            RAISE EXCEPTION '高风险病理报告必须先完成患者告知（pathology_notification）才能发布';
        END IF;
        IF NEW.published_at IS NULL THEN
            NEW.published_at := now();
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_pathology_publish_gate ON pathology_report;
CREATE TRIGGER tg_pathology_publish_gate
    BEFORE INSERT OR UPDATE ON pathology_report
    FOR EACH ROW EXECUTE FUNCTION trg_pathology_publish_gate();


-- =============================================================================
-- 8. 消息与通知
-- =============================================================================

CREATE TABLE IF NOT EXISTS notify_channel (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(30)  NOT NULL UNIQUE,
    name        VARCHAR(60)  NOT NULL,
    enabled     BOOLEAN      NOT NULL DEFAULT FALSE,
    config_json JSONB,
    daily_limit INT,
    sort_no     INT          NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE  notify_channel      IS '消息渠道配置';
COMMENT ON COLUMN notify_channel.code IS 'IN_APP/ANDROID_LOCAL/WECHAT_MP_SUBSCRIBE/WECHAT_OA_SUBSCRIBE/WECOM/SMS';


CREATE TABLE IF NOT EXISTS notify_template (
    id                 BIGSERIAL PRIMARY KEY,
    code               VARCHAR(50)  NOT NULL,
    channel_code       VARCHAR(30)  NOT NULL REFERENCES notify_channel(code),
    remote_template_id VARCHAR(100),                           -- 微信模板 ID
    title              VARCHAR(100),
    body_template      TEXT,
    status             VARCHAR(20)  NOT NULL DEFAULT 'DRAFT',
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uk_notify_tpl UNIQUE (code, channel_code)
);


-- 消息日志：按月分区，便于整月 DROP 归档（不 DELETE）
CREATE TABLE IF NOT EXISTS notify_log (
    id            BIGSERIAL,
    task_id       BIGINT      REFERENCES followup_task(id),
    patient_id    BIGINT      REFERENCES patient(id),
    staff_id      BIGINT      REFERENCES staff(id),
    channel_code  VARCHAR(30) NOT NULL,
    template_code VARCHAR(50),
    biz_type      VARCHAR(30),                                 -- TASK_REMIND/TASK_OVERDUE/PATHOLOGY/PICKUP
    title         VARCHAR(200),
    content_masked TEXT,                                       -- 实际发送内容（已脱敏）
    status        VARCHAR(20) NOT NULL DEFAULT 'PENDING'
                  CHECK (status IN ('PENDING','SENT','FAILED','READ')),
    error_msg     VARCHAR(500),
    retry_count   INT         NOT NULL DEFAULT 0,
    sent_at       TIMESTAMPTZ,
    read_at       TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE notify_log IS '消息发送记录；按月分区，保留 12 个月后整月归档';
CREATE INDEX IF NOT EXISTS idx_notifylog_staff ON notify_log(staff_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifylog_task  ON notify_log(task_id);

DO $$
DECLARE
    base_date DATE := DATE '2026-09-01';
    i         INT;
    part_name TEXT;
BEGIN
    FOR i IN 0..35 LOOP
        part_name := 'notify_log_' || to_char(base_date + (i || ' month')::interval, 'YYYYMM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF notify_log FOR VALUES FROM (%L) TO (%L)',
            part_name,
            base_date + (i || ' month')::interval,
            base_date + ((i + 1) || ' month')::interval
        );
    END LOOP;
END $$;


-- 设备与推送 token（安卓本地通知重建用）
CREATE TABLE IF NOT EXISTS user_device (
    id             BIGSERIAL PRIMARY KEY,
    account_id     BIGINT       NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    device_id      VARCHAR(100) NOT NULL,
    platform       VARCHAR(20)  NOT NULL CHECK (platform IN ('ANDROID','IOS','H5','MP')),
    push_token     VARCHAR(300),
    app_version    VARCHAR(30),
    last_active_at TIMESTAMPTZ,
    status         SMALLINT     NOT NULL DEFAULT 1,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uk_user_device UNIQUE (account_id, device_id)
);


-- 小程序订阅消息额度（一次性订阅的补充机制）
CREATE TABLE IF NOT EXISTS mp_subscribe_quota (
    id            BIGSERIAL PRIMARY KEY,
    account_id    BIGINT      NOT NULL REFERENCES account(id) ON DELETE CASCADE,
    template_code VARCHAR(50) NOT NULL,
    total_granted INT         NOT NULL DEFAULT 0,
    total_used    INT         NOT NULL DEFAULT 0,
    last_grant_at TIMESTAMPTZ,
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT uk_mp_quota UNIQUE (account_id, template_code)
);
COMMENT ON TABLE mp_subscribe_quota IS '小程序订阅消息额度；长期订阅未获批时使用';


-- 提醒策略（可配置，按科室或模板覆盖）
CREATE TABLE IF NOT EXISTS reminder_rule (
    id                     BIGSERIAL PRIMARY KEY,
    dept_id                BIGINT      REFERENCES department(id),
    scope                  VARCHAR(20) NOT NULL DEFAULT 'DEPT'
                           CHECK (scope IN ('GLOBAL','DEPT','TEMPLATE')),
    scope_id               BIGINT,
    name                   VARCHAR(100) NOT NULL,
    advance_notify_days    INT         NOT NULL DEFAULT 1,      -- T-1 预告
    advance_notify_time    TIME        NOT NULL DEFAULT '18:00',
    day_start_time         TIME        NOT NULL DEFAULT '08:00',
    interval_hours         INT         NOT NULL DEFAULT 2,      -- 当天每 2 小时催办
    day_end_time           TIME        NOT NULL DEFAULT '18:00',
    quiet_start            TIME        NOT NULL DEFAULT '22:00',-- 夜间免打扰
    quiet_end              TIME        NOT NULL DEFAULT '07:00',
    overdue_day_times      INT         NOT NULL DEFAULT 3,
    overdue_week_times     INT         NOT NULL DEFAULT 1,
    stop_after_days        INT         NOT NULL DEFAULT 14,
    escalate_to_manager    BOOLEAN     NOT NULL DEFAULT FALSE,  -- 默认不打扰护士长
    escalate_after_hours   INT,
    status                 SMALLINT    NOT NULL DEFAULT 1,
    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);
COMMENT ON TABLE reminder_rule IS '提醒与催办策略；默认夜间免打扰、逾期降频';


-- =============================================================================
-- 9. Excel 导入
-- =============================================================================

CREATE TABLE IF NOT EXISTS import_batch (
    id            BIGSERIAL PRIMARY KEY,
    public_id     UUID         NOT NULL DEFAULT gen_random_uuid(),
    dept_id       BIGINT       NOT NULL REFERENCES department(id),
    biz_type      VARCHAR(30)  NOT NULL DEFAULT 'PATIENT_ENCOUNTER',
    file_name     VARCHAR(300),
    file_hash     VARCHAR(64),
    total_rows    INT          NOT NULL DEFAULT 0,
    success_rows  INT          NOT NULL DEFAULT 0,
    update_rows   INT          NOT NULL DEFAULT 0,
    fail_rows     INT          NOT NULL DEFAULT 0,
    status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING'
                  CHECK (status IN ('PENDING','VALIDATED','IMPORTING','SUCCESS','FAILED','ROLLED_BACK')),
    error_summary TEXT,
    imported_by   BIGINT       NOT NULL REFERENCES staff(id),
    started_at    TIMESTAMPTZ,
    finished_at   TIMESTAMPTZ,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now()
);
COMMENT ON TABLE import_batch IS '导入批次；全部成功或全部回滚';
CREATE UNIQUE INDEX IF NOT EXISTS uk_import_public_id ON import_batch(public_id);


CREATE TABLE IF NOT EXISTS import_row_error (
    id          BIGSERIAL PRIMARY KEY,
    batch_id    BIGINT       NOT NULL REFERENCES import_batch(id) ON DELETE CASCADE,
    row_no      INT          NOT NULL,
    column_name VARCHAR(50),
    raw_value   TEXT,
    error_code  VARCHAR(50),
    error_msg   VARCHAR(500),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_importerr_batch ON import_row_error(batch_id, row_no);


-- =============================================================================
-- 10. 系统与审计
-- =============================================================================

CREATE TABLE IF NOT EXISTS sys_config (
    id           BIGSERIAL PRIMARY KEY,
    config_key   VARCHAR(100) NOT NULL UNIQUE,
    config_value TEXT,
    value_type   VARCHAR(20)  NOT NULL DEFAULT 'STRING',
    description  VARCHAR(300),
    is_editable  BOOLEAN      NOT NULL DEFAULT TRUE,
    updated_by   BIGINT       REFERENCES staff(id),
    created_at   TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at   TIMESTAMPTZ  NOT NULL DEFAULT now()
);


CREATE TABLE IF NOT EXISTS dictionary (
    id          BIGSERIAL PRIMARY KEY,
    dict_code   VARCHAR(50)  NOT NULL UNIQUE,
    dict_name   VARCHAR(80)  NOT NULL,
    description VARCHAR(200),
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);


CREATE TABLE IF NOT EXISTS dictionary_item (
    id         BIGSERIAL PRIMARY KEY,
    dict_code  VARCHAR(50)  NOT NULL REFERENCES dictionary(dict_code) ON DELETE CASCADE,
    item_value VARCHAR(50)  NOT NULL,
    item_label VARCHAR(100) NOT NULL,
    sort_no    INT          NOT NULL DEFAULT 0,
    is_default BOOLEAN      NOT NULL DEFAULT FALSE,
    status     SMALLINT     NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uk_dict_item UNIQUE (dict_code, item_value)
);


-- 审计日志：只追加，按月分区
CREATE TABLE IF NOT EXISTS audit_log (
    id            BIGSERIAL,
    account_id    BIGINT,
    staff_id      BIGINT,
    patient_id    BIGINT,
    action        VARCHAR(50)  NOT NULL,                       -- VIEW_PHONE/EXPORT/DOWNLOAD/PUBLISH_REPORT/...
    resource_type VARCHAR(50),
    resource_id   VARCHAR(64),
    field_name    VARCHAR(50),
    before_value  TEXT,
    after_value   TEXT,
    ip            VARCHAR(45),
    user_agent    VARCHAR(300),
    result        VARCHAR(20)  NOT NULL DEFAULT 'SUCCESS',
    detail        JSONB,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);
COMMENT ON TABLE audit_log IS '审计日志，只追加不修改；敏感字段查看必须留痕';
CREATE INDEX IF NOT EXISTS idx_audit_staff   ON audit_log(staff_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_patient ON audit_log(patient_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action  ON audit_log(action, created_at DESC);

DO $$
DECLARE
    base_date DATE := DATE '2026-09-01';
    i         INT;
    part_name TEXT;
BEGIN
    FOR i IN 0..47 LOOP
        part_name := 'audit_log_' || to_char(base_date + (i || ' month')::interval, 'YYYYMM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF audit_log FOR VALUES FROM (%L) TO (%L)',
            part_name,
            base_date + (i || ' month')::interval,
            base_date + ((i + 1) || ' month')::interval
        );
    END LOOP;
END $$;


CREATE TABLE IF NOT EXISTS login_log (
    id                 BIGSERIAL PRIMARY KEY,
    account_id         BIGINT,
    login_name_masked  VARCHAR(100),
    account_type       VARCHAR(20),
    login_type         VARCHAR(20),                            -- PASSWORD/SMS/WECHAT
    success            BOOLEAN      NOT NULL,
    fail_reason        VARCHAR(200),
    ip                 VARCHAR(45),
    user_agent         VARCHAR(300),
    created_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_loginlog_name ON login_log(login_name_masked, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_loginlog_ip   ON login_log(ip, created_at DESC);


-- =============================================================================
-- 11. updated_at 自动维护
-- =============================================================================

DO $$
DECLARE
    t TEXT;
    tables TEXT[] := ARRAY[
        'department','staff','care_team','staff_absence','account','role',
        'patient','patient_contact','encounter','medical_procedure','patient_care_team',
        'followup_template','followup_template_item','followup_plan','followup_task',
        'followup_record','pathology_report','pathology_interpretation','pathology_pickup',
        'notify_channel','notify_template','user_device','reminder_rule',
        'import_batch','sys_config','dictionary','dictionary_item'
    ];
BEGIN
    FOREACH t IN ARRAY tables LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS tg_%s_updated ON %I', t, t);
        EXECUTE format(
            'CREATE TRIGGER tg_%s_updated BEFORE UPDATE ON %I
             FOR EACH ROW EXECUTE FUNCTION set_updated_at()', t, t);
    END LOOP;
END $$;


-- =============================================================================
-- 12. 行级安全（第二道防线）
--     应用连接必须使用 app_rw（非表属主），否则 RLS 不生效。
--     会话变量：app.current_staff_id / app.is_manager / app.is_system
-- =============================================================================

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_rw') THEN
        -- 部署时务必修改密码
        CREATE ROLE app_rw LOGIN PASSWORD 'CHANGE_ME_ON_DEPLOY';
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO app_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES    IN SCHEMA public TO app_rw;
GRANT USAGE, SELECT                  ON ALL SEQUENCES IN SCHEMA public TO app_rw;

ALTER TABLE followup_task       ENABLE ROW LEVEL SECURITY;
ALTER TABLE followup_task       FORCE  ROW LEVEL SECURITY;
ALTER TABLE followup_record     ENABLE ROW LEVEL SECURITY;
ALTER TABLE followup_record     FORCE  ROW LEVEL SECURITY;
ALTER TABLE patient             ENABLE ROW LEVEL SECURITY;
ALTER TABLE patient             FORCE  ROW LEVEL SECURITY;
ALTER TABLE pathology_report    ENABLE ROW LEVEL SECURITY;
ALTER TABLE pathology_report    FORCE  ROW LEVEL SECURITY;

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
    );

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
    );

DROP POLICY IF EXISTS p_patient_access ON patient;
CREATE POLICY p_patient_access ON patient
    USING (
        current_setting('app.is_system', true)  = 'true'
        OR current_setting('app.is_manager', true) = 'true'
        OR current_setting('app.is_patient_portal', true) = 'true'
        OR id IN (
            SELECT pct.patient_id FROM patient_care_team pct
            JOIN care_team_member ctm ON ctm.team_id = pct.team_id
            WHERE ctm.staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
              AND pct.status = 'ACTIVE'
        )
    );

DROP POLICY IF EXISTS p_pathology_access ON pathology_report;
CREATE POLICY p_pathology_access ON pathology_report
    USING (
        current_setting('app.is_system', true)  = 'true'
        OR current_setting('app.is_manager', true) = 'true'
        OR patient_id IN (
            SELECT pct.patient_id FROM patient_care_team pct
            JOIN care_team_member ctm ON ctm.team_id = pct.team_id
            WHERE ctm.staff_id = nullif(current_setting('app.current_staff_id', true), '')::bigint
              AND pct.status = 'ACTIVE'
        )
        -- 患者端只能看到已发布的报告
        OR (current_setting('app.is_patient_portal', true) = 'true'
            AND status = 'PUBLISHED'
            AND patient_id = nullif(current_setting('app.current_patient_id', true), '')::bigint)
    );


-- =============================================================================
-- 13. 初始化数据
-- =============================================================================

INSERT INTO department (code, name, sort_no)
VALUES ('XHNK', '消化内科', 1)
ON CONFLICT DO NOTHING;

INSERT INTO role (code, name, description, is_system) VALUES
    ('SUPER_ADMIN',       '系统管理员',     '账号、权限、字典、备份；默认不可见患者明细', TRUE),
    ('DEPT_MANAGER',      '科室管理者',     '护士长/主任：本科室全部数据、任务分配与质控', TRUE),
    ('DOCTOR',            '主管医生',       '本人主管患者、制定与调整随访计划、审核病理报告', TRUE),
    ('NURSE',             '主管护士',       '本人主管患者、执行电话随访、代录记录', TRUE),
    ('FOLLOWUP_OFFICER',  '随访专员',       '仅执行电话随访，不可查看完整病历', TRUE),
    ('AUDITOR',           '审计员',         '只读操作日志', TRUE)
ON CONFLICT (code) DO NOTHING;

INSERT INTO permission (code, name, module) VALUES
    ('patient:read',        '查看患者',           'patient'),
    ('patient:write',       '新增/编辑患者',       'patient'),
    ('patient:phone:view',  '查看完整手机号',      'patient'),
    ('encounter:read',      '查看就诊记录',        'encounter'),
    ('encounter:write',     '编辑就诊记录',        'encounter'),
    ('encounter:import',    '批量导入',            'encounter'),
    ('task:read',           '查看随访任务',        'followup'),
    ('task:execute',        '执行随访任务',        'followup'),
    ('task:assign',         '分配/改派任务',       'followup'),
    ('plan:write',          '制定随访计划',        'followup'),
    ('template:write',      '维护随访模板',        'template'),
    ('template:approve',    '审核随访模板',        'template'),
    ('pathology:enter',     '录入病理报告',        'pathology'),
    ('pathology:review',    '审核病理报告',        'pathology'),
    ('pathology:publish',   '发布病理报告给患者',  'pathology'),
    ('audit:read',          '查看审计日志',        'system'),
    ('staff:manage',        '管理医护账号',        'system'),
    ('config:write',        '修改系统配置',        'system')
ON CONFLICT (code) DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r CROSS JOIN permission p
WHERE r.code = 'SUPER_ADMIN'
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p ON p.code IN (
    'patient:read','patient:write','patient:phone:view','encounter:read','encounter:write',
    'encounter:import','task:read','task:execute','task:assign','plan:write',
    'template:write','template:approve','pathology:enter','pathology:review',
    'pathology:publish','audit:read'
)
WHERE r.code = 'DEPT_MANAGER'
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p ON p.code IN (
    'patient:read','patient:phone:view','encounter:read','task:read','task:execute',
    'plan:write','pathology:enter','pathology:review','pathology:publish'
)
WHERE r.code = 'DOCTOR'
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p ON p.code IN (
    'patient:read','patient:phone:view','encounter:read','task:read','task:execute',
    'pathology:enter'
)
WHERE r.code = 'NURSE'
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p ON p.code IN ('task:read','task:execute')
WHERE r.code = 'FOLLOWUP_OFFICER'
ON CONFLICT DO NOTHING;

INSERT INTO role_permission (role_id, permission_id)
SELECT r.id, p.id FROM role r JOIN permission p ON p.code IN ('audit:read')
WHERE r.code = 'AUDITOR'
ON CONFLICT DO NOTHING;

INSERT INTO dictionary (dict_code, dict_name, description) VALUES
    ('gender',            '性别',           '1男 2女'),
    ('discharge_type',    '离院方式',       '医嘱离院/转院/转科/死亡/其他'),
    ('risk_level',        '病理风险分级',   'LOW低 ATTENTION需关注 HIGH高'),
    ('recovery_level',    '恢复情况',       'GOOD良好 MILD轻度不适 ABNORMAL明显异常'),
    ('contact_relation',  '联系人关系',     '本人/配偶/父亲/母亲/儿子/女儿/其他'),
    ('task_status',       '任务状态',       'PENDING/DOING/DONE/SKIPPED/CANCELLED/EXPIRED'),
    ('symptom',           '随访症状选项',   '腹痛/便血/呕血/黑便/发热/黄疸/恶心呕吐/无明显症状')
ON CONFLICT (dict_code) DO NOTHING;

INSERT INTO dictionary_item (dict_code, item_value, item_label, sort_no, is_default) VALUES
    ('gender','1','男',1,TRUE),  ('gender','2','女',2,FALSE),
    ('discharge_type','1','医嘱离院',1,TRUE),
    ('discharge_type','2','转院',2,FALSE),
    ('discharge_type','3','转科',3,FALSE),
    ('discharge_type','4','死亡',4,FALSE),
    ('discharge_type','9','其他',9,FALSE),
    ('risk_level','LOW','低风险',1,TRUE),
    ('risk_level','ATTENTION','需关注',2,FALSE),
    ('risk_level','HIGH','高风险',3,FALSE),
    ('recovery_level','GOOD','恢复良好',1,TRUE),
    ('recovery_level','MILD','轻度不适',2,FALSE),
    ('recovery_level','ABNORMAL','明显异常',3,FALSE),
    ('contact_relation','SELF','本人',1,TRUE),
    ('contact_relation','SPOUSE','配偶',2,FALSE),
    ('contact_relation','SON','儿子',3,FALSE),
    ('contact_relation','DAUGHTER','女儿',4,FALSE),
    ('contact_relation','PARENT','父母',5,FALSE),
    ('contact_relation','OTHER','其他',9,FALSE)
ON CONFLICT (dict_code, item_value) DO NOTHING;

INSERT INTO notify_channel (code, name, enabled, daily_limit, sort_no, config_json) VALUES
    ('IN_APP','App内待办列表',        TRUE,  NULL, 1, '{"note":"权威数据源，不可关闭"}'),
    ('ANDROID_LOCAL','安卓本地定时通知', TRUE,  NULL, 2, '{"note":"系统级定时器，离线可用"}'),
    ('WECHAT_MP_SUBSCRIBE','小程序订阅消息', FALSE, NULL, 3, '{"note":"需小程序审核通过后启用"}'),
    ('WECHAT_OA_SUBSCRIBE','服务号订阅通知', FALSE, NULL, 4, '{"note":"医院有服务号，待配置"}'),
    ('WECOM','企业微信',              FALSE, NULL, 5, '{"note":"第二阶段接入"}'),
    ('SMS','短信',                    FALSE, 200,  6, '{"note":"仅逾期升级时发送"}')
ON CONFLICT (code) DO NOTHING;

INSERT INTO reminder_rule (scope, name, advance_notify_days, advance_notify_time,
                           day_start_time, interval_hours, day_end_time,
                           quiet_start, quiet_end, overdue_day_times, overdue_week_times,
                           stop_after_days, escalate_to_manager)
VALUES ('GLOBAL','全局默认提醒策略', 1, '18:00', '08:00', 2, '18:00',
        '22:00', '07:00', 3, 1, 14, FALSE)
ON CONFLICT DO NOTHING;

INSERT INTO sys_config (config_key, config_value, value_type, description) VALUES
    ('notify.mask_patient_name',      'true',  'BOOLEAN', '通知栏是否隐藏患者姓名'),
    ('notify.mask_phone',             'true',  'BOOLEAN', '通知内容是否隐藏手机号'),
    ('security.phone_view_reauth',    'true',  'BOOLEAN', '查看完整手机号是否需二次验证'),
    ('security.session_timeout_min',  '30',    'INT',     '会话超时（分钟）'),
    ('security.password_min_length',  '10',    'INT',     '密码最小长度'),
    ('security.login_max_fail',       '5',     'INT',     '连续登录失败锁定阈值'),
    ('followup.anchor_priority',      'SURGERY,DISCHARGE', 'STRING', '随访时间锚点优先级'),
    ('retention.notify_log_months',   '12',    'INT',     '消息日志保留月数'),
    ('retention.audit_log_months',    '36',    'INT',     '审计日志保留月数'),
    ('backup.daily_time',             '02:00', 'STRING',  '每日备份时间')
ON CONFLICT (config_key) DO NOTHING;

-- =============================================================================
-- 完成
-- =============================================================================

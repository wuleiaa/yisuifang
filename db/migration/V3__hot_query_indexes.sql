-- =============================================================================
--  V3：压测发现的索引补充
--
--  背景：把数据量从 3 位患者抬到 1000 位患者 / 6010 个任务后复测，
--  "待办列表"P95 从 35ms 变成 214ms。执行计划显示：
--    followup_task 只用到了 idx_task_assignee(assignee_staff_id)，
--    再回表逐行过滤 status / due_date，最后排序取前 100 条。
--  也就是说"把某个医生名下所有任务全部取回再排序"，数据量一大就不划算。
--
--  本迁移加三个索引，都是直接对着执行计划里的过滤与排序条件建的。
--  索引不是越多越好——每加一个都会拖慢写入，所以只加这三个高频路径上的。
-- =============================================================================

-- 1. 待办列表的主路径：按人 + 状态过滤，按应完成日期排序
CREATE INDEX IF NOT EXISTS idx_task_assignee_status_due
    ON followup_task (assignee_staff_id, status, due_date)
    WHERE deleted_at IS NULL;

-- 2. 患者详情 / 患者列表里的"这人还有几条待办"
CREATE INDEX IF NOT EXISTS idx_task_patient_status_due
    ON followup_task (patient_id, status, due_date)
    WHERE deleted_at IS NULL;

-- 3. 待办卡片上"最近一次手术"的取值（LATERAL 子查询每行查一次）
CREATE INDEX IF NOT EXISTS idx_proc_encounter_primary_date
    ON medical_procedure (encounter_id, is_primary DESC, procedure_date DESC)
    WHERE deleted_at IS NULL;

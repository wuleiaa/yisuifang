-- =============================================================================
--  pgbench 并发压力测试脚本
--
--  模拟医护人员真实使用时的混合读负载：
--    Q1  打开 App → 拉取待办列表（最高频）
--    Q2  点开患者 → 拉取该患者的随访任务
--    Q3  患者管理 → 姓名模糊搜索
--    Q4  解锁手机 → 查询今日待办数量
--
--  用法：
--    pgbench -h 127.0.0.1 -p 55432 -U postgres -d followup_perf \
--            -c 20 -j 4 -T 60 -f tools/perf_bench.sql
-- =============================================================================

\set pidx   random(1, 100000)
\set days   random(0, 800)
\set today  random(700, 800)

-- Q1 待办列表（按应完成时间，取前 50 条）
SELECT t.id, t.title, t.due_date, t.status
FROM followup_task t
WHERE t.status IN ('PENDING','DOING')
  AND t.due_date <= (DATE '2024-01-01' + :days)
ORDER BY t.due_date
LIMIT 50;

-- Q2 患者详情：该患者的全部随访任务
SELECT t.id, t.title, t.due_date, t.status
FROM followup_task t
WHERE t.patient_id = :pidx
ORDER BY t.due_date DESC
LIMIT 20;

-- Q3 姓名模糊搜索
SELECT id, name, phone_mask
FROM patient
WHERE name LIKE '%张%'
LIMIT 20;

-- Q4 今日待办数量（首页角标）
SELECT count(*)
FROM followup_task
WHERE status = 'PENDING'
  AND due_date <= (DATE '2024-01-01' + :today);

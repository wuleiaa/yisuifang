-- 单查询压测：首页角标「今日待办数量」（聚合查询，无 LIMIT）
\set today random(700, 800)

SELECT count(*)
FROM followup_task
WHERE status = 'PENDING'
  AND due_date <= (DATE '2024-01-01' + :today);

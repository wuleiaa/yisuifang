-- 单查询压测：只跑「待办列表」（最高频、且走了索引的查询）
\set days random(0, 800)

SELECT t.id, t.title, t.due_date, t.status
FROM followup_task t
WHERE t.status IN ('PENDING','DOING')
  AND t.due_date <= (DATE '2024-01-01' + :days)
ORDER BY t.due_date
LIMIT 50;

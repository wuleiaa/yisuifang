-- 定位姓名搜索瓶颈：对比不同关键词的查询计划
\echo '--- A. LIKE 前缀匹配（可走索引）---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name FROM patient WHERE name LIKE '张%' LIMIT 20;

\echo '--- B. LIKE 包含匹配（低选择性，必然全表扫描）---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name FROM patient WHERE name LIKE '%张%' LIMIT 20;

\echo '--- C. 前缀 + 高选择性（模拟真实检索）---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name FROM patient WHERE name LIKE '张伟%' LIMIT 20;

\echo '--- D. 加科室过滤后（系统实际会带的条件）---'
EXPLAIN (ANALYZE, COSTS OFF, TIMING OFF, SUMMARY ON)
SELECT id, name FROM patient
WHERE dept_id = (SELECT id FROM department WHERE code = 'XHNK')
  AND name LIKE '%张%'
LIMIT 20;

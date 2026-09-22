-- ============================================================
-- 模块 4：同期群留存分析（产品运营/数据运营面试必考）
-- 知识点：CTE、自关联思路（首购月份 × 活跃月份）、日期月份差计算
-- 面试考点：
--   ① 留存率定义：某月新客中，第 N 个月后仍活跃（有下单）的比例
--   ② 同期群 Cohort = 按「首次购买月份」把用户分组，观察每组随时间的留存
--      避免「把老用户和新用户混在一起看留存」的失真
--   ③ 留存曲线普遍前陡后缓：第 0→1 月掉得最狠，之后趋于平稳
--   ④ 🔴 用户 ID 口径：必须用 customer_unique_id（用户级），
--      用 customer_id（订单级）会算成留存率 100%，错误结论
-- ============================================================

-- 查询 5-1：每月新增客户数（同期群规模，按用户级 ID 统计）
SELECT
    strftime('%Y-%m', first_purchase_time) AS 首购月份,
    COUNT(*) AS 新客数
FROM (
    SELECT c.customer_unique_id, MIN(o.order_purchase_timestamp) AS first_purchase_time
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
GROUP BY 首购月份
ORDER BY 首购月份;

-- 查询 5-2：同期群留存明细（cohort × 第N月 → 留存率）
-- 逻辑拆解：
--   ① first_purchase：每个用户的首次购买年/月（同期群分组依据）
--   ② user_month：每个用户有哪些月份下过单（活跃月份）
--   ③ 两张表 JOIN 后，用月份差公式算出「这是该用户的第几个月」：
--      第N月 = (活跃年 - 首购年) * 12 + (活跃月 - 首购月)
--   ④ 留存率 = 第 N 月活跃人数 / 该同期群新客数
-- 面试考点：
--   ① 月份差公式是笔试常见写法；MySQL 里可用 TIMESTAMPDIFF(MONTH, ...)
--   ② 🔴 strftime 只认 'YYYY-MM-DD' 等完整时间格式，不认 'YYYY-MM' 字符串！
--      所以先把年、月提取成整数，再做算术（本查询的做法）
WITH first_purchase AS (
    SELECT
        c.customer_unique_id AS customer_id,
        strftime('%Y-%m', MIN(o.order_purchase_timestamp)) AS 首购月份,  -- 展示用
        CAST(strftime('%Y', MIN(o.order_purchase_timestamp)) AS INTEGER) AS 首购年,
        CAST(strftime('%m', MIN(o.order_purchase_timestamp)) AS INTEGER) AS 首购月
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
user_month AS (
    SELECT DISTINCT
        c.customer_unique_id AS customer_id,
        CAST(strftime('%Y', o.order_purchase_timestamp) AS INTEGER) AS 活跃年,
        CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) AS 活跃月
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_size AS (
    SELECT 首购月份, COUNT(*) AS 新客数
    FROM first_purchase
    GROUP BY 首购月份
)
SELECT
    fp.首购月份,
    (um.活跃年 - fp.首购年) * 12 + (um.活跃月 - fp.首购月) AS 第N月,
    COUNT(DISTINCT um.customer_id) AS 活跃人数,
    ROUND(100.0 * COUNT(DISTINCT um.customer_id) / cs.新客数, 1) AS 留存率百分比
FROM first_purchase fp
JOIN user_month um ON um.customer_id = fp.customer_id
JOIN cohort_size cs ON cs.首购月份 = fp.首购月份
WHERE fp.首购月份 >= '2017-01'   -- 只看 2017 年后的同期群，数据完整
  AND (um.活跃年 - fp.首购年) * 12 + (um.活跃月 - fp.首购月) BETWEEN 0 AND 12
GROUP BY fp.首购月份, 第N月
ORDER BY fp.首购月份, 第N月;

-- 查询 5-3：整体复购率（辅助指标）
-- 复购率 = 购买 ≥ 2 次的用户 / 总下单用户
-- 面试考点：复购率和留存率的区别——
--   留存率看「人在不在」，复购率看「有没有再次花钱」，一个是过程指标一个是结果指标
SELECT
    COUNT(*)                       AS 下单用户总数,
    SUM(CASE WHEN 购买次数 >= 2 THEN 1 ELSE 0 END) AS 复购用户数,
    ROUND(100.0 * SUM(CASE WHEN 购买次数 >= 2 THEN 1 ELSE 0 END) / COUNT(*), 1)
                                   AS 复购率百分比
FROM (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS 购买次数
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
);

-- ============================================================
-- 模块 5：地域销售分析（销售运营/商业分析常见分析维度）
-- 知识点：多维度 GROUP BY、HAVING、子查询复用
-- 面试考点：
--   ① 分析维度：地域 × 时间 × 品类 × 用户，是商业分析的四件套
--   ② 巴西电商集中在东南部（SP 圣保罗州占一半左右），
--      头部城市贡献大部分 GMV —— 这是典型的长尾分布
--   ③ 客单价高 ≠ 贡献大，还要看订单量（规模 × 效率两个维度一起看）
-- ============================================================

-- 查询 6-1：各州销售排名（全部 27 个州）
SELECT
    c.customer_state             AS 州,
    COUNT(DISTINCT o.order_id)   AS 订单数,
    ROUND(SUM(oi.price), 2)      AS GMV
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
JOIN olist_order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY GMV DESC;

-- 查询 6-2：城市 TOP 15（按 GMV）
SELECT
    c.customer_city              AS 城市,
    c.customer_state             AS 州,
    COUNT(DISTINCT o.order_id)   AS 订单数,
    ROUND(SUM(oi.price), 2)      AS GMV,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS 客单价
FROM olist_orders o
JOIN olist_customers c ON o.customer_id = c.customer_id
JOIN olist_order_items oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_city, c.customer_state
ORDER BY GMV DESC
LIMIT 15;

-- 查询 6-3：头部城市 vs 长尾城市（帕累托视角）
-- 面试考点：订单量 < 100 的城市有几百个，贡献却微乎其微 ——
-- 市场扩张时优先打头部，而不是平均用力
SELECT
    CASE
        WHEN 订单数 >= 1000 THEN 'A级 大市场（≥1000单）'
        WHEN 订单数 >= 100  THEN 'B级 中市场（100~999单）'
        ELSE 'C级 长尾市场（<100单）'
    END AS 城市分级,
    COUNT(*)                    AS 城市数,
    ROUND(SUM(GMV), 2)          AS GMV合计,
    ROUND(100.0 * SUM(GMV) / SUM(SUM(GMV)) OVER (), 2) AS GMV占比百分比
FROM (
    SELECT
        c.customer_city AS 城市,
        COUNT(DISTINCT o.order_id) AS 订单数,
        SUM(oi.price)             AS GMV
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_city
)
GROUP BY 城市分级
ORDER BY GMV合计 DESC;

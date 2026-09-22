-- ============================================================
-- 模块 2：品类分析（品类运营/电商运营面试核心）
-- 知识点：多表 JOIN（4 张表串联）、窗口函数 SUM() OVER、LIMIT、LEFT JOIN
-- 面试考点：
--   ① 三表以上 JOIN 的关联链条怎么走（items → products → translation → orders）
--   ② 帕累托法则：Top 品类贡献多少 GMV（二八定律在电商的体现）
--   ③ LEFT JOIN 和 JOIN 的区别（哪些类目没翻译？）
-- ============================================================

-- 查询 3-1：品类 GMV 排名 TOP 10
-- 关联链条：明细表(金额) → 商品表(类目) → 翻译表(英文名)，再回订单表过滤状态
SELECT
    t.product_category_name_english AS 品类,
    COUNT(DISTINCT oi.order_id)      AS 订单数,
    ROUND(SUM(oi.price), 2)          AS GMV
FROM olist_order_items oi
JOIN olist_products p
    ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
JOIN olist_orders o
    ON o.order_id = oi.order_id AND o.order_status = 'delivered'
GROUP BY t.product_category_name_english
ORDER BY GMV DESC
LIMIT 10;

-- 查询 3-2：帕累托分析 —— Top N 品类累计贡献占比
-- 面试考点：窗口函数 SUM(GMV) OVER (ORDER BY GMV DESC) 是「滚动累计求和」，
-- 结果里找第一个累计占比超过 80% 的行，前面那些品类就是头部品类
SELECT 品类, GMV, 累计GMV占比
FROM (
    SELECT
        t.product_category_name_english AS 品类,
        ROUND(SUM(oi.price), 2)         AS GMV,
        ROUND(100.0 * SUM(SUM(oi.price)) OVER (ORDER BY SUM(oi.price) DESC)
              / SUM(SUM(oi.price)) OVER (), 2) AS 累计GMV占比
    FROM olist_order_items oi
    JOIN olist_products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    JOIN olist_orders o
        ON o.order_id = oi.order_id AND o.order_status = 'delivered'
    GROUP BY t.product_category_name_english
)
LIMIT 15;

-- 查询 3-3：头部品类的件单价和客单价
-- 件单价 = GMV / 销售件数；客单价 = GMV / 订单数
-- 面试考点：件单价高的品类（如家居）和件单价低的品类（如食品）运营策略完全不同
SELECT
    t.product_category_name_english AS 品类,
    ROUND(SUM(oi.price) / COUNT(*), 2)                    AS 件单价,
    ROUND(SUM(oi.price) / COUNT(DISTINCT oi.order_id), 2) AS 客单价
FROM olist_order_items oi
JOIN olist_products p ON oi.product_id = p.product_id
LEFT JOIN product_category_name_translation t
    ON p.product_category_name = t.product_category_name
JOIN olist_orders o
    ON o.order_id = oi.order_id AND o.order_status = 'delivered'
GROUP BY t.product_category_name_english
HAVING COUNT(DISTINCT oi.order_id) > 1000   -- 只看有一定规模的品类，避免小样本干扰
ORDER BY 件单价 DESC
LIMIT 10;

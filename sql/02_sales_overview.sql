-- ============================================================
-- 模块 1：销售概览（GMV、订单量、客单价、月度趋势）
-- 知识点：聚合函数 COUNT/SUM、GROUP BY、日期函数 strftime、
--         子查询、JOIN、数据口径意识
-- 面试考点：
--   ① GMV 公式：GMV = 销售额合计（本表 = SUM(price)）
--   ② 客单价 AOV = GMV / 订单数
--   ③ 为什么只统计 delivered 订单（口径问题，见查询 2-3）
-- ============================================================

-- 查询 2-1：整体销售概况（口径：仅 delivered 订单）
-- 一个订单里有多个商品行（order_items 一行一件），所以要先按订单
-- 汇总出每笔订单的金额，再整体聚合 —— 这就是子查询的典型用法
SELECT
    COUNT(*)                             AS 订单数,
    COUNT(DISTINCT customer_id)          AS 下单用户数,
    ROUND(SUM(gmv_price), 2)             AS GMV_不含运费,
    ROUND(SUM(gmv_price + gmv_freight), 2) AS GMV_含运费,
    ROUND(SUM(gmv_price) / COUNT(*), 2)  AS 客单价AOV
FROM (
    SELECT
        o.order_id,
        o.customer_id,
        SUM(oi.price)          AS gmv_price,   -- 商品金额
        SUM(oi.freight_value)  AS gmv_freight  -- 运费金额
    FROM olist_orders o
    JOIN olist_order_items oi ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY o.order_id, o.customer_id
);

-- 查询 2-2：订单状态分布 —— 看看取消/未成交的订单占比多少
-- 面试考点：canceled 约 0.6%、unavailable 约 0.6%，不算它们 GMV 虚高 1%+
-- 分析师第一件事永远是确认"口径"
SELECT
    order_status    AS 订单状态,
    COUNT(*)        AS 订单数,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS 占比百分比
FROM olist_orders
GROUP BY order_status
ORDER BY 订单数 DESC;

-- 查询 2-3：月度 GMV 趋势 —— strftime 把时间戳截到月，再分组
-- 面试考点：strftime('%Y-%m', 时间列) 是 SQLite 写法；
--           MySQL 等价写法是 DATE_FORMAT(时间列, '%Y-%m')
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS 月份,
    COUNT(DISTINCT o.order_id)                    AS 订单数,
    ROUND(SUM(oi.price), 2)                       AS GMV
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY 月份
ORDER BY 月份;

-- 查询 2-4：月度客单价趋势 —— 客单价 = 当月 GMV / 当月订单数
-- 面试考点：客单价下降可能意味着什么？（促销拉新、低价商品占比升高、
--          组合购买变少 —— 需要拆解到品类/新老用户验证）
SELECT
    strftime('%Y-%m', o.order_purchase_timestamp) AS 月份,
    ROUND(SUM(oi.price) / COUNT(DISTINCT o.order_id), 2) AS 客单价AOV
FROM olist_orders o
JOIN olist_order_items oi ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY 月份
ORDER BY 月份;

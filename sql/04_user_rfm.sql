-- ============================================================
-- 模块 3：RFM 用户分层（运营岗面试必考）
-- 知识点：CTE 公共表表达式 WITH、NTILE 分位分组、CASE WHEN 多分支、julianday 日期差
-- 面试考点：
--   ① RFM 三个字母：R=Recency 最近一次消费距今天数（越小越好）
--                   F=Frequency 消费次数（越大越好）
--                   M=Monetary 消费金额（越大越好）
--   ② 为什么要分层：资源有限，运营要对不同价值用户用不同策略
--      （重要价值→重点维护；重要挽留→发券召回；一般挽留→低成本触达或放弃）
--   ③ 分层方法：按中位数/均值/三分位切，本模块用 NTILE(2) 中位切分
--   ④ 🔴 ID 口径陷阱（本数据集独有，面试可以主动讲）：
--      orders.customer_id 是「订单级匿名 ID」——每个订单一个新 ID，
--      一个真人下两单会有两个 customer_id；
--      customers.customer_unique_id 才是「用户级 ID」，算复购必须用它。
--      真实工作中同样常见：订单表里的 user_id 和设备号/账号的换算口径
--      搞错，复购率会从 3% 错算成 0%
-- ============================================================

-- 查询 4-1：每用户的 RFM 原始值（示例前 20 行）
-- R 的天数用 julianday 相减：以数据集中最大日期 2018-10-01 作为「今天」
-- 面试考点：真实工作中「今天」= 取数当天，所以 R 每天都会变
WITH rfm AS (
    SELECT
        c.customer_unique_id AS 用户ID,  -- 用户级 ID，复购必须按它聚合
        CAST(julianday('2018-10-01') - julianday(MAX(o.order_purchase_timestamp)) AS INTEGER) AS R天数,
        COUNT(DISTINCT o.order_id)  AS F次数,
        ROUND(SUM(oi.price), 2)     AS M金额
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT * FROM rfm
ORDER BY R天数 ASC
LIMIT 20;

-- 查询 4-2：NTILE 中位切分 —— 把用户按每个维度切成 2 组
-- ⚠️ 运行结果只有 4 类（重要价值/重要挽留/一般价值/一般挽留），为什么？
-- 因为这个平台复购率只有约 3%：96,096 个唯一用户里，购买 ≥2 次的才 2,801 人。
-- F 的中位数 = 1，NTILE 切在 F=1 处，于是「高频组」=「买过 2 次以上的人」，
-- 恰好也就是「高金额组」→ 重要发展/重要保持等交叉类型人数为 0。
-- 面试话术：「全量用户做 8 分类没意义，因为大部分人只买一次；
-- 正确做法是对复购用户单独做精细分层」—— 见查询 4-4
-- NTILE(2) OVER (ORDER BY R天数 ASC)：R 最小的一半 = 1 组（最近购买，好用户）
-- 注意 F/M 要 DESC 排序：值最大的一半才是 1 组（好用户）
WITH rfm AS (
    SELECT
        c.customer_unique_id AS 用户ID,  -- 用户级 ID，复购必须按它聚合
        CAST(julianday('2018-10-01') - julianday(MAX(o.order_purchase_timestamp)) AS INTEGER) AS R天数,
        COUNT(DISTINCT o.order_id)  AS F次数,
        ROUND(SUM(oi.price), 2)     AS M金额
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT *,
        NTILE(2) OVER (ORDER BY R天数 ASC)  AS R组,  -- 1 = 最近购买（好）
        NTILE(2) OVER (ORDER BY F次数 DESC) AS F组,  -- 1 = 高频（好）
        NTILE(2) OVER (ORDER BY M金额 DESC) AS M组   -- 1 = 高消费（好）
    FROM rfm
),
labelled AS (
    SELECT *,
        CASE
            WHEN R组 = 1 AND F组 = 1 AND M组 = 1 THEN '重要价值客户'
            WHEN R组 = 1 AND F组 = 1 AND M组 = 2 THEN '重要发展客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 1 THEN '重要保持客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 2 THEN '重要挽留客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 1 THEN '一般价值客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 2 THEN '一般发展客户'
            WHEN R组 = 2 AND F组 = 2 AND M组 = 1 THEN '一般保持客户'
            ELSE '一般挽留客户'
        END AS 用户类型
    FROM scored
)
SELECT
    用户类型,
    COUNT(*)        AS 人数,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS 占比百分比,
    ROUND(AVG(F次数), 2) AS 人均购买次数,
    ROUND(AVG(M金额), 2) AS 人均消费金额
FROM labelled
GROUP BY 用户类型
ORDER BY 人数 DESC;

-- 查询 4-3：重要价值客户 + 一般挽留客户的特征对比（运营策略的数据依据）
-- 面试考点：看到分层的下一步永远是「每类用户长什么样、该怎么运营」
WITH rfm AS (
    SELECT
        c.customer_unique_id AS 用户ID,  -- 用户级 ID，复购必须按它聚合
        CAST(julianday('2018-10-01') - julianday(MAX(o.order_purchase_timestamp)) AS INTEGER) AS R天数,
        COUNT(DISTINCT o.order_id)  AS F次数,
        ROUND(SUM(oi.price), 2)     AS M金额
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
scored AS (
    SELECT *,
        NTILE(2) OVER (ORDER BY R天数 ASC)  AS R组,
        NTILE(2) OVER (ORDER BY F次数 DESC) AS F组,
        NTILE(2) OVER (ORDER BY M金额 DESC) AS M组
    FROM rfm
),
labelled AS (
    SELECT *,
        CASE
            WHEN R组 = 1 AND F组 = 1 AND M组 = 1 THEN '重要价值客户'
            WHEN R组 = 1 AND F组 = 1 AND M组 = 2 THEN '重要发展客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 1 THEN '重要保持客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 2 THEN '重要挽留客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 1 THEN '一般价值客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 2 THEN '一般发展客户'
            WHEN R组 = 2 AND F组 = 2 AND M组 = 1 THEN '一般保持客户'
            ELSE '一般挽留客户'
        END AS 用户类型
    FROM scored
)
SELECT
    用户类型,
    COUNT(*)         AS 人数,
    ROUND(AVG(R天数), 1) AS 平均距上次购买天数,
    ROUND(AVG(F次数), 1) AS 平均购买次数,
    ROUND(AVG(M金额), 0) AS 平均消费金额
FROM labelled
WHERE 用户类型 IN ('重要价值客户', '重要挽留客户', '一般挽留客户')
GROUP BY 用户类型
ORDER BY 平均消费金额 DESC;

-- 查询 4-4：复购用户的精细 RFM 分层（运营资源投向会复购的人）
-- 只保留 F ≥ 2 的用户再做 NTILE(2) 切分，8 类都能出现
-- 面试话术：「RFM 不是死的，数据什么分布就用什么切法；
-- 对一次性用户分层没意义，把分层聚焦到复购人群上，运营动作才落得下去」
WITH rfm AS (
    SELECT
        c.customer_unique_id AS 用户ID,  -- 用户级 ID，复购必须按它聚合
        CAST(julianday('2018-10-01') - julianday(MAX(o.order_purchase_timestamp)) AS INTEGER) AS R天数,
        COUNT(DISTINCT o.order_id)  AS F次数,
        ROUND(SUM(oi.price), 2)     AS M金额
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
    HAVING F次数 >= 2                -- 只看复购用户
),
scored AS (
    SELECT *,
        NTILE(2) OVER (ORDER BY R天数 ASC)  AS R组,
        NTILE(2) OVER (ORDER BY F次数 DESC) AS F组,
        NTILE(2) OVER (ORDER BY M金额 DESC) AS M组
    FROM rfm
),
labelled AS (
    SELECT *,
        CASE
            WHEN R组 = 1 AND F组 = 1 AND M组 = 1 THEN '重要价值客户'
            WHEN R组 = 1 AND F组 = 1 AND M组 = 2 THEN '重要发展客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 1 THEN '重要保持客户'
            WHEN R组 = 1 AND F组 = 2 AND M组 = 2 THEN '重要挽留客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 1 THEN '一般价值客户'
            WHEN R组 = 2 AND F组 = 1 AND M组 = 2 THEN '一般发展客户'
            WHEN R组 = 2 AND F组 = 2 AND M组 = 1 THEN '一般保持客户'
            ELSE '一般挽留客户'
        END AS 用户类型
    FROM scored
)
SELECT
    用户类型,
    COUNT(*)        AS 人数,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS 占比百分比,
    ROUND(AVG(F次数), 2) AS 人均购买次数,
    ROUND(AVG(M金额), 2) AS 人均消费金额
FROM labelled
GROUP BY 用户类型
ORDER BY 人数 DESC;

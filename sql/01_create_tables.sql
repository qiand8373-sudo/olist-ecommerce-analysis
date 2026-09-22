-- ============================================================
-- Olist 电商数据库建表脚本
-- 知识点：DDL 数据定义语言、主键 PRIMARY KEY、外键 FOREIGN KEY、ER 关系
-- 面试考点：9 张表之间的关联关系（多表 JOIN 的依据）
-- ============================================================
-- 表关系速记（ER 图文字版）：
--   orders（订单主表）1 ── N order_items（订单明细：一个订单买多件商品）
--   orders 1 ── N payments（支付记录：一个订单可能分多次支付）
--   orders 1 ── 1 customers（客户信息）
--   order_items N ── 1 products（商品信息，通过 product_id 关联）
--   order_items N ── 1 sellers（卖家信息，通过 seller_id 关联）
--   orders 1 ── N reviews（评价，通过 order_id 关联）
-- ============================================================

-- 订单主表：每一行 = 一笔订单
CREATE TABLE IF NOT EXISTS olist_orders (
    order_id                        TEXT PRIMARY KEY,  -- 订单号（主键：唯一标识一笔订单）
    customer_id                     TEXT,              -- 下单客户号
    order_status                    TEXT,              -- 订单状态（delivered 已交付 / canceled 已取消...）
    order_purchase_timestamp        TEXT,              -- 下单时间（ISO 格式，方便 strftime 做日期计算）
    order_approved_at               TEXT,              -- 商家确认时间
    order_delivered_carrier_date    TEXT,              -- 交到承运商时间
    order_delivered_customer_date   TEXT,              -- 送达客户时间
    order_estimated_delivery_date   TEXT               -- 预计送达时间
);

-- 订单明细表：每一行 = 订单里的一件商品（主键是复合键：订单号+商品序号）
CREATE TABLE IF NOT EXISTS olist_order_items (
    order_id                TEXT,       -- 属于哪笔订单（外键 → orders.order_id）
    order_item_id            INTEGER,   -- 该订单里的商品序号（第 1 件、第 2 件...）
    product_id               TEXT,      -- 商品号（外键 → products.product_id）
    seller_id                TEXT,      -- 卖家号（外键 → sellers.seller_id）
    shipping_limit_date      TEXT,      -- 发货期限
    price                    REAL,      -- 商品单价
    freight_value            REAL,      -- 运费
    PRIMARY KEY (order_id, order_item_id)  -- 复合主键：订单号+序号才能唯一确定一行
);

-- 支付表：每一行 = 一次支付（一笔订单可分多期/多种方式支付）
CREATE TABLE IF NOT EXISTS olist_order_payments (
    order_id             TEXT,     -- 订单号（外键 → orders.order_id）
    payment_sequential   INTEGER,  -- 支付序号（第几次支付）
    payment_type         TEXT,     -- 支付方式（credit_card 信用卡 / boleto 银行券 / voucher 券...）
    payment_installments INTEGER,  -- 分期数
    payment_value        REAL,     -- 本次支付金额
    PRIMARY KEY (order_id, payment_sequential)
);

-- 客户表：每一行 = 一个下单账号
CREATE TABLE IF NOT EXISTS olist_customers (
    customer_id          TEXT PRIMARY KEY,  -- 客户号（主键，orders 表靠它关联）
    customer_unique_id   TEXT,              -- 客户唯一号（一个真人可能有多个账号）
    customer_zip_code_prefix TEXT,          -- 邮编前缀（关联地理位置）
    customer_city        TEXT,              -- 城市
    customer_state       TEXT               -- 州（巴西行政区划）
);

-- 商品表：每一行 = 一个商品
CREATE TABLE IF NOT EXISTS olist_products (
    product_id                  TEXT PRIMARY KEY,
    product_category_name       TEXT,   -- 类目名（葡萄牙语，需关联翻译表）
    product_name_lenght         INTEGER,  -- 名称长度（官方原表拼写如此，保留）
    product_description_lenght  INTEGER,  -- 描述长度
    product_photos_qty          INTEGER,  -- 图片数量
    product_weight_g            INTEGER,  -- 重量（克）
    product_length_cm           INTEGER,  -- 长（厘米）
    product_height_cm           INTEGER,  -- 高
    product_width_cm            INTEGER   -- 宽
);

-- 卖家表：每一行 = 一个卖家
CREATE TABLE IF NOT EXISTS olist_sellers (
    seller_id              TEXT PRIMARY KEY,
    seller_zip_code_prefix TEXT,
    seller_city            TEXT,
    seller_state           TEXT
);

-- 评价表：每一行 = 一条评价
CREATE TABLE IF NOT EXISTS olist_order_reviews (
    review_id               TEXT PRIMARY KEY,
    order_id                TEXT,     -- 评价针对哪笔订单
    review_score            INTEGER,  -- 评分 1~5
    review_comment_title    TEXT,     -- 评价标题
    review_comment_message  TEXT,     -- 评价内容
    review_creation_date    TEXT,     -- 评价时间
    review_answer_timestamp TEXT      -- 商家回复时间
);

-- 类目翻译表：葡萄牙语类目名 → 英语类目名（分析展示用英语）
CREATE TABLE IF NOT EXISTS product_category_name_translation (
    product_category_name          TEXT PRIMARY KEY,
    product_category_name_english  TEXT
);

-- ============================================================
-- 索引：加速 JOIN 和筛选（面试考点：索引为什么快？B+ 树）
-- 高频关联字段建索引：orders.customer_id、order_items.order_id 等
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_orders_customer ON olist_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_items_order    ON olist_order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_items_product  ON olist_order_items(product_id);
CREATE INDEX IF NOT EXISTS idx_payments_order ON olist_order_payments(order_id);
CREATE INDEX IF NOT EXISTS idx_reviews_order  ON olist_order_reviews(order_id);

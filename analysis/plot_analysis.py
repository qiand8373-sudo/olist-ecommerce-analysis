# -*- coding: utf-8 -*-
"""
生成项目核心图表（保存到 ../report/figures/）
用法：python plot_analysis.py   （在 analysis 目录下运行）

知识点：
- matplotlib 基础：折线图 plot / 条形图 barh / 热力图 imshow
- pandas 从 SQLite 取数（pd.read_sql_query），SQL 分析结果直接转图表
- 中文显示：设置 plt.rcParams['font.sans-serif'] 用微软雅黑
- 面试考点：图表是结论的载体——每张图背后都要能说出一句业务结论
"""
import sqlite3
import os
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use('Agg')  # 无界面环境出图
import matplotlib.pyplot as plt

plt.rcParams['font.sans-serif'] = ['Microsoft YaHei', 'SimHei']  # 中文字体
plt.rcParams['axes.unicode_minus'] = False                        # 负号正常显示

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'olist.db')
FIG_DIR = os.path.join(os.path.dirname(__file__), '..', 'report', 'figures')
os.makedirs(FIG_DIR, exist_ok=True)

# 统一配色
COLOR_MAIN = '#2B579A'
COLOR_ACCENT = '#E07B39'


def q(sql):
    """从 SQLite 取数的小工具函数"""
    conn = sqlite3.connect(DB_PATH)
    try:
        return pd.read_sql_query(sql, conn)
    finally:
        conn.close()


# ---------- 图 1：月度 GMV 趋势 ----------
df = q("""
    SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS 月份,
           ROUND(SUM(oi.price), 0) AS GMV
    FROM olist_orders o
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY 月份 ORDER BY 月份
""")
fig, ax = plt.subplots(figsize=(10, 5))
ax.plot(df['月份'], df['GMV'], marker='o', color=COLOR_MAIN, linewidth=2)
ax.set_title('月度 GMV 趋势（2016-09 至 2018-08）', fontsize=14)
ax.set_xlabel('月份'); ax.set_ylabel('GMV（巴西雷亚尔）')
ax.grid(axis='y', alpha=0.3)
plt.xticks(rotation=45)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, '01_gmv_trend.png'), dpi=150)
plt.close()

# ---------- 图 2：品类 GMV TOP10 ----------
df = q("""
    SELECT t.product_category_name_english AS 品类, ROUND(SUM(oi.price), 0) AS GMV
    FROM olist_order_items oi
    JOIN olist_products p ON oi.product_id = p.product_id
    LEFT JOIN product_category_name_translation t
        ON p.product_category_name = t.product_category_name
    JOIN olist_orders o ON o.order_id = oi.order_id AND o.order_status = 'delivered'
    GROUP BY t.product_category_name_english
    ORDER BY GMV DESC LIMIT 10
""")
fig, ax = plt.subplots(figsize=(10, 6))
ax.barh(df['品类'][::-1], df['GMV'][::-1], color=COLOR_MAIN)
ax.set_title('GMV Top 10 品类', fontsize=14)
ax.set_xlabel('GMV（巴西雷亚尔）')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, '02_category_top10.png'), dpi=150)
plt.close()

# ---------- 图 3：复购用户的 RFM 分层 ----------
df = q("""
WITH rfm AS (
    SELECT c.customer_unique_id AS 用户ID,
           CAST(julianday('2018-10-01') - julianday(MAX(o.order_purchase_timestamp)) AS INTEGER) AS R天数,
           COUNT(DISTINCT o.order_id) AS F次数,
           ROUND(SUM(oi.price), 2) AS M金额
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
    HAVING F次数 >= 2
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
            WHEN R组=1 AND F组=1 AND M组=1 THEN '重要价值客户'
            WHEN R组=1 AND F组=1 AND M组=2 THEN '重要发展客户'
            WHEN R组=1 AND F组=2 AND M组=1 THEN '重要保持客户'
            WHEN R组=1 AND F组=2 AND M组=2 THEN '重要挽留客户'
            WHEN R组=2 AND F组=1 AND M组=1 THEN '一般价值客户'
            WHEN R组=2 AND F组=1 AND M组=2 THEN '一般发展客户'
            WHEN R组=2 AND F组=2 AND M组=1 THEN '一般保持客户'
            ELSE '一般挽留客户'
        END AS 用户类型
    FROM scored
)
SELECT 用户类型, COUNT(*) AS 人数 FROM labelled GROUP BY 用户类型
""")
order = ['重要价值客户', '重要发展客户', '重要保持客户', '重要挽留客户',
         '一般价值客户', '一般发展客户', '一般保持客户', '一般挽留客户']
df['用户类型'] = pd.Categorical(df['用户类型'], categories=order, ordered=True)
df = df.sort_values('用户类型')
fig, ax = plt.subplots(figsize=(10, 5))
colors = [COLOR_ACCENT if '重要' in t else COLOR_MAIN for t in df['用户类型']]
ax.bar(df['用户类型'], df['人数'], color=colors)
ax.set_title('复购用户 RFM 分层（8 类）', fontsize=14)
ax.set_ylabel('人数')
plt.xticks(rotation=30, ha='right')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, '03_rfm_segments.png'), dpi=150)
plt.close()

# ---------- 图 4：留存热力图 ----------
df = q("""
WITH first_purchase AS (
    SELECT c.customer_unique_id AS customer_id,
           strftime('%Y-%m', MIN(o.order_purchase_timestamp)) AS 首购月份,
           CAST(strftime('%Y', MIN(o.order_purchase_timestamp)) AS INTEGER) AS 首购年,
           CAST(strftime('%m', MIN(o.order_purchase_timestamp)) AS INTEGER) AS 首购月
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
),
user_month AS (
    SELECT DISTINCT c.customer_unique_id AS customer_id,
           CAST(strftime('%Y', o.order_purchase_timestamp) AS INTEGER) AS 活跃年,
           CAST(strftime('%m', o.order_purchase_timestamp) AS INTEGER) AS 活跃月
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
),
cohort_size AS (
    SELECT 首购月份, COUNT(*) AS 新客数 FROM first_purchase GROUP BY 首购月份
)
SELECT fp.首购月份,
       (um.活跃年 - fp.首购年) * 12 + (um.活跃月 - fp.首购月) AS 第N月,
       ROUND(100.0 * COUNT(DISTINCT um.customer_id) / cs.新客数, 1) AS 留存率
FROM first_purchase fp
JOIN user_month um ON um.customer_id = fp.customer_id
JOIN cohort_size cs ON cs.首购月份 = fp.首购月份
WHERE fp.首购月份 >= '2017-06'
  AND (um.活跃年 - fp.首购年) * 12 + (um.活跃月 - fp.首购月) BETWEEN 0 AND 6
GROUP BY fp.首购月份, 第N月
""")
# 宽表化：行 = 同期群，列 = 第 N 月
matrix = df.pivot_table(index='首购月份', columns='第N月', values='留存率')
fig, ax = plt.subplots(figsize=(10, 7))
im = ax.imshow(matrix.values, cmap='Blues', aspect='auto')
ax.set_xticks(range(matrix.shape[1]), matrix.columns, fontsize=9)
ax.set_yticks(range(matrix.shape[0]), matrix.index, fontsize=9)
ax.set_title('月度同期群留存热力图（%，第 0-6 月）', fontsize=14)
ax.set_xlabel('首购后第 N 个月')
ax.set_ylabel('首购月份（同期群）')
fig.colorbar(im, ax=ax, label='留存率 %')
# 在格子里标注数值
for i in range(matrix.shape[0]):
    for j in range(matrix.shape[1]):
        v = matrix.values[i, j]
        if not np.isnan(v):
            ax.text(j, i, f'{v:.1f}', ha='center', va='center',
                    fontsize=8, color='white' if v > 30 else '#333333')
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, '04_retention_heatmap.png'), dpi=150)
plt.close()

# ---------- 图 5：州 GMV 排名 ----------
df = q("""
    SELECT c.customer_state AS 州, ROUND(SUM(oi.price), 0) AS GMV
    FROM olist_orders o
    JOIN olist_customers c ON o.customer_id = c.customer_id
    JOIN olist_order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
    ORDER BY GMV DESC LIMIT 10
""")
fig, ax = plt.subplots(figsize=(10, 5))
ax.bar(df['州'], df['GMV'], color=COLOR_ACCENT)
ax.set_title('GMV Top 10 州（SP 圣保罗州一家独大）', fontsize=14)
ax.set_ylabel('GMV（巴西雷亚尔）')
ax.grid(axis='y', alpha=0.3)
plt.tight_layout()
plt.savefig(os.path.join(FIG_DIR, '05_state_top10.png'), dpi=150)
plt.close()

print('✅ 5 张图表已生成到 report/figures/：')
for f in sorted(os.listdir(FIG_DIR)):
    print('  -', f)

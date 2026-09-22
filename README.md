# Olist 电商销售与用户分析

基于巴西电商平台 Olist 公开数据集（约 10 万订单，2016-2018）的销售与用户分析项目。

面向运营/商业分析实习岗位：覆盖 GMV 拆解、品类分析、RFM 用户分层、同期群留存、地域分析五大模块，SQL 为主、Python 可视化为辅。

## 数据来源

Kaggle 公开数据集 [Olist Brazilian E-Commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)（GitHub 镜像下载）。原始 CSV 不入库（.gitignore 排除）。

## 目录结构

```
olist-ecommerce-analysis/
├── data/            # 原始 CSV + SQLite 数据库（不入 git）
├── sql/             # SQL 分析与建库脚本
│   ├── 01_create_tables.sql       # 建表：DDL、主外键、索引
│   ├── 02_sales_overview.sql      # 销售概览：GMV、客单价、月度趋势
│   ├── 03_category_analysis.sql   # 品类分析：排名、帕累托、件单价
│   ├── 04_user_rfm.sql            # RFM 用户分层（含复购用户精细分层）
│   ├── 05_retention_cohort.sql    # 同期群留存、复购率
│   ├── 06_geo_analysis.sql        # 地域分析
│   ├── load_data.py               # CSV 导入 SQLite
│   └── run_sql.py                 # SQL 执行器
├── analysis/
│   └── plot_analysis.py           # 生成 5 张核心图表
└── report/
    ├── 分析报告.md                 # 结论与运营建议
    └── figures/                   # 图表 PNG
```

## 快速开始

```bash
# 1. 下载数据（9 个 CSV 放到 data/ 目录，来源见上方链接）

# 2. 建库导入
cd sql
python load_data.py

# 3. 运行分析（按模块逐个跑，代码里带知识点注释）
python run_sql.py 02_sales_overview.sql
python run_sql.py 03_category_analysis.sql
python run_sql.py 04_user_rfm.sql
python run_sql.py 05_retention_cohort.sql
python run_sql.py 06_geo_analysis.sql

# 4. 生成图表
cd ../analysis
python plot_analysis.py
```

## 核心结论速览

- 平台 2017 年高速增长，2018 年进入平台期（月 GMV 85-95 万）
- Top 10 品类占 GMV 62.4%，头部为健康美妆/手表礼品/床品卫浴
- 复购率仅 3.0%，同期群第 1 月留存跌至 0.3%——重拉新轻促活，首购后 30 天触达是 ROI 最高动作
- 复购用户中重要价值客户人均消费 419.9，是挽留客户的 3.75 倍
- 销售集中于东南部，SP 州占约 38%

## 学习知识点清单

SQL：DDL/DML、多表 JOIN、窗口函数（SUM OVER、NTILE）、CTE、CASE WHEN、strftime 日期函数、索引原理、ID 口径（customer_id vs customer_unique_id）

Python：pandas 读写、matplotlib 五种图表、SQLite 连接

分析方法：GMV 口径、帕累托分析、RFM 8 分层、同期群留存、复购率

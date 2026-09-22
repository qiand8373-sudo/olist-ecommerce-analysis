# -*- coding: utf-8 -*-
"""
把 Olist 的 CSV 原始数据导入 SQLite 数据库
用法：python load_data.py   （在 sql 目录下运行）

知识点：
- pandas.read_csv 读 CSV（大数据场景会用分块读取 chunksize，这里文件小直接读）
- DataFrame.to_sql 把 DataFrame 写入数据库表
- sqlite3 是 Python 内置库，SQLite 是文件型数据库（单文件 .db，无需安装服务）
- 面试考点：SQLite 和 MySQL 的区别（SQLite 单机文件库、MySQL 客户端-服务器架构），
  但 SQL 语法基本兼容，练习用的查询语句在 MySQL 里照写
"""
import sqlite3
import pandas as pd
import os

DATA_DIR = os.path.join(os.path.dirname(__file__), '..', 'data')
DB_PATH = os.path.join(DATA_DIR, 'olist.db')

# 要导入的表：(CSV 文件名, 数据库表名)
TABLES = [
    ('olist_orders_dataset', 'olist_orders'),
    ('olist_order_items_dataset', 'olist_order_items'),
    ('olist_order_payments_dataset', 'olist_order_payments'),
    ('olist_customers_dataset', 'olist_customers'),
    ('olist_products_dataset', 'olist_products'),
    ('olist_sellers_dataset', 'olist_sellers'),
    ('olist_order_reviews_dataset', 'olist_order_reviews'),
    ('product_category_name_translation', 'product_category_name_translation'),
]

# 地理表 100 万行（经纬度），本项目的分析不直接用它（客户表里已有城市/州），
# 默认跳过以加快导入；想导入改成 True
IMPORT_GEOLOCATION = False


def create_tables(conn):
    """执行建表脚本 01_create_tables.sql"""
    sql_path = os.path.join(os.path.dirname(__file__), '01_create_tables.sql')
    with open(sql_path, encoding='utf-8') as f:
        conn.executescript(f.read())
    print('✅ 建表完成（含索引）')


def load_table(conn, csv_name, table_name):
    csv_path = os.path.join(DATA_DIR, csv_name + '.csv')
    df = pd.read_csv(csv_path, dtype=str)  # 全部按字符串读，避免科学计数法破坏 ID
    df.to_sql(table_name, conn, if_exists='replace', index=False)
    print(f'✅ {table_name:<38} {len(df):>9,} 行')


def main():
    # 删掉旧库重建，保证每次导入结果一致（幂等）
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
        print('🔄 已删除旧数据库，重新构建')

    conn = sqlite3.connect(DB_PATH)
    try:
        create_tables(conn)
        for csv_name, table_name in TABLES:
            load_table(conn, csv_name, table_name)
        if IMPORT_GEOLOCATION:
            load_table(conn, 'olist_geolocation_dataset', 'olist_geolocation')
        conn.commit()

        # 验证：输出各表行数，和官方数据规模对得上（约 10 万订单）
        print('\n===== 表行数汇总 =====')
        for (row,) in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
        ):
            n = conn.execute(f'SELECT COUNT(*) FROM "{row}"').fetchone()[0]
            print(f'{row:<38} {n:>9,} 行')
    finally:
        conn.close()


if __name__ == '__main__':
    main()

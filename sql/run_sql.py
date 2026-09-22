# -*- coding: utf-8 -*-
"""
SQL 执行器：运行 sql 目录下的 .sql 分析文件并打印结果
用法：python run_sql.py 02_sales_overview.sql   （在 sql 目录下运行）

知识点：
- 每个 .sql 文件里写多条 SQL，每条以分号结尾，中间用 -- 写注释
- 执行器把查询结果用 pandas 打印成表格，方便看和复制到报告
"""
import sqlite3
import pandas as pd
import sys
import os

DB_PATH = os.path.join(os.path.dirname(__file__), '..', 'data', 'olist.db')
pd.set_option('display.width', 200)          # 输出宽度放宽，避免表格折行
pd.set_option('display.max_columns', 30)     # 最多显示 30 列
pd.set_option('display.float_format', '{:,.2f}'.format)  # 金额千分位


def run_sql_file(sql_file):
    with open(sql_file, encoding='utf-8') as f:
        script = f.read()

    conn = sqlite3.connect(DB_PATH)
    try:
        # 按分号切分成多条 SQL（注释行以 -- 开头，不影响切分）
        statements = [s.strip() for s in script.split(';') if s.strip()]
        for i, sql in enumerate(statements, 1):
            # 跳过纯注释块（没有实质 SQL 关键字）
            real_lines = [ln for ln in sql.splitlines()
                          if ln.strip() and not ln.strip().startswith('--')]
            if not real_lines:
                continue
            print('=' * 70)
            print(f'【查询 {i}】')
            print('=' * 70)
            df = pd.read_sql_query(sql, conn)
            print(df.to_string(index=False))
            print(f'（共 {len(df)} 行）\n')
    finally:
        conn.close()


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('用法：python run_sql.py <sql文件名>')
        print('例如：python run_sql.py 02_sales_overview.sql')
        sys.exit(1)
    run_sql_file(sys.argv[1])

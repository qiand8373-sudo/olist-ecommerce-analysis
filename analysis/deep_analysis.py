# -*- coding: utf-8 -*-
"""
Olist 深度分析模块（在基础报告之上补充三个模块）
==================================================
模块 A：复购用户 vs 新客画像对比  —— 回答"什么样的用户会复购"
模块 B：差评驱动因素分析          —— 物流延迟/品类/金额对差评率的影响
模块 C：复购概率预测模型          —— logistic regression（机器学习入门）

口径铁律（沿用项目规范）：
  - 仅统计 order_status = 'delivered' 的订单
  - 复购/用户维度一律用 customer_unique_id（customer_id 是订单级匿名 ID）
"""
import sqlite3

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (accuracy_score, classification_report,
                             roc_auc_score)
from sklearn.model_selection import train_test_split

plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei"]
plt.rcParams["axes.unicode_minus"] = False

DB = r"C:/Users/12923/Desktop/我的项目/olist-ecommerce-analysis/data/olist.db"
FIG = r"C:/Users/12923/Desktop/我的项目/olist-ecommerce-analysis/report/figures"

# ---------------------------------------------------------------
# 公共数据准备：订单宽表（delivered 口径）
# ---------------------------------------------------------------
def load_order_wide():
    """构建订单级宽表：订单、商品、支付、评价、物流时效全部 JOIN 进来"""
    con = sqlite3.connect(DB)
    sql = """
    SELECT
        o.order_id,
        o.customer_id,
        c.customer_unique_id,
        c.customer_state,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        -- 物流时效：实际送达日期 - 预计送达日期（负数为提前送达）
        julianday(o.order_delivered_customer_date) - julianday(o.order_estimated_delivery_date) AS delivery_delta_days
    FROM olist_orders o
    JOIN olist_customers c ON c.customer_id = o.customer_id
    WHERE o.order_status = 'delivered'
    """
    orders = pd.read_sql(sql, con)

    # 订单金额（items 聚合）
    items = pd.read_sql("""
        SELECT order_id, SUM(price) AS order_value, COUNT(*) AS item_cnt,
               COUNT(DISTINCT product_id) AS distinct_products
        FROM olist_order_items GROUP BY order_id
    """, con)

    # 支付方式（每单可能多行，取主支付 payment_sequential=1）
    pay = pd.read_sql("""
        SELECT order_id, payment_type, payment_installments
        FROM olist_order_payments WHERE payment_sequential = 1
    """, con)

    # 评价分数（每单可能多行，取订单级平均分）
    rev = pd.read_sql("""
        SELECT order_id,
               AVG(review_score) AS avg_score,
               MAX(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS is_bad_review
        FROM olist_order_reviews GROUP BY order_id
    """, con)

    # 品类（订单中商品数量最多的品类作为主品类；品类名在 products 表）
    cat = pd.read_sql("""
        SELECT i.order_id, p.product_category_name
        FROM olist_order_items i
        JOIN olist_products p ON p.product_id = i.product_id
    """, con)
    main_cat = (cat.groupby("order_id")["product_category_name"]
                   .agg(lambda s: s.value_counts().index[0]
                        if s.notna().any() else None)
                   .rename("main_category"))
    # 英文翻译（报告用）
    trans = pd.read_sql("SELECT * FROM product_category_name_translation", con)
    main_cat = (main_cat.reset_index().merge(trans, left_on="main_category",
                                             right_on="product_category_name",
                                             how="left")
                .drop(columns="product_category_name"))

    df = orders.merge(items, on="order_id", how="left") \
               .merge(pay, on="order_id", how="left") \
               .merge(rev, on="order_id", how="left") \
               .merge(main_cat, on="order_id", how="left")
    con.close()
    return df


# ---------------------------------------------------------------
# 模块 A：复购用户 vs 新客画像
# ---------------------------------------------------------------
def module_a_user_profile(df):
    print("=" * 60)
    print("模块 A：复购用户 vs 单次购买用户画像对比")
    print("=" * 60)

    # 用户级聚合：按 customer_unique_id 统计
    user = df.groupby("customer_unique_id").agg(
        order_cnt=("order_id", "count"),
        total_value=("order_value", "sum"),
        first_order=("order_purchase_timestamp", "min"),
        last_order=("order_purchase_timestamp", "max"),
        state=("customer_state", "first"),
    )
    user["is_repeat"] = user["order_cnt"] >= 2
    repeat_n = user["is_repeat"].sum()
    once_n = (~user["is_repeat"]).sum()
    print(f"复购用户（≥2单）: {repeat_n} 人 | 单次购买用户: {once_n} 人 "
          f"| 复购率: {repeat_n / len(user) * 100:.1f}%")

    # 对比表
    cmp = user.groupby("is_repeat").agg(
        人均消费=("total_value", "mean"),
        人均订单数=("order_cnt", "mean"),
    ).round(2)
    print(cmp)

    # 复购用户的品类偏好 vs 单次用户
    df2 = df.merge(user[["is_repeat"]], left_on="customer_unique_id",
                   right_index=True)
    # 按用户主品类统计订单分布（每人第一个订单的主品类代表首购偏好）
    first_orders = df2.sort_values("order_purchase_timestamp") \
                      .groupby("customer_unique_id").head(1)
    cat_dist = first_orders.groupby(["is_repeat", "product_category_name_english"]) \
                           .size().unstack(fill_value=0)
    cat_share = cat_dist.div(cat_dist.sum(axis=1), axis=0) * 100
    top = cat_share.mean().sort_values(ascending=False).head(10).index
    print("\n首购品类分布（Top 10 品类，单位 %）：")
    print(cat_share[top].round(1).T)

    # 支付方式差异
    pay_dist = df2.groupby(["is_repeat", "payment_type"]) \
                  .size().unstack(fill_value=0)
    print("\n支付方式分布（单位 %）：")
    print(pay_dist.div(pay_dist.sum(axis=1), axis=0).mul(100).round(1).T)

    # 复购间隔（复购用户的第 2 单距首单中位天数）
    def repeat_gap(g):
        if len(g) < 2:
            return np.nan
        ts = pd.to_datetime(g).sort_values()
        return (ts.iloc[1] - ts.iloc[0]).days
    gaps = df2[df2["is_repeat"]].groupby("customer_unique_id") \
             ["order_purchase_timestamp"].apply(repeat_gap).dropna()
    print(f"\n复购用户第 2 单距首单间隔: 中位数 {gaps.median():.0f} 天, "
          f"30 天内复购占比 {(gaps <= 30).mean() * 100:.1f}%")

    # 图 A-1：品类对比柱状图
    fig, ax = plt.subplots(figsize=(10, 5))
    x = np.arange(len(top))
    w = 0.35
    ax.bar(x - w/2, cat_share.loc[True, top], w, label="复购用户")
    ax.bar(x + w/2, cat_share.loc[False, top], w, label="单次购买用户")
    ax.set_xticks(x, cat_share[top].columns, rotation=35, ha="right")
    ax.set_ylabel("首购品类占比 %")
    ax.set_title("复购用户 vs 单次用户：首购品类偏好对比")
    ax.legend()
    fig.tight_layout()
    fig.savefig(f"{FIG}/A1_category_profile.png", dpi=120)
    plt.close(fig)
    print("图已保存 A1_category_profile.png")

    return user


# ---------------------------------------------------------------
# 模块 B：差评驱动因素
# ---------------------------------------------------------------
def module_b_bad_review(df):
    print("\n" + "=" * 60)
    print("模块 B：差评（≤2 分）驱动因素分析")
    print("=" * 60)

    d = df.dropna(subset=["avg_score"])
    d["is_late"] = d["delivery_delta_days"] > 0
    d["is_very_late"] = d["delivery_delta_days"] > 5
    n = len(d)
    bad = d["is_bad_review"].sum()
    print(f"有评价订单 {n} 笔，差评订单 {bad} 笔，差评率 {bad / n * 100:.1f}%")

    # 因素 1：物流延迟
    late = d.groupby("is_late")["is_bad_review"].agg(["size", "mean"])
    print("\n物流延迟 vs 差评率：")
    print(late.rename(columns={"size": "订单数", "mean": "差评率"}).round(3))
    very_late = d.groupby("is_very_late")["is_bad_review"].agg(["size", "mean"])
    print("\n严重延迟（>5天）vs 差评率：")
    print(very_late.rename(columns={"size": "订单数", "mean": "差评率"}).round(3))

    # 因素 2：品类差评率排行（订单数 >= 500 的品类）
    cat_bad = d.groupby("product_category_name_english").agg(
        订单数=("is_bad_review", "size"),
        差评率=("is_bad_review", "mean"),
    ).query("订单数 >= 500").sort_values("差评率", ascending=False)
    print("\n差评率最高的 5 个品类（订单≥500）：")
    print((cat_bad.head(5)["差评率"] * 100).round(1).to_string() + " %")

    # 因素 3：订单金额分层
    d["value_bin"] = pd.cut(d["order_value"], bins=[0, 50, 100, 200, 500, 99999],
                            labels=["<50", "50-100", "100-200", "200-500", ">500"])
    val_bad = d.groupby("value_bin")["is_bad_review"].agg(["size", "mean"])
    print("\n订单金额分层 vs 差评率：")
    print(val_bad.rename(columns={"size": "订单数", "mean": "差评率"}).round(3))

    # 图 B-1：差评率对比图（物流维度）
    fig, axes = plt.subplots(1, 2, figsize=(11, 4))
    late.plot.bar(y="mean", ax=axes[0], legend=False)
    axes[0].set_title("物流延迟（>预计送达日）vs 差评率")
    axes[0].set_xticklabels(["准时", "延迟"], rotation=0)
    axes[0].set_ylabel("差评率")
    very_late.plot.bar(y="mean", ax=axes[1], legend=False)
    axes[1].set_title("严重延迟（>5 天）vs 差评率")
    axes[1].set_xticklabels(["≤5天", ">5天"], rotation=0)
    axes[1].set_ylabel("差评率")
    fig.tight_layout()
    fig.savefig(f"{FIG}/B1_delivery_badreview.png", dpi=120)
    plt.close(fig)
    print("图已保存 B1_delivery_badreview.png")


# ---------------------------------------------------------------
# 模块 C：复购概率预测模型
# ---------------------------------------------------------------
def module_c_repeat_model(df, user):
    print("\n" + "=" * 60)
    print("模块 C：复购概率预测（逻辑回归 + 随机森林对比）")
    print("=" * 60)

    # 特征构造：用每个用户「首单」的特征预测其是否会复购
    first = df.sort_values("order_purchase_timestamp") \
              .groupby("customer_unique_id").head(1).copy()
    feat = first.merge(user[["is_repeat"]], left_on="customer_unique_id",
                       right_index=True)

    # 类别编码：主品类（保留订单数 top 15，其余归为 other）
    top_cats = feat["product_category_name_english"].value_counts().head(15).index
    feat["cat_code"] = feat["product_category_name_english"] \
        .where(feat["product_category_name_english"].isin(top_cats), "other")
    feat["payment_type"] = feat["payment_type"].fillna("unknown")

    X = pd.get_dummies(feat[["order_value", "item_cnt", "distinct_products",
                             "payment_installments", "cat_code", "payment_type",
                             "customer_state"]],
                       columns=["cat_code", "payment_type", "customer_state"],
                       drop_first=True)
    X = X.fillna(0)
    y = feat["is_repeat"].astype(int)

    X_tr, X_te, y_tr, y_te = train_test_split(
        X, y, test_size=0.3, random_state=42, stratify=y)

    results = {}
    for name, model in [("逻辑回归", LogisticRegression(max_iter=3000,
                                                        class_weight="balanced")),
                        ("随机森林", RandomForestClassifier(n_estimators=200,
                                                            max_depth=8,
                                                            class_weight="balanced",
                                                            random_state=42))]:
        model.fit(X_tr, y_tr)
        pred = model.predict(X_te)
        proba = model.predict_proba(X_te)[:, 1]
        acc = accuracy_score(y_te, pred)
        auc = roc_auc_score(y_te, proba)
        results[name] = (acc, auc)
        print(f"\n{name}: 准确率 {acc:.3f}, AUC {auc:.3f} "
              f"(基线随机猜测 AUC=0.5, 复购占比基线 {y.mean():.1%})")
        if name == "逻辑回归":
            imp = pd.Series(model.coef_[0], index=X.columns)
            print("Top 5 正向特征（提升复购概率）:")
            print(imp.sort_values(ascending=False).head(5).round(4))
            print("Top 5 负向特征（降低复购概率）:")
            print(imp.sort_values().head(5).round(4))
        else:
            imp = pd.Series(model.feature_importances_, index=X.columns)
            print("Top 5 重要特征:")
            print(imp.sort_values(ascending=False).head(5).round(4))
    return results


if __name__ == "__main__":
    df = load_order_wide()
    print(f"delivered 订单宽表: {len(df)} 行")
    user = module_a_user_profile(df)
    module_b_bad_review(df)
    module_c_repeat_model(df, user)

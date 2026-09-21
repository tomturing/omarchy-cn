#!/usr/bin/env python3
"""Semantica 知识图谱排障与因果推理查询工具 (query_kg.py)

功能：
1. 面向排障场景，针对故障现象或组件关键字进行多跳因果溯源。
2. 支持查询“导致原因 (Root Causes)”与“解决措施/排障步骤 (Solutions)”。
3. 支持原生 Cypher 自定义查询或直接查询 Oxigraph 三元组。
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))


def query_neo4j(keyword: str, max_hops: int = 2):
    uri = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
    user = os.getenv("NEO4J_USER", "neo4j")
    pwd = os.getenv("NEO4J_PASS", "semantica2026")

    from neo4j import GraphDatabase
    driver = GraphDatabase.driver(uri, auth=(user, pwd))

    print(f"\n🔍 正在检索知识图谱 (关键字: '{keyword}', 最大跳数: {max_hops})...\n")

    with driver.session() as session:
        # 1. 查找匹配的实体
        match_query = """
        MATCH (e:Entity)
        WHERE e.id CONTAINS $kw OR e.name CONTAINS $kw
        RETURN e.id AS id, e.name AS name, e.type AS type
        LIMIT 10
        """
        matched = session.run(match_query, kw=keyword).data()
        if not matched:
            print(f"❌ 未找到与 '{keyword}' 匹配的实体节点。")
            driver.close()
            return

        print(f"📌 命中的匹配实体 ({len(matched)} 个):")
        for m in matched:
            print(f"  - [{m['type']}] {m['name']}")

        target_id = matched[0]["id"]
        print(f"\n⚡ 以核心节点 [{target_id}] 为锚点展开排障因果链条:")

        # 2. 向上溯源：查找诱因和根因
        upstream_query = f"""
        MATCH path = (cause:Entity)-[r*1..{max_hops}]->(target:Entity {{id: $tid}})
        RETURN [n in nodes(path) | n.name] AS chain,
               [rel in relationships(path) | type(rel)] AS rels
        LIMIT 15
        """
        up_results = session.run(upstream_query, tid=target_id).data()
        if up_results:
            print(f"\n  🔴 向上溯源 (可能诱因 / 前置根因):")
            for res in up_results:
                chain = res["chain"]
                rels = res["rels"]
                steps = []
                for i in range(len(rels)):
                    steps.append(f"{chain[i]} --[{rels[i]}]--> ")
                steps.append(chain[-1])
                print(f"    • {''.join(steps)}")
        else:
            print("  ⚪ 向上溯源: 暂无前置诱因关联")

        # 3. 向下溯源：查找影响、排障动作或关联组件
        downstream_query = f"""
        MATCH path = (target:Entity {{id: $tid}})-[r*1..{max_hops}]->(effect:Entity)
        RETURN [n in nodes(path) | n.name] AS chain,
               [rel in relationships(path) | type(rel)] AS rels
        LIMIT 15
        """
        down_results = session.run(downstream_query, tid=target_id).data()
        if down_results:
            print(f"\n  🟢 向下发散 (导致的后果 / 触发动作 / 关联组件):")
            for res in down_results:
                chain = res["chain"]
                rels = res["rels"]
                steps = []
                for i in range(len(rels)):
                    steps.append(f"{chain[i]} --[{rels[i]}]--> ")
                steps.append(chain[-1])
                print(f"    • {''.join(steps)}")
        else:
            print("  ⚪ 向下发散: 暂无后置关联")

    driver.close()


def query_cypher(cypher_sql: str):
    uri = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
    user = os.getenv("NEO4J_USER", "neo4j")
    pwd = os.getenv("NEO4J_PASS", "semantica2026")

    from neo4j import GraphDatabase
    driver = GraphDatabase.driver(uri, auth=(user, pwd))
    print(f"\n⚡ 执行自定义 Cypher: {cypher_sql}\n")
    with driver.session() as session:
        result = session.run(cypher_sql)
        records = result.data()
        print(f"返回结果数: {len(records)}")
        for r in records[:20]:
            print(" ", r)
    driver.close()


def main():
    parser = argparse.ArgumentParser(description="Semantica 知识图谱排障与因果推理查询工具")
    parser.add_argument("query", nargs="?", default="虚拟机开机", help="检索关键字或实体名")
    parser.add_argument("--hops", type=int, default=2, help="多跳推理深度 (默认 2)")
    parser.add_argument("--cypher", default=None, help="执行原生 Cypher 语句")

    args = parser.parse_args()
    if args.cypher:
        query_cypher(args.cypher)
    else:
        query_neo4j(args.query, max_hops=args.hops)


if __name__ == "__main__":
    main()

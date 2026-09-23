#!/usr/bin/env python3
"""Semantica Neo4j 双向数据同步桥 (neo4j_sync_bridge.py)

功能：
1. 监听/拉取 (pull)：专家在 Neo4j Browser / Bloom 中通过可视化或 Cypher 做出的任意修改，通过本同步桥反向比对并拉取回 Canonical SSOT 主库，并广播至 Oxigraph 和 8088 全景网页。
2. 推送 (push)：将 Canonical SSOT 状态全量刷新覆盖至 Neo4j。
3. 差异核对 (diff)：检查 Neo4j 在线库与 Canonical SSOT 之间的实体与关系差异。
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

CANONICAL_PATH = BASE_DIR / "data/canonical/canonical_kg.json"
CHANGELOG_PATH = BASE_DIR / "data/canonical/changelog.jsonl"


def get_neo4j_data(uri: str, user: str, pwd: str) -> tuple[dict[str, dict], dict[tuple, dict]]:
    from neo4j import GraphDatabase
    driver = GraphDatabase.driver(uri, auth=(user, pwd))

    neo_entities = {}
    neo_relationships = {}

    with driver.session() as session:
        # 1. 抓取所有 Entity 节点
        node_records = session.run("""
            MATCH (e:Entity)
            RETURN e.id AS id, e.name AS name, e.type AS type, properties(e) AS props, labels(e) AS labels
        """).data()
        for r in node_records:
            eid = str(r["id"])
            props = dict(r["props"])
            # 清除保留系统属性
            props.pop("id", None)
            props.pop("name", None)
            props.pop("type", None)
            neo_entities[eid] = {
                "id": eid,
                "name": str(r["name"] or eid),
                "type": str(r["type"] or "Entity"),
                "properties": props
            }

        # 2. 抓取所有关系
        rel_records = session.run("""
            MATCH (s:Entity)-[r]->(t:Entity)
            RETURN s.id AS s, t.id AS t, type(r) AS type, r.confidence AS conf, properties(r) AS props
        """).data()
        for r in rel_records:
            s = str(r["s"])
            t = str(r["t"])
            rtype = str(r["type"])
            conf = float(r["conf"] or 1.0)
            props = dict(r["props"])
            props.pop("confidence", None)
            neo_relationships[(s, t, rtype)] = {
                "source": s,
                "target": t,
                "type": rtype,
                "confidence": conf,
                "properties": props
            }

    driver.close()
    return neo_entities, neo_relationships


def diff_neo4j():
    uri = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
    user = os.getenv("NEO4J_USER", "neo4j")
    pwd = os.getenv("NEO4J_PASS", "semantica2026")

    with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
        kg = json.load(f)

    ssot_entities = {e["id"]: e for e in kg.get("entities", [])}
    ssot_rels = {(r["source"], r["target"], r.get("type", "RELATED_TO")): r for r in kg.get("relationships", [])}

    neo_entities, neo_rels = get_neo4j_data(uri, user, pwd)

    nodes_in_neo_only = set(neo_entities.keys()) - set(ssot_entities.keys())
    nodes_in_ssot_only = set(ssot_entities.keys()) - set(neo_entities.keys())
    rels_in_neo_only = set(neo_rels.keys()) - set(ssot_rels.keys())
    rels_in_ssot_only = set(ssot_rels.keys()) - set(neo_rels.keys())

    print("=== Neo4j 在线库 VS Canonical SSOT 差异比对 ===")
    print(f"SSOT 实体: {len(ssot_entities)} | Neo4j 实体: {len(neo_entities)}")
    print(f"SSOT 关系: {len(ssot_rels)} | Neo4j 关系: {len(neo_rels)}")

    if nodes_in_neo_only:
        print(f"\n[+] Neo4j 中新增的实体 (待回流): {len(nodes_in_neo_only)}")
        for n in list(nodes_in_neo_only)[:5]:
            print(f"    • {n}")
    if nodes_in_ssot_only:
        print(f"\n[-] SSOT 中存在但 Neo4j 已被删除的实体: {len(nodes_in_ssot_only)}")
        for n in list(nodes_in_ssot_only)[:5]:
            print(f"    • {n}")
    if rels_in_neo_only:
        print(f"\n[+] Neo4j 中新增的关系: {len(rels_in_neo_only)}")
        for r in list(rels_in_neo_only)[:5]:
            print(f"    • {r[0]} -[{r[2]}]-> {r[1]}")
    if rels_in_ssot_only:
        print(f"\n[-] SSOT 中存在但 Neo4j 已被删除的关系: {len(rels_in_ssot_only)}")
        for r in list(rels_in_ssot_only)[:5]:
            print(f"    • {r[0]} -[{r[2]}]-> {r[1]}")

    if not (nodes_in_neo_only or nodes_in_ssot_only or rels_in_neo_only or rels_in_ssot_only):
        print("✅ 数据完全一致，无任何漂移！")


def pull_from_neo4j():
    uri = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
    user = os.getenv("NEO4J_USER", "neo4j")
    pwd = os.getenv("NEO4J_PASS", "semantica2026")

    print(f"🔄 正在从 Neo4j ({uri}) 反向捕获修改并对齐 SSOT...")
    neo_entities, neo_rels = get_neo4j_data(uri, user, pwd)

    with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
        kg = json.load(f)

    # 完整以 Neo4j 当前最新状态反哺 SSOT
    updated_kg = {
        "entities": list(neo_entities.values()),
        "relationships": list(neo_rels.values()),
        "metadata": {
            "last_updated": datetime.datetime.now().isoformat(),
            "source": "neo4j_bidirectional_pull",
            "stats": {
                "entities": len(neo_entities),
                "relationships": len(neo_rels)
            }
        }
    }

    with open(CANONICAL_PATH, "w", encoding="utf-8") as f:
        json.dump(updated_kg, f, ensure_ascii=False, indent=2)

    # 记录审计
    audit_entry = {
        "timestamp": datetime.datetime.now().isoformat(),
        "action": "neo4j_pull_sync",
        "entities_count": len(neo_entities),
        "relationships_count": len(neo_rels)
    }
    with open(CHANGELOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(audit_entry, ensure_ascii=False) + "\n")

    print(f"✅ [Neo4j ➔ SSOT 反向同步成功] Canonical KG 已同步更新为: {len(neo_entities)} 实体, {len(neo_rels)} 关系")

    # 广播同步至 Oxigraph 与 8088 网页
    print("\n⚡ 广播同步至 Oxigraph 与 Vis-Network 全景大盘...")
    from pipeline.sync_dispatcher import sync_to_oxigraph
    from scripts.generate_html_visualizer import generate_visualizer

    sync_to_oxigraph(updated_kg, BASE_DIR / "data/oxigraph", clear=True)
    target_html = BASE_DIR / "kb_out_win_qwen38/index.html"
    generate_visualizer(str(CANONICAL_PATH), str(target_html))
    print(f"  🎨 [Vis-Network] 全景网页已同步刷新: {target_html}")

    print("\n🎉 Neo4j 双向数据流反向对齐全部完成！")


def main():
    parser = argparse.ArgumentParser(description="Semantica Neo4j 双向数据同步桥")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("diff", help="比对 Neo4j 与 SSOT 差异")
    subparsers.add_parser("pull", help="从 Neo4j 拉取最新修改并反哺 SSOT 和其他端")
    subparsers.add_parser("push", help="将 SSOT 强制覆盖推送到 Neo4j")

    args = parser.parse_args()
    if args.command == "diff":
        diff_neo4j()
    elif args.command == "pull":
        pull_from_neo4j()
    elif args.command == "push":
        from pipeline.sync_dispatcher import sync_to_neo4j
        with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
            kg = json.load(f)
        sync_to_neo4j(kg, os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687"), os.getenv("NEO4J_USER", "neo4j"), os.getenv("NEO4J_PASS", "semantica2026"), clear=True)


if __name__ == "__main__":
    main()

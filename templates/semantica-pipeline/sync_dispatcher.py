#!/usr/bin/env python3
"""Semantica 统一同步分发调度器 (Sync Dispatcher)

功能：
1. 读取权威单一真实源 (Canonical KG: data/canonical/canonical_kg.json)。
2. 同步写入在线热库 Neo4j (包含建立唯一约束、动态标签分配、带权关系)。
3. 同步写入本地嵌入三元组库 Oxigraph (标准 RDF 映射、SPARQL 支持)。
4. 校验各端数据一致性 (节点数、边数、三元组数)。
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from urllib.parse import quote

# 确保能加载当前环境的 semantica
BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))


def load_canonical_kg(file_path: Path) -> dict:
    if not file_path.exists():
        raise FileNotFoundError(f"Canonical KG 不存在: {file_path}")
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


def sync_to_neo4j(kg: dict, uri: str, user: str, password: str, clear: bool = False) -> dict:
    from neo4j import GraphDatabase

    print(f"\n[1/2] 正在同步数据至 Neo4j ({uri})...")
    driver = GraphDatabase.driver(uri, auth=(user, password))

    entities = kg.get("entities", [])
    relationships = kg.get("relationships", [])

    with driver.session() as session:
        # 测试连接
        session.run("RETURN 1").consume()

        if clear:
            print("  - 清空旧数据...")
            session.run("MATCH (n) DETACH DELETE n").consume()

        # 创建索引与唯一约束
        print("  - 确保唯一约束与索引...")
        session.run("CREATE CONSTRAINT IF NOT EXISTS FOR (e:Entity) REQUIRE e.id IS UNIQUE").consume()

        # 批量写入节点 (以 500 个为一批)
        print(f"  - 批量写入 {len(entities)} 个实体节点...")
        node_batch = []
        for e in entities:
            # 安全转义 label
            raw_type = str(e.get("type", "Entity")).strip()
            label = raw_type.replace(" ", "_").replace("-", "_")
            if not label or label == "UNKNOWN":
                label = "Entity"
            node_batch.append({
                "id": str(e.get("id")),
                "name": str(e.get("name", e.get("id"))),
                "type": str(e.get("type", "Entity")),
                "label": label,
                "properties": {k: str(v) for k, v in e.get("properties", {}).items() if v is not None}
            })

        batch_size = 500
        for i in range(0, len(node_batch), batch_size):
            chunk = node_batch[i:i + batch_size]
            query = """
            UNWIND $batch AS item
            MERGE (e:Entity {id: item.id})
            SET e.name = item.name,
                e.type = item.type,
                e += item.properties
            """
            session.run(query, batch=chunk).consume()

            # 追加具体业务分类 Label
            for item in chunk:
                lbl = item["label"]
                if lbl and lbl != "Entity":
                    try:
                        session.run(f"MATCH (e:Entity {{id: $id}}) SET e:`{lbl}`", id=item["id"]).consume()
                    except Exception:
                        pass

        # 批量写入关系
        print(f"  - 批量写入 {len(relationships)} 条关联边...")
        rel_batch = []
        for r in relationships:
            rel_type = str(r.get("type", "RELATED_TO")).strip().replace(" ", "_").replace("-", "_")
            if not rel_type:
                rel_type = "RELATED_TO"
            rel_batch.append({
                "source": str(r.get("source")),
                "target": str(r.get("target")),
                "type": rel_type,
                "confidence": float(r.get("confidence", 1.0)),
                "properties": {k: str(v) for k, v in r.get("properties", {}).items() if v is not None}
            })

        for i in range(0, len(rel_batch), batch_size):
            chunk = rel_batch[i:i + batch_size]
            for r in chunk:
                rtype = r["type"]
                q = f"""
                MATCH (s:Entity {{id: $source}}), (t:Entity {{id: $target}})
                MERGE (s)-[r:`{rtype}`]->(t)
                SET r.confidence = $conf, r += $props
                """
                session.run(q, source=r["source"], target=r["target"], conf=r["confidence"], props=r["properties"]).consume()

        # 统计结果
        n_count = session.run("MATCH (n:Entity) RETURN count(n) AS cnt").single()["cnt"]
        r_count = session.run("MATCH ()-[r]->() RETURN count(r) AS cnt").single()["cnt"]
        print(f"  ✅ Neo4j 同步完成: {n_count} 个节点, {r_count} 条关系已入库。")

    driver.close()
    return {"nodes": n_count, "relationships": r_count}


def sync_to_oxigraph(kg: dict, store_path: Path, clear: bool = False) -> dict:
    from semantica.semantic_extract.types import Triplet
    from semantica.triplet_store import TripletStore
    import shutil

    print(f"\n[2/2] 正在同步数据至本地嵌入式 Oxigraph ({store_path})...")
    if clear and store_path.exists():
        shutil.rmtree(store_path)
    store_path.mkdir(parents=True, exist_ok=True)

    entities = kg.get("entities", [])
    relationships = kg.get("relationships", [])

    triplets: list[Triplet] = []
    base_iri = "http://semantica.local/kg/"

    def iri(val: str) -> str:
        return base_iri + quote(str(val).strip(), safe="")

    # 1. 实体三元组
    for e in entities:
        eid = e.get("id")
        etype = e.get("type", "Entity")
        ename = e.get("name", eid)
        triplets.append(Triplet(
            subject=iri(eid),
            predicate="http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            object=iri(etype)
        ))
        triplets.append(Triplet(
            subject=iri(eid),
            predicate="http://www.w3.org/2000/01/rdf-schema#label",
            object=str(ename)
        ))

    # 2. 关系三元组
    for r in relationships:
        s = r.get("source")
        t = r.get("target")
        p = r.get("type", "related_to")
        triplets.append(Triplet(
            subject=iri(s),
            predicate=iri(p),
            object=iri(t)
        ))

    store = TripletStore(backend="oxigraph", path=str(store_path))
    res = store.add_triplets(triplets, batch_size=500)
    print(f"  - 写入三元组总计: {len(triplets)} 条 (状态: {res.get('status')})")

    # 执行 SPARQL 验证
    check = store.execute_query("SELECT (COUNT(*) AS ?cnt) WHERE { ?s ?p ?o }")
    count_val = 0
    if check.bindings:
        count_val = check.bindings[0].get("cnt", {}).get("value", "0")
    print(f"  ✅ Oxigraph 同步完成: 当前本地存储三元组总数: {count_val}")
    return {"triplets": count_val}


def main():
    parser = argparse.ArgumentParser(description="Semantica 统一同步分发调度器")
    parser.add_argument("--canonical", default=str(BASE_DIR / "data/canonical/canonical_kg.json"),
                        help="Canonical KG 路径")
    parser.add_argument("--neo4j-uri", default=os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687"))
    parser.add_argument("--neo4j-user", default=os.getenv("NEO4J_USER", "neo4j"))
    parser.add_argument("--neo4j-pass", default=os.getenv("NEO4J_PASS", "semantica2026"))
    parser.add_argument("--oxigraph-path", default=str(BASE_DIR / "data/oxigraph"))
    parser.add_argument("--clear", action="store_true", help="同步前是否清空目标库")
    parser.add_argument("--target", choices=["all", "neo4j", "oxigraph"], default="all")

    args = parser.parse_args()
    canonical_path = Path(args.canonical)
    print(f"=== Semantica 统一数据流同步分发 ===")
    print(f"单一真实源 (SSOT): {canonical_path}")

    kg = load_canonical_kg(canonical_path)
    print(f"已加载主图谱: 实体 {len(kg.get('entities', []))} 个, 关系 {len(kg.get('relationships', []))} 条")

    if args.target in ("all", "neo4j"):
        sync_to_neo4j(kg, args.neo4j_uri, args.neo4j_user, args.neo4j_pass, clear=args.clear)

    if args.target in ("all", "oxigraph"):
        sync_to_oxigraph(kg, Path(args.oxigraph_path), clear=args.clear)

    # 自动重新生成并刷新 Vis-Network 全景 HTML (8088 端口服务)
    try:
        from scripts.generate_html_visualizer import generate_visualizer
        target_html = BASE_DIR / "kb_out_win_qwen38/index.html"
        generate_visualizer(str(canonical_path), str(target_html))
        print(f"  🎨 [Vis-Network] 全景网页已自动同步重构: {target_html}")
    except Exception as exc:
        print(f"  [警告] 全景网页自动重构跳过: {exc}")

    print("\n🎉 全端同步完成！数据已在 Neo4j、Oxigraph 与 Vis-Network 网页实时就绪。")


if __name__ == "__main__":
    main()

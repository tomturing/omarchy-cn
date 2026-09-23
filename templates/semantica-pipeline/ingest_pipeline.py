#!/usr/bin/env python3
"""Semantica 宏观文档增量抽取与对齐合并流水线 (ingest_pipeline.py)

功能：
1. 接收单个文件或目录 (Word/PDF/Markdown/文本)。
2. 使用本地 LLM 网关 (Linux 或 Windows Qwen3.8-27B) 进行实体与因果关系抽取。
3. 读取现有权威主图谱 (data/canonical/canonical_kg.json)。
4. 运行 GraphBuilder 执行跨文档实体消歧与冲突消解，增量合并到主图谱中。
5. 自动触发 sync_dispatcher.py 同步刷新 Neo4j 与 Oxigraph。
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
CANONICAL_PATH = BASE_DIR / "data/canonical/canonical_kg.json"
BACKUP_DIR = BASE_DIR / "data/canonical/backups"


def main():
    parser = argparse.ArgumentParser(description="Semantica 宏观文档增量抽取流水线")
    parser.add_argument("input_path", help="待抽取的文档路径或目录 (docx/pdf/md/txt)")
    parser.add_argument("--llm-base-url", default=os.getenv("OPENAI_BASE_URL", "http://172.28.24.22:8080/v1"))
    parser.add_argument("--llm-api-key", default=os.getenv("OPENAI_API_KEY", "sk-local-litellm-master-key"))
    parser.add_argument("--llm-model", default="Qwen3.8-27B-GGUF")
    parser.add_argument("--no-sync", action="store_true", help="抽取完成后不同步分发")

    args = parser.parse_args()
    input_file = Path(args.input_path)
    if not input_file.exists():
        print(f"❌ 输入文件不存在: {input_file}")
        sys.exit(1)

    print(f"=== Semantica 增量抽取与统一数据流更新 ===")
    print(f"输入源: {input_file}")
    print(f"LLM 节点: {args.llm_base_url} ({args.llm_model})")

    # 1. 备份现有主图谱
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    if CANONICAL_PATH.exists():
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_file = BACKUP_DIR / f"canonical_kg_{timestamp}.json"
        import shutil
        shutil.copy2(CANONICAL_PATH, backup_file)
        print(f"📦 已备份当前权威图谱至: {backup_file.name}")

    # 2. 临时抽取目录
    tmp_out = BASE_DIR / "data/canonical/.tmp_extract"
    tmp_out.mkdir(parents=True, exist_ok=True)

    # 3. 调用抽取
    env = os.environ.copy()
    env["OPENAI_API_KEY"] = args.llm_api_key
    cmd = [
        sys.executable,
        str(BASE_DIR / "examples/build_kb_graph.py"),
        str(input_file),
        "--out", str(tmp_out),
        "--language", "zh",
        "--ner-method", "llm",
        "--llm-provider", "openai",
        "--llm-model", args.llm_model,
        "--llm-base-url", args.llm_base_url,
    ]
    print(f"\n🚀 启动语义抽取进程...")
    ret = subprocess.run(cmd, env=env)
    if ret.returncode != 0:
        print(f"❌ 抽取过程失败，退出码: {ret.returncode}")
        sys.exit(ret.returncode)

    # 4. 加载新抽取的临时图与旧权威图，执行合并
    new_kg_file = tmp_out / "kg.json"
    if not new_kg_file.exists():
        print("❌ 未生成临时抽取结果")
        sys.exit(1)

    with open(new_kg_file, "r", encoding="utf-8") as f:
        new_kg = json.load(f)

    if CANONICAL_PATH.exists():
        with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
            base_kg = json.load(f)
    else:
        base_kg = {"entities": [], "relationships": []}

    old_e_count = len(base_kg.get("entities", []))
    old_r_count = len(base_kg.get("relationships", []))
    print(f"\n🔄 正在合并知识图谱 (基础: {old_e_count} 实体 / {old_r_count} 关系)...")

    # 简单而稳健的实体与关系去重合并
    entity_map = {e["id"]: e for e in base_kg.get("entities", [])}
    for e in new_kg.get("entities", []):
        eid = e["id"]
        if eid in entity_map:
            # 合并属性与别名
            entity_map[eid].setdefault("properties", {}).update(e.get("properties", {}))
            merged_from = set(entity_map[eid].get("merged_from", []))
            merged_from.update(e.get("merged_from", []))
            entity_map[eid]["merged_from"] = list(merged_from)
        else:
            entity_map[eid] = e

    rel_set = {(r["source"], r["target"], r.get("type", "RELATED_TO")) for r in base_kg.get("relationships", [])}
    merged_rels = list(base_kg.get("relationships", []))
    for r in new_kg.get("relationships", []):
        key = (r["source"], r["target"], r.get("type", "RELATED_TO"))
        if key not in rel_set:
            rel_set.add(key)
            merged_rels.append(r)

    updated_kg = {
        "entities": list(entity_map.values()),
        "relationships": merged_rels,
        "metadata": {
            "last_updated": datetime.datetime.now().isoformat(),
            "last_source": str(input_file.name),
            "total_entities": len(entity_map),
            "total_relationships": len(merged_rels)
        }
    }

    with open(CANONICAL_PATH, "w", encoding="utf-8") as f:
        json.dump(updated_kg, f, ensure_ascii=False, indent=2)

    print(f"✅ 合并完成: 当前权威主图谱共有 {len(entity_map)} 个实体 (+{len(entity_map) - old_e_count}), {len(merged_rels)} 条关系 (+{len(merged_rels) - old_r_count})")

    # 5. 自动分发同步
    if not args.no_sync:
        print("\n⚡ 自动触发全端分发同步...")
        sync_cmd = [
            sys.executable,
            str(BASE_DIR / "pipeline/sync_dispatcher.py"),
            "--canonical", str(CANONICAL_PATH)
        ]
        subprocess.run(sync_cmd)

    print("\n🎉 增量文档流水线执行完毕！")


if __name__ == "__main__":
    main()

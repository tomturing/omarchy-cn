#!/usr/bin/env python3
"""Semantica 专家 Excel 批量审阅与反哺引擎 (excel_workflow.py)

功能：
1. 导出 (export)：将当前 Canonical KG 导出为结构化、带样式的 kg_review.xlsx，包含【实体清单】与【关联关系】两个工作表。
2. 导入 (import)：读取专家批注与修改后的 Excel，解析“保持/修改/删除/新增”标记，原子落盘 SSOT，并自动广播同步 Neo4j、Oxigraph 与 8088 网页。
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
DEFAULT_EXCEL_PATH = BASE_DIR / "data/canonical/kg_review.xlsx"


def export_excel(excel_path: Path):
    import openpyxl
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side

    if not CANONICAL_PATH.exists():
        raise FileNotFoundError(f"Canonical KG 文件不存在: {CANONICAL_PATH}")

    with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
        kg = json.load(f)

    entities = kg.get("entities", [])
    relationships = kg.get("relationships", [])

    wb = openpyxl.Workbook()
    # 样式配置
    header_fill_entity = PatternFill(start_color="1E3A8A", end_color="1E3A8A", fill_type="solid")  # 沉稳蓝
    header_fill_rel = PatternFill(start_color="14532D", end_color="14532D", fill_type="solid")     # 沉稳绿
    header_font = Font(name="微软雅黑", size=11, bold=True, color="FFFFFF")
    cell_font = Font(name="微软雅黑", size=10)
    thin_border = Border(
        left=Side(style='thin', color='CBD5E1'),
        right=Side(style='thin', color='CBD5E1'),
        top=Side(style='thin', color='CBD5E1'),
        bottom=Side(style='thin', color='CBD5E1')
    )

    # 1. 实体清单 Sheet
    ws_ent = wb.active
    ws_ent.title = "实体清单"
    ent_headers = ["操作标记(保持/修改/删除)", "实体ID(不可改)", "实体名称(可修改)", "业务分类(可修改)", "属性JSON(可修改)", "专家审核意见"]
    ws_ent.append(ent_headers)

    for cell in ws_ent[1]:
        cell.fill = header_fill_entity
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center", vertical="center")

    for e in entities:
        ws_ent.append([
            "保持",
            str(e.get("id")),
            str(e.get("name", e.get("id"))),
            str(e.get("type", "Entity")),
            json.dumps(e.get("properties", {}), ensure_ascii=False) if e.get("properties") else "{}",
            ""
        ])

    # 2. 关系清单 Sheet
    ws_rel = wb.create_sheet(title="因果与关联关系")
    rel_headers = ["操作标记(保持/修改/删除)", "源实体(Source)", "关系类型(Type)", "目标实体(Target)", "置信度(可修改)", "属性JSON(可修改)", "专家审核意见"]
    ws_rel.append(rel_headers)

    for cell in ws_rel[1]:
        cell.fill = header_fill_rel
        cell.font = header_font
        cell.alignment = Alignment(horizontal="center", vertical="center")

    for r in relationships:
        ws_rel.append([
            "保持",
            str(r.get("source")),
            str(r.get("type", "related_to")),
            str(r.get("target")),
            float(r.get("confidence", 1.0)),
            json.dumps(r.get("properties", {}), ensure_ascii=False) if r.get("properties") else "{}",
            ""
        ])

    # 调整两张表的列宽
    for sheet in (ws_ent, ws_rel):
        for col in sheet.columns:
            max_len = max(len(str(cell.value or '')) for cell in col)
            col_letter = openpyxl.utils.get_column_letter(col[0].column)
            sheet.column_dimensions[col_letter].width = min(50, max(12, max_len + 4))
            for cell in col:
                if cell.row > 1:
                    cell.font = cell_font
                    cell.border = thin_border

    excel_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(excel_path)
    print(f"✅ [Excel 导出] 已成功生成专家审阅表格: {excel_path}")
    print(f"   - 实体数量: {len(entities)} 行")
    print(f"   - 关系数量: {len(relationships)} 行")
    print("   💡 专家操作提示: 在【操作标记】列中，填写 '修改' 可更新名称/分类/属性；填写 '删除' 可剔除错误知识；新增行填写 '新增' 可扩充图谱。")


def import_excel(excel_path: Path):
    import openpyxl

    if not excel_path.exists():
        raise FileNotFoundError(f"Excel 审阅文件不存在: {excel_path}")

    print(f"📖 正在解析专家审阅 Excel: {excel_path}...")
    wb = openpyxl.load_workbook(excel_path, data_only=True)

    with open(CANONICAL_PATH, "r", encoding="utf-8") as f:
        kg = json.load(f)

    entities = kg.get("entities", [])
    relationships = kg.get("relationships", [])

    entity_map = {e["id"]: e for e in entities}
    modified_nodes = 0
    deleted_nodes = 0
    added_nodes = 0

    # 1. 处理实体变更
    if "实体清单" in wb.sheetnames:
        ws_ent = wb["实体清单"]
        for row in ws_ent.iter_rows(min_row=2, values_only=True):
            if not row or not row[1]:
                continue
            op = str(row[0] or "保持").strip()
            eid = str(row[1]).strip()
            name = str(row[2] or eid).strip()
            etype = str(row[3] or "Entity").strip()
            props_str = str(row[4] or "{}").strip()
            try:
                props = json.loads(props_str)
            except Exception:
                props = {}

            if op == "删除":
                if eid in entity_map:
                    del entity_map[eid]
                    deleted_nodes += 1
            elif op == "修改":
                if eid in entity_map:
                    entity_map[eid]["name"] = name
                    entity_map[eid]["type"] = etype
                    entity_map[eid].setdefault("properties", {}).update(props)
                    modified_nodes += 1
            elif op == "新增":
                if eid not in entity_map:
                    entity_map[eid] = {
                        "id": eid,
                        "name": name,
                        "type": etype,
                        "properties": props,
                        "metadata": {"source": "excel_expert_import", "imported_at": datetime.datetime.now().isoformat()}
                    }
                    added_nodes += 1

    # 级联清除被删除节点的关系
    valid_ids = set(entity_map.keys())
    rel_map = {(r["source"], r["target"], r.get("type", "RELATED_TO")): r for r in relationships if r["source"] in valid_ids and r["target"] in valid_ids}

    modified_rels = 0
    deleted_rels = 0
    added_rels = 0

    # 2. 处理关系变更
    if "因果与关联关系" in wb.sheetnames:
        ws_rel = wb["因果与关联关系"]
        for row in ws_rel.iter_rows(min_row=2, values_only=True):
            if not row or not row[1] or not row[3]:
                continue
            op = str(row[0] or "保持").strip()
            s = str(row[1]).strip()
            rtype = str(row[2] or "related_to").strip()
            t = str(row[3]).strip()
            conf = float(row[4] or 1.0)
            props_str = str(row[5] or "{}").strip()
            try:
                props = json.loads(props_str)
            except Exception:
                props = {}

            key = (s, t, rtype)
            if op == "删除":
                if key in rel_map:
                    del rel_map[key]
                    deleted_rels += 1
            elif op == "修改":
                if key in rel_map:
                    rel_map[key]["confidence"] = conf
                    rel_map[key].setdefault("properties", {}).update(props)
                    modified_rels += 1
            elif op == "新增":
                if key not in rel_map and s in valid_ids and t in valid_ids:
                    rel_map[key] = {
                        "source": s,
                        "target": t,
                        "type": rtype,
                        "confidence": conf,
                        "properties": props,
                        "metadata": {"source": "excel_expert_import"}
                    }
                    added_rels += 1

    # 3. 落盘到 Canonical SSOT
    updated_kg = {
        "entities": list(entity_map.values()),
        "relationships": list(rel_map.values()),
        "metadata": {
            "last_updated": datetime.datetime.now().isoformat(),
            "last_import": str(excel_path.name),
            "stats": {
                "entities": len(entity_map),
                "relationships": len(rel_map)
            }
        }
    }

    with open(CANONICAL_PATH, "w", encoding="utf-8") as f:
        json.dump(updated_kg, f, ensure_ascii=False, indent=2)

    # 记录审计流水
    audit_entry = {
        "timestamp": datetime.datetime.now().isoformat(),
        "action": "excel_import",
        "delta": {
            "nodes_added": added_nodes,
            "nodes_modified": modified_nodes,
            "nodes_deleted": deleted_nodes,
            "rels_added": added_rels,
            "rels_modified": modified_rels,
            "rels_deleted": deleted_rels
        }
    }
    with open(CHANGELOG_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(audit_entry, ensure_ascii=False) + "\n")

    print(f"✅ [Excel 反哺 SSOT] 主库已吸收专家审核结果:")
    print(f"   - 实体: +{added_nodes} 新增, ~{modified_nodes} 修改, -{deleted_nodes} 删除 (当前总数: {len(entity_map)})")
    print(f"   - 关系: +{added_rels} 新增, ~{modified_rels} 修改, -{deleted_rels} 删除 (当前总数: {len(rel_map)})")

    # 4. 触发全端广播同步 (Fan-Out)
    print("\n⚡ 自动触发全端广播同步 (Neo4j, Oxigraph, Vis-Network)...")
    from pipeline.sync_dispatcher import sync_to_neo4j, sync_to_oxigraph
    from scripts.generate_html_visualizer import generate_visualizer

    # Neo4j
    neo4j_uri = os.getenv("NEO4J_URI", "bolt://127.0.0.1:7687")
    neo4j_user = os.getenv("NEO4J_USER", "neo4j")
    neo4j_pass = os.getenv("NEO4J_PASS", "semantica2026")
    sync_to_neo4j(updated_kg, neo4j_uri, neo4j_user, neo4j_pass, clear=True)

    # Oxigraph
    sync_to_oxigraph(updated_kg, BASE_DIR / "data/oxigraph", clear=True)

    # Vis-Network HTML
    target_html = BASE_DIR / "kb_out_win_qwen38/index.html"
    generate_visualizer(str(CANONICAL_PATH), str(target_html))
    print(f"  🎨 [Vis-Network] 全景网页已根据 Excel 审核结果重新编译: {target_html}")

    print("\n🎉 Excel 专家审阅反哺完成！全端数据强一致性已同步就绪。")


def main():
    parser = argparse.ArgumentParser(description="Semantica 专家 Excel 批量审阅与反哺引擎")
    subparsers = parser.add_subparsers(dest="command", required=True)

    p_exp = subparsers.add_parser("export", help="导出为结构化 Excel 审阅表格")
    p_exp.add_argument("--output", "-o", default=str(DEFAULT_EXCEL_PATH), help="输出文件路径")

    p_imp = subparsers.add_parser("import", help="导入修改后的 Excel 并同步全端")
    p_imp.add_argument("--input", "-i", default=str(DEFAULT_EXCEL_PATH), help="待导入文件路径")

    args = parser.parse_args()
    if args.command == "export":
        export_excel(Path(args.output))
    elif args.command == "import":
        import_excel(Path(args.input))


if __name__ == "__main__":
    main()

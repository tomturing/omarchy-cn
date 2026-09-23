#!/usr/bin/env python3
"""Semantica 统一变更网关与全景 Web 服务 (api_server.py)

功能：
1. 提供 RESTful API (/api/node, /api/relationship, /api/stats) 支持浏览器前端实时增删改。
2. 内部直接联动 DataUnificationEngine (manage_kg.py)，确保修改写入 SSOT 并实时同步 Neo4j、Oxigraph 与本地文件。
3. 托管并服务 kb_out_win_qwen38 目录 (index.html)，使 8088 端口同时兼具“可视化大盘”与“专家交互编辑后台”。
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional

BASE_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BASE_DIR))

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from pipeline.manage_kg import (
    add_node,
    update_node,
    delete_node,
    add_rel,
    delete_rel,
    load_canonical
)

app = FastAPI(title="Semantica Unified KG Web & API Gateway", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ----------------- 数据模型 -----------------
class NodeCreateRequest(BaseModel):
    id: str
    name: Optional[str] = None
    type: Optional[str] = "Entity"
    properties: Optional[Dict[str, Any]] = None

class NodeUpdateRequest(BaseModel):
    id: str
    name: Optional[str] = None
    type: Optional[str] = None
    properties: Optional[Dict[str, Any]] = None

class RelCreateRequest(BaseModel):
    source: str
    target: str
    type: str = "related_to"
    confidence: float = 1.0
    properties: Optional[Dict[str, Any]] = None

class RelDeleteRequest(BaseModel):
    source: str
    target: str
    type: Optional[str] = ""

# ----------------- API 路由 -----------------
@app.get("/api/health")
def health():
    return {"status": "ok"}

@app.get("/api/stats")
def stats():
    kg = load_canonical()
    return {
        "entities_count": len(kg.get("entities", [])),
        "relationships_count": len(kg.get("relationships", [])),
        "last_updated": kg.get("metadata", {}).get("last_updated")
    }

@app.post("/api/node")
def create_node_endpoint(req: NodeCreateRequest):
    success = add_node(req.id, req.name or req.id, req.type or "Entity", req.properties or {}, sync=True)
    if not success:
        raise HTTPException(status_code=400, detail="Node already exists or invalid")
    return {"success": True, "message": f"Entity '{req.id}' created and synchronized across all backends"}

@app.put("/api/node")
def update_node_endpoint(req: NodeUpdateRequest):
    props = req.properties or {}
    if req.name:
        props["name"] = req.name
    if req.type:
        props["type"] = req.type
    success = update_node(req.id, props, sync=True)
    if not success:
        raise HTTPException(status_code=404, detail="Entity not found")
    return {"success": True, "message": f"Entity '{req.id}' updated and synchronized"}

@app.delete("/api/node/{node_id}")
def delete_node_endpoint(node_id: str):
    success = delete_node(node_id, sync=True)
    if not success:
        raise HTTPException(status_code=404, detail="Entity not found")
    return {"success": True, "message": f"Entity '{node_id}' cascade-deleted and synchronized"}

@app.post("/api/relationship")
def create_rel_endpoint(req: RelCreateRequest):
    success = add_rel(req.source, req.target, req.type, req.confidence, req.properties or {}, sync=True)
    if not success:
        raise HTTPException(status_code=400, detail="Failed to create relationship")
    return {"success": True, "message": f"Relationship ({req.source})->({req.target}) created and synchronized"}

@app.delete("/api/relationship")
def delete_rel_endpoint(req: RelDeleteRequest):
    success = delete_rel(req.source, req.target, req.type, sync=True)
    if not success:
        raise HTTPException(status_code=404, detail="Relationship not found")
    return {"success": True, "message": f"Relationship ({req.source})->({req.target}) deleted and synchronized"}

# ----------------- 静态托管 -----------------
STATIC_DIR = BASE_DIR / "kb_out_win_qwen38"
if STATIC_DIR.is_dir():
    @app.get("/")
    async def serve_index():
        return FileResponse(STATIC_DIR / "index.html")

    app.mount("/", StaticFiles(directory=str(STATIC_DIR), html=True), name="static")


def main():
    import uvicorn
    port = int(os.getenv("PORT", "8088"))
    print(f"🚀 启动 Semantica 统一变更网关与全景 Web: http://0.0.0.0:{port}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")


if __name__ == "__main__":
    main()

#!/usr/bin/env bash
# ==============================================================================
# Semantica 知识图谱服务综合启动与运维管理脚本
#
# 管理的服务：
# 1. Neo4j 生产图数据库 (端口 7474 Web / 7687 Bolt)
# 2. Semantica Explorer 官方交互工作台 (端口 8002)
# 3. Vis-Network 轻量级全景大盘 (端口 8088)
# ==============================================================================

set -euo pipefail

BASE_DIR="/home/tom/Projects/semantica"
VENV_PYTHON="${BASE_DIR}/.venv/bin/python"
CANONICAL_KG="${BASE_DIR}/data/canonical/canonical_kg.json"
STATIC_DIR="${BASE_DIR}/kb_out_win_qwen38"
LOG_DIR="${BASE_DIR}/logs"
PID_DIR="${BASE_DIR}/run"

mkdir -p "${LOG_DIR}" "${PID_DIR}"

start_neo4j() {
    echo "▶ [1/3] 检查并启动 Neo4j 容器 (semantica-neo4j)..."
    if docker ps --format '{{.Names}}' | grep -q "^semantica-neo4j$"; then
        echo "  - Neo4j 容器已在运行中。"
    elif docker ps -a --format '{{.Names}}' | grep -q "^semantica-neo4j$"; then
        echo "  - 启动已停止的 Neo4j 容器..."
        docker start semantica-neo4j
    else
        echo "  - 创建并启动全新 Neo4j 容器..."
        docker run -d \
            --name semantica-neo4j \
            --restart unless-stopped \
            -p 7474:7474 \
            -p 7687:7687 \
            -v "${BASE_DIR}/data/neo4j/data:/data" \
            -v "${BASE_DIR}/data/neo4j/logs:/logs" \
            -e NEO4J_AUTH="neo4j/semantica2026" \
            -e NEO4J_PLUGINS='["apoc"]' \
            -e NEO4J_dbms_memory_pagecache_size=2G \
            -e NEO4J_dbms_memory_heap_initial__size=2G \
            -e NEO4J_dbms_memory_heap_max__size=4G \
            neo4j:5.26-community
    fi
}

start_explorer() {
    echo "▶ [2/3] 启动 Semantica Explorer 官方工作台 (端口 8002)..."
    local pid_file="${PID_DIR}/explorer.pid"
    if [ -f "${pid_file}" ] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
        echo "  - Explorer 已在运行 (PID: $(cat "${pid_file}"))"
    else
        nohup env SEMANTICA_ALLOW_ANONYMOUS=true "${BASE_DIR}/.venv/bin/semantica-explorer" \
            --graph "${CANONICAL_KG}" \
            --host "0.0.0.0" \
            --port 8002 \
            --no-browser > "${LOG_DIR}/explorer.log" 2>&1 &
        echo $! > "${pid_file}"
        echo "  - Explorer 启动成功 (PID: $!) -> http://localhost:8002"
    fi
}

start_static_vis() {
    echo "▶ [3/3] 启动全景 Web 与专家交互网关 (端口 8088)..."
    local pid_file="${PID_DIR}/static_vis.pid"
    if [ -f "${pid_file}" ] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
        echo "  - 全景与交互 API 服务已在运行 (PID: $(cat "${pid_file}"))"
    else
        nohup "${BASE_DIR}/.venv/bin/python" "${BASE_DIR}/pipeline/api_server.py" > "${LOG_DIR}/api_server.log" 2>&1 &
        echo $! > "${pid_file}"
        echo "  - 全景与专家交互大盘启动成功 (PID: $!) -> http://localhost:8088"
    fi
}

stop_all() {
    echo "⏹ 正在停止图谱服务..."
    if [ -f "${PID_DIR}/explorer.pid" ]; then
        kill "$(cat "${PID_DIR}/explorer.pid")" 2>/dev/null || true
        rm -f "${PID_DIR}/explorer.pid"
        echo "  - 已停止 Semantica Explorer"
    fi
    if [ -f "${PID_DIR}/static_vis.pid" ]; then
        kill "$(cat "${PID_DIR}/static_vis.pid")" 2>/dev/null || true
        rm -f "${PID_DIR}/static_vis.pid"
        echo "  - 已停止 Vis-Network 静态全景"
    fi
    echo "  - 提示: Neo4j 容器未停止 (如需停止请执行: docker stop semantica-neo4j)"
}

status_all() {
    echo "=== Semantica 知识图谱服务运行状态 ==="
    echo -n "1. Neo4j (7474/7687): "
    if docker ps --format '{{.Names}}' | grep -q "^semantica-neo4j$"; then
        echo "RUNNING (http://localhost:7474)"
    else
        echo "STOPPED"
    fi

    echo -n "2. Semantica Explorer (8002): "
    if [ -f "${PID_DIR}/explorer.pid" ] && kill -0 "$(cat "${PID_DIR}/explorer.pid")" 2>/dev/null; then
        echo "RUNNING (PID $(cat "${PID_DIR}/explorer.pid") -> http://localhost:8002/docs)"
    else
        echo "STOPPED"
    fi

    echo -n "3. Vis-Network 全景 (8088): "
    if [ -f "${PID_DIR}/static_vis.pid" ] && kill -0 "$(cat "${PID_DIR}/static_vis.pid")" 2>/dev/null; then
        echo "RUNNING (PID $(cat "${PID_DIR}/static_vis.pid") -> http://localhost:8088/index.html)"
    else
        echo "STOPPED"
    fi
}

case "${1:-start}" in
    start)
        start_neo4j
        start_explorer
        start_static_vis
        echo ""
        status_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        start_neo4j
        start_explorer
        start_static_vis
        status_all
        ;;
    status)
        status_all
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

#!/usr/bin/env bash
# ==============================================================================
# reload_windows_q8.sh - Windows 22 节点 Unsloth Studio REST API 远程管理脚本
#
# 功能说明:
# 1. 远程热加载/重载 Qwen3.8-27B-GGUF (Q8_0 准无损)，动态注入 -b 8192 -ub 2048 极限批次参数
# 2. 查询远端推理服务状态与 GPU 显存负载
# 3. 释放模型显存 (unload)
#
# 架构原理:
# Unsloth Studio 基于 FastAPI 架构，通过 /api/inference/load 接收配置并拉起内部 llama-server，
# 其中 llama_extra_args 字段能够无缝透传底层高性能参数。
# ==============================================================================

set -euo pipefail

# 默认配置 (可通过环境变量覆盖)
WIN_HOST="${WIN_HOST:-172.28.24.22}"
WIN_PORT="${WIN_PORT:-8080}"
WIN_API_KEY="${WIN_API_KEY:-sk-unsloth-win22-masterkey}"
MODEL_PATH="${MODEL_PATH:-unsloth/Qwen3.8-27B-GGUF}"
GGUF_VARIANT="${GGUF_VARIANT:-Q8_0}"
MAX_SEQ_LEN="${MAX_SEQ_LEN:-131072}"
BATCH_SIZE="${BATCH_SIZE:-8192}"
UBATCH_SIZE="${UBATCH_SIZE:-2048}"

BASE_URL="http://${WIN_HOST}:${WIN_PORT}"

usage() {
    cat <<EOF
用法: $0 [load|status|unload|health]

子命令:
  load    (默认) 远程热加载/重载模型并注入 -b ${BATCH_SIZE} -ub ${UBATCH_SIZE}
  status  查询当前推理引擎加载状态与配置
  system  查询 Windows 远端系统状态 (CPU/内存/GPU 显存)
  unload  卸载当前模型并释放显存
  health  快速探活接口

环境变量:
  WIN_HOST       目标 Windows IP (默认: 172.28.24.22)
  WIN_PORT       服务端口 (默认: 8080)
  WIN_API_KEY    Unsloth Master Key
  BATCH_SIZE     批处理大小 (默认: 8192)
  UBATCH_SIZE    微批处理大小 (默认: 2048)

示例:
  $0 load
  WIN_API_KEY="your-token" $0 status
EOF
}

cmd="${1:-load}"

check_curl() {
    if ! command -v curl &>/dev/null; then
        echo "错误: 未找到 curl 工具，请先安装。" >&2
        exit 1
    fi
}

do_status() {
    echo "==> 查询 Windows 22 推理服务状态..."
    curl -sS -X GET "${BASE_URL}/api/inference/status" \
        -H "Authorization: Bearer ${WIN_API_KEY}" \
        -H "Accept: application/json" | jq . || true
}

do_system() {
    echo "==> 查询 Windows 22 系统资源状态..."
    curl -sS -X GET "${BASE_URL}/api/system/status" \
        -H "Authorization: Bearer ${WIN_API_KEY}" \
        -H "Accept: application/json" | jq . || true
}

do_health() {
    echo "==> 探活检测: ${BASE_URL}/api/inference/status"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/api/inference/status" \
        -H "Authorization: Bearer ${WIN_API_KEY}" || echo "000")
    if [ "${http_code}" = "200" ]; then
        echo "✅ 远端服务正常响应 (HTTP 200)"
    else
        echo "❌ 远端服务异常 (HTTP ${http_code})，请检查 Windows 防火墙或服务是否拉起。"
        exit 1
    fi
}

do_unload() {
    echo "==> 正在卸载 Windows 22 上的模型..."
    curl -sS -X POST "${BASE_URL}/api/inference/unload" \
        -H "Authorization: Bearer ${WIN_API_KEY}" \
        -H "Content-Type: application/json" | jq . || true
    echo "✅ 卸载完成，显存已释放。"
}

do_load() {
    echo "==> 开始向 Windows 22 (${BASE_URL}) 发送热重载指令..."
    echo "    - 模型路径: ${MODEL_PATH}"
    echo "    - 量化版本: ${GGUF_VARIANT}"
    echo "    - 上下文: ${MAX_SEQ_LEN}"
    echo "    - 批处理参数: -b ${BATCH_SIZE} -ub ${UBATCH_SIZE}"

    PAYLOAD=$(cat <<EOF
{
  "model_path": "${MODEL_PATH}",
  "gguf_variant": "${GGUF_VARIANT}",
  "max_seq_length": ${MAX_SEQ_LEN},
  "cache_type_k": "q4_0",
  "cache_type_v": "q4_0",
  "gpu_memory_mode": "manual",
  "gpu_layers": 99,
  "llama_extra_args": [
    "-b", "${BATCH_SIZE}",
    "-ub", "${UBATCH_SIZE}"
  ]
}
EOF
)

    response=$(curl -sS -w "\nHTTP_STATUS_CODE:%{http_code}" -X POST "${BASE_URL}/api/inference/load" \
        -H "Authorization: Bearer ${WIN_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "${PAYLOAD}")

    body=$(echo "${response}" | sed -e '$d')
    code=$(echo "${response}" | tail -n 1 | cut -d':' -f2)

    if [ "${code}" = "200" ]; then
        echo "✅ 模型热重载成功 (HTTP 200)！"
        echo "${body}" | jq . 2>/dev/null || echo "${body}"
    else
        echo "❌ 热重载失败 (HTTP ${code})："
        echo "${body}"
        exit 1
    fi
}

check_curl

case "${cmd}" in
    load)
        do_load
        ;;
    status)
        do_status
        ;;
    system)
        do_system
        ;;
    health)
        do_health
        ;;
    unload)
        do_unload
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "未知子命令: ${cmd}" >&2
        usage
        exit 1
        ;;
esac

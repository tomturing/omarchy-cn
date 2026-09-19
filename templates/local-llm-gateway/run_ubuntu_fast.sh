#!/usr/bin/env bash
# ==============================================================================
# run_ubuntu_fast.sh - 节点 1 (Ubuntu 22.04) 极速响应嘴启动脚本
# 硬件要求: Xeon 6244 (锁频 4.4GHz) + Quadro RTX 8000 (48GB)
# 核心外挂: MTP 多 Token 投机预测 (--spec-type draft-mtp --spec-draft-n-max 2)
# 性能指标: TTFT 0.15 秒，生成速度 75 ~ 88 tokens/s
# ==============================================================================

set -euo pipefail

MODEL_PATH="/home/sangfor/models/Qwen3.8-27B-Q4_K_M.gguf"
PORT=8888
HOST="0.0.0.0"

echo "=== 优化宿主机 CPU 调频 (锁定 Performance) ==="
if command -v cpupower >/dev/null 2>&1; then
    sudo cpupower frequency-set -g performance >/dev/null || true
fi

echo "=== 启动 Ubuntu 极速 MTP 投机推理服务 (Port: ${PORT}) ==="
exec llama-server \
  --model "${MODEL_PATH}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --ctx-size 32768 \
  --gpu-layers 999 \
  --flash-attn on \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --spec-type draft-mtp \
  --spec-draft-n-max 6 \
  -t 8 \
  -tb 14 \
  -b 2048 \
  -ub 512

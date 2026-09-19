#!/usr/bin/env bash
# ==============================================================================
# run_omarchy_256k.sh - 节点 3 (Omarchy Arch Linux) 256K 满血长文本启动脚本
# 硬件要求: Quadro RTX 8000 (48GB) + 64GB 内存
# 显存核算: 模型 Q4_K_M (16GB) + 256K Q4 KV Cache (16GB) + 缓冲 (3GB) = 35GB (剩余 13GB)
# ==============================================================================

set -euo pipefail

MODEL_PATH="/opt/models/Qwen3.8-27B-Q4_K_M.gguf"
PORT=9999
HOST="0.0.0.0"

echo "=== 启动 Omarchy 256K 满血超长文本推理服务 (Port: ${PORT}) ==="

# 确保大页内存开启
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    echo always | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null || true
fi

exec llama-server \
  --model "${MODEL_PATH}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --ctx-size 262144 \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  --gpu-layers 999 \
  --flash-attn on \
  --cont-batching \
  -t 8 \
  -tb 14 \
  -b 2048 \
  -ub 512

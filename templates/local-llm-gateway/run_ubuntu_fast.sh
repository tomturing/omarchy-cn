#!/usr/bin/env bash
# ==============================================================================
# run_ubuntu_fast.sh - 节点 1 (Ubuntu 22.04) 极速响应嘴启动脚本
# 运行环境: Unsloth Studio (Ubuntu 原生)
# 硬件要求: Xeon 6244 + Quadro RTX 8000 (48GB)
# 核心机制: 原生 Auto MTP 投机加速 (内置 blk.64.nextn 预测层)
# 上下文规格: 128K (131,072 Tokens), Q4_0 KV Cache
# 实测性能: 生成速度 41.79 tokens/s, 显存占用 19.3 GB (余量 28.8 GB)
# ==============================================================================

set -e

export PATH="/home/sangfor/.unsloth/studio/unsloth_studio/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/home/sangfor/.local/bin"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:"
export CUDA_VISIBLE_DEVICES=0

exec /home/sangfor/.unsloth/studio/unsloth_studio/bin/unsloth studio run \
  --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf \
  --speculative-type auto \
  -H 0.0.0.0 \
  -p 8888 \
  --parallel 1 \
  --max-seq-length 131072 \
  --gpu-memory-mode manual \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 99 \
  -t 8 \
  -tb 16 \
  -b 2048 \
  -ub 512

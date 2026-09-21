#!/usr/bin/env bash
# ==============================================================================
# run_omarchy_256k.sh - 节点 3 (Omarchy Arch Linux) 256K 满血长文本启动脚本
# 运行环境: Unsloth Studio (Arch Linux 官方最佳实践原生安装)
# 硬件要求: Quadro RTX 8000 (48GB) + 64GB 内存
# 核心机制: 原生 Auto MTP 投机加速 (内置 blk.64.nextn 预测层)
# 上下文规格: 256K (262,144 Tokens 满血), Q4_0 KV Cache
# 实测性能: 生成速度 40.32 tokens/s (短文本峰值 59.35 t/s), 显存占用 22.9 GB (余量 25.2 GB)
# ==============================================================================

set -e

export PATH="/home/sangfor/.local/bin:/home/sangfor/.unsloth/studio/unsloth_studio/bin:/opt/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/bin:/home/sangfor/.local/bin"
export LD_LIBRARY_PATH="/opt/cuda/lib64:"
export CUDA_VISIBLE_DEVICES=0

exec /home/sangfor/.local/bin/unsloth studio run \
  --model /home/sangfor/models/Qwen3.8-27B-UD-Q4_K_M.gguf \
  --speculative-type auto \
  -H 0.0.0.0 \
  -p 8888 \
  --parallel 1 \
  --max-seq-length 262144 \
  --gpu-memory-mode manual \
  --cache-type-k q4_0 \
  --cache-type-v q4_0 \
  -ngl 99 \
  -t 8 \
  -tb 16 \
  -b 2048 \
  -ub 512

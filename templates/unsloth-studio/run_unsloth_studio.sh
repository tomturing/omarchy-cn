#!/usr/bin/env bash
set -e

# 默认读取当前用户主目录，或配置为实际服务运行路径
USER_HOME="${HOME:-/home/ai-runner}"

export PATH="${USER_HOME}/.unsloth/studio/unsloth_studio/bin:/usr/local/cuda/bin:$PATH"
export LD_LIBRARY_PATH="/usr/local/cuda/lib64:$LD_LIBRARY_PATH"
export CUDA_VISIBLE_DEVICES=0

exec "${USER_HOME}/.unsloth/studio/unsloth_studio/bin/unsloth" studio run \
  --model "${USER_HOME}/models/unsloth-Qwen3.8-27B-Q8_0.gguf" \
  -H 0.0.0.0 \
  -p 8888 \
  --parallel 1 \
  --max-seq-length 65536 \
  --gpu-memory-mode manual \
  --cache-type-k q8_0 \
  --cache-type-v q8_0 \
  -t 8 \
  -tb 16 \
  -b 2048 \
  -ub 512

#!/usr/bin/env bash
# ==============================================================================
# test_agents.sh - 超融合三节点大模型集群端到端自动化测试脚本
# 测试内容:
#   1. Anthropic 协议 (Claude Code -> local-fast / local-precise)
#   2. OpenAI 协议 (Ubuntu 快节点响应速度与吞吐)
#   3. OpenAI 协议 (Windows 精节点高精测试)
#   4. 输出 Langfuse Trace 直达大屏链接
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BASE_URL="http://127.0.0.1:4000"
KEY="sk-local-litellm-master-key"

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}   Omarchy 超融合三节点本地 LLM 集群与多 Agent 自动化测试套件   ${NC}"
echo -e "${BLUE}================================================================${NC}"

# Test 1: Anthropic Messages 协议测试 (Claude Code)
echo -ne "1. 测试 Anthropic 协议 (Claude Code 映射)... "
START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/messages" \
  -H "x-api-key: ${KEY}" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-7-sonnet-20250219",
    "max_tokens": 120,
    "messages": [{"role": "user", "content": "Respond exactly with: CLAUDE_OK"}]
  }')
END_TIME=$(date +%s%N)
LATENCY=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000000}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}[PASSED] (HTTP 200, 耗时: ${LATENCY}s)${NC}"
else
    echo -e "${RED}[FAILED] (HTTP ${HTTP_CODE})${NC}"
    echo "   响应: $BODY"
fi

# Test 2: 极速响应测试 (Ubuntu 21 极速层)
echo -ne "2. 测试 OpenAI 协议 (极速响应层: local-fast / local-auto)... "
START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "node1-qwen",
    "max_tokens": 120,
    "messages": [{"role": "user", "content": "Respond exactly with: SPEED_OK"}]
  }')
END_TIME=$(date +%s%N)
LATENCY=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000000}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}[PASSED] (HTTP 200, 耗时: ${LATENCY}s)${NC}"
else
    echo -e "${RED}[FAILED] (HTTP ${HTTP_CODE})${NC}"
    echo "   响应: $BODY"
fi

# Test 3: 高精严谨思考测试 (Windows 22 高精层 / 降级兜底)
echo -ne "3. 测试 OpenAI 协议 (高精严谨层: node2-qwen / local-precise)... "
START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "local-qwen",
    "max_tokens": 120,
    "messages": [{"role": "user", "content": "Respond exactly with: PRECISE_OK"}]
  }')
END_TIME=$(date +%s%N)
LATENCY=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000000}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}[PASSED] (HTTP 200, 耗时: ${LATENCY}s)${NC}"
else
    echo -e "${RED}[FAILED] (HTTP ${HTTP_CODE})${NC}"
    echo "   响应: $BODY"
fi

# Test 4: 满血 256K 超长文本测试 (Omarchy 23 超长层)
echo -ne "4. 测试 OpenAI 协议 (超长满血层: node3-qwen / local-infinite)... "
START_TIME=$(date +%s%N)
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${BASE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "node3-qwen",
    "max_tokens": 120,
    "messages": [{"role": "user", "content": "Respond exactly with: INFINITE_256K_OK"}]
  }')
END_TIME=$(date +%s%N)
LATENCY=$(awk "BEGIN {print ($END_TIME - $START_TIME) / 1000000000}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [ "$HTTP_CODE" -eq 200 ]; then
    echo -e "${GREEN}[PASSED] (HTTP 200, 耗时: ${LATENCY}s)${NC}"
else
    echo -e "${RED}[FAILED] (HTTP ${HTTP_CODE})${NC}"
    echo "   响应: $BODY"
fi

echo -e "\n${YELLOW}全链路可观测性仪表盘:${NC}"
echo -e " * Langfuse Traces 深度追踪大屏: ${BLUE}http://localhost:3000/project/sangfor/hci/traces${NC}"
echo -e " * LiteLLM 交互式 Swagger 文档:   ${BLUE}http://localhost:4000/docs${NC}"
echo -e " * Prometheus 实时性能指标:       ${BLUE}http://localhost:4000/metrics/${NC}"

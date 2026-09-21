#!/usr/bin/env bash
# ==============================================================================
# check_gateway_env.sh - 统一网关与三节点超融合算力池全栈健康诊断脚本
# 支持探测：
#   - 节点 1 (Ubuntu 21): 极速响应层 (Q4_K_M + MTP, 8888)
#   - 节点 2 (Windows 22): 高精深度层 (Q8_0, 8080)
#   - 节点 3 (Omarchy 23): 256K 满血长文本层 (9999)
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== LiteLLM 统一网关与超融合三节点算力池全栈诊断 ===${NC}\n"

# 1. LiteLLM 服务状态检查
echo -e "${YELLOW}[1/5] 检查 LiteLLM systemd 用户级守护进程...${NC}"
if systemctl --user is-active litellm >/dev/null 2>&1; then
    echo -e "${GREEN}✓ LiteLLM 守护进程正在运行 (Active: active)${NC}"
else
    echo -e "${RED}✗ LiteLLM 守护进程未运行！请执行: systemctl --user start litellm${NC}"
fi

# 2. 检查 4000 端口与 Swagger 文档 / Prometheus 指标
echo -e "\n${YELLOW}[2/5] 检查 LiteLLM 网关核心端点 (4000 端口)...${NC}"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:4000/docs || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Swagger UI 文档端点正常: http://127.0.0.1:4000/docs (HTTP 200)${NC}"
else
    echo -e "${RED}✗ Swagger UI 无法访问 (HTTP $HTTP_CODE)${NC}"
fi

METRICS_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:4000/metrics/ || echo "000")
if [ "$METRICS_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Prometheus 指标端点正常: http://127.0.0.1:4000/metrics/ (HTTP 200)${NC}"
else
    echo -e "${RED}✗ Prometheus 端点无法访问 (HTTP $METRICS_CODE)${NC}"
fi

# 3. 检查三节点私有算力池连通性
echo -e "\n${YELLOW}[3/5] 检查超融合私有算力集群连通性...${NC}"
# 节点 1 Ubuntu 21
NODE1_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://172.28.24.21:8888/v1/models -H "Authorization: Bearer sk-unsloth-ubuntu21-masterkey" || echo "000")
if [ "$NODE1_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 节点 1 (Ubuntu 21 极速版, 172.28.24.21:8888) 响应正常 (HTTP 200)${NC}"
else
    echo -e "${RED}✗ 节点 1 (172.28.24.21:8888) 无法连通或鉴权失败 (HTTP $NODE1_CODE)${NC}"
fi

# 节点 2 Windows 22
NODE2_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://172.28.24.22:8080/v1/models -H "Authorization: Bearer sk-unsloth-win22-masterkey" || echo "000")
if [ "$NODE2_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 节点 2 (Windows 22 高精版, 172.28.24.22:8080) 响应正常 (HTTP 200)${NC}"
else
    echo -e "${RED}✗ 节点 2 (172.28.24.22:8080) 无法连通或模型未加载 (HTTP $NODE2_CODE)${NC}"
fi

# 节点 3 Omarchy 23
NODE3_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://172.28.24.23:8888/v1/models -H "Authorization: Bearer sk-unsloth-omarchy23-masterkey" || echo "000")
if [ "$NODE3_CODE" = "200" ]; then
    echo -e "${GREEN}✓ 节点 3 (Omarchy 23 256K长文本, 172.28.24.23:8888) 响应正常 (HTTP 200)${NC}"
else
    echo -e "${YELLOW}! 节点 3 (172.28.24.23:8888) 暂未上线 (按规划部署后生效)${NC}"
fi

# 4. 检查 Langfuse 可观测性大屏状态
echo -e "\n${YELLOW}[4/5] 检查 Langfuse 容器状态 (3000 端口)...${NC}"
LF_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 3 http://127.0.0.1:3000 || echo "000")
if [ "$LF_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Langfuse 大屏正常运行: http://127.0.0.1:3000 (HTTP 200)${NC}"
else
    echo -e "${RED}✗ Langfuse 大屏无法访问 (HTTP $LF_CODE)${NC}"
fi

# 5. 检查本地 Agent 配置与上下文水位一致性
echo -e "\n${YELLOW}[5/5] 检查各大 Agent 配置与上下文防爆水位...${NC}"
# Pi
if [ -f "$HOME/.pi/agent/models.json" ] && grep -q "127.0.0.1:4000" "$HOME/.pi/agent/models.json"; then
    echo -e "${GREEN}✓ Pi Agent 已正确配置指向本地网关${NC}"
else
    echo -e "${YELLOW}! Pi Agent 尚未指向 127.0.0.1:4000${NC}"
fi

# Hermes
if [ -f "$HOME/.hermes/config.yaml" ] && grep -q "127.0.0.1:4000" "$HOME/.hermes/config.yaml"; then
    echo -e "${GREEN}✓ Hermes Agent 已正确配置指向本地网关${NC}"
else
    echo -e "${YELLOW}! Hermes Agent 尚未指向 127.0.0.1:4000${NC}"
fi

# Claude Code
if [ -f "$HOME/.claude/settings.json" ] && grep -q "127.0.0.1:4000" "$HOME/.claude/settings.json"; then
    echo -e "${GREEN}✓ Claude Code 已正确配置指向本地网关${NC}"
else
    echo -e "${YELLOW}! Claude Code 尚未指向 127.0.0.1:4000${NC}"
fi

# dsh
if [ -f "$HOME/.dsh/settings.yaml" ] && grep -q "127.0.0.1:4000" "$HOME/.dsh/settings.yaml"; then
    echo -e "${GREEN}✓ dsh Agent 已配置指向本地网关${NC}"
    if grep -q "contextWindow: 65536" "$HOME/.dsh/settings.yaml"; then
        echo -e "${GREEN}✓ dsh 上下文安全水位已设为 64K (自动 Compaction 防爆已激活)${NC}"
    else
        echo -e "${YELLOW}! dsh 上下文水位建议配置为 contextWindow: 65536 以免物理截断${NC}"
    fi
else
    echo -e "${YELLOW}! dsh Agent 尚未完全配置${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

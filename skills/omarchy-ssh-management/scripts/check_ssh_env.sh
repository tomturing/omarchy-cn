#!/bin/bash
# ==============================================================================
# Omarchy SSH & WindTerm 环境诊断脚本
# ==============================================================================

set -u

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy SSH 运维与终端环境诊断 ===${NC}\n"

# 1. 检测 sshs 是否安装
if command -v sshs >/dev/null 2>&1; then
    SSHS_VER=$(sshs --version 2>&1 | head -n 1)
    echo -e " [${GREEN}PASS${NC}] sshs 已安装: ${SSHS_VER}"
else
    echo -e " [${RED}FAIL${NC}] 未安装 sshs (可通过 'sudo pacman -S sshs' 安装)"
fi

# 2. 检测 ~/.local/bin/ssh-manager 启动脚本
SSH_MGR="$HOME/.local/bin/ssh-manager"
if [ -x "$SSH_MGR" ]; then
    echo -e " [${GREEN}PASS${NC}] ssh-manager 启动脚本存在且具备可执行权限: ${SSH_MGR}"
else
    echo -e " [${RED}FAIL${NC}] ssh-manager 脚本不存在或无执行权限 (~/.local/bin/ssh-manager)"
fi

# 3. 检测 Hyprland 浮动规则
RULES_FILE="$HOME/.config/hypr/windowrules.lua"
if [ -f "$RULES_FILE" ] && grep -q "sshs-floating" "$RULES_FILE"; then
    echo -e " [${GREEN}PASS${NC}] Hyprland 已配置 sshs-floating 居中浮动规则"
else
    echo -e " [${RED}FAIL${NC}] Hyprland 缺少 sshs-floating 浮动规则 (在 ~/.config/hypr/windowrules.lua)"
fi

# 4. 检测 Hyprland 快捷键与解绑配置
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS_FILE" ]; then
    HAS_UNBIND=false
    HAS_BIND=false
    if grep -q 'hl\.unbind.*SUPER.*SHIFT.*RETURN' "$BINDINGS_FILE"; then
        HAS_UNBIND=true
    fi
    if grep -q 'SUPER + SHIFT + RETURN.*ssh-manager' "$BINDINGS_FILE"; then
        HAS_BIND=true
    fi

    if [ "$HAS_UNBIND" = true ] && [ "$HAS_BIND" = true ]; then
        echo -e " [${GREEN}PASS${NC}] 快捷键 Super+Shift+Enter 已正确解绑默认浏览器并绑定至 ssh-manager"
    elif [ "$HAS_BIND" = true ] && [ "$HAS_UNBIND" = false ]; then
        echo -e " [${YELLOW}WARN${NC}] 快捷键已绑定但未发现 hl.unbind 解绑！按下时可能同时唤醒系统默认浏览器"
    else
        echo -e " [${RED}FAIL${NC}] 未在 bindings.lua 中发现 Super+Shift+Enter -> ssh-manager 的配置"
    fi
fi

# 5. 检测 ~/.bashrc 中针对 WindTerm 的 OSC 3008 拦截
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ] && grep -q "__systemd_osc_context_precmdline" "$BASHRC"; then
    echo -e " [${GREEN}PASS${NC}] ~/.bashrc 已配置针对 WindTerm 的 OSC 3008 转义拦截补丁"
else
    echo -e " [${YELLOW}WARN${NC}] ~/.bashrc 尚未配置 WindTerm OSC 3008 拦截，若使用 WindTerm 可能会出现提示符乱码"
fi

# 6. 检测 ~/.ssh/config 是否存在
if [ -f "$HOME/.ssh/config" ]; then
    HOST_COUNT=$(grep -c -E "^Host[[:space:]]+" "$HOME/.ssh/config" || true)
    echo -e " [${GREEN}INFO${NC}] ~/.ssh/config 存在，已定义 ${HOST_COUNT} 个 Host 节点"
else
    echo -e " [${YELLOW}WARN${NC}] ~/.ssh/config 不存在，sshs 将无法检索到预设的主机列表"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

#!/bin/bash
# ==============================================================================
# 修复 WindTerm 下 systemd OSC 3008 提示符乱码脚本
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

BASHRC="$HOME/.bashrc"

echo -e "${BLUE}=== 配置 WindTerm systemd OSC 3008 乱码拦截补丁 ===${NC}"

if [ ! -f "$BASHRC" ]; then
    touch "$BASHRC"
fi

if grep -q "__systemd_osc_context_precmdline" "$BASHRC"; then
    echo -e " [${GREEN}OK${NC}] $BASHRC 中已存在 OSC 3008 拦截代码，无需重复添加"
else
    echo -e "正在向 $BASHRC 追加针对 WindTerm 的细粒度转义拦截规则..."
    cat << 'BASHRC_EOF' >> "$BASHRC"

# 仅针对 WindTerm 细粒度拦截 systemd OSC 3008 上下文转义序列（避免提示乱码）
if [ "$TERM_PROGRAM" = "WindTerm" ] || [ -n "$WINDTERM_SESSION" ]; then
    __systemd_osc_context_precmdline() { :; }
    __systemd_osc_context_ps0() { :; }
    unset systemd_osc_context_cmd_id systemd_osc_context_shell_id
    PS0=""
fi
BASHRC_EOF
    echo -e " [${GREEN}OK${NC}] 补丁追加成功！新开的 WindTerm 会话将不再出现 3008;... 乱码字符。"
fi

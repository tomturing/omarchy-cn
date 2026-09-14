#!/bin/bash
# ==============================================================================
# 一键安装与配置 Omarchy SSH 天花板组合 (sshs + Foot + Hyprland 浮动规则)
# ==============================================================================

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${BLUE}=== 开始配置 Omarchy SSH 天花板组合 ===${NC}"

# 1. 安装 extra/sshs
if ! command -v sshs >/dev/null 2>&1; then
    echo -e "正在通过 pacman 安装 sshs..."
    sudo pacman -S --needed --noconfirm sshs
else
    echo -e " [${GREEN}OK${NC}] sshs 已经安装"
fi

# 2. 部署 ~/.local/bin/ssh-manager
mkdir -p "$HOME/.local/bin"
SSH_MGR="$HOME/.local/bin/ssh-manager"
cat << 'MGR_EOF' > "$SSH_MGR"
#!/bin/bash
# 启动原生 Wayland foot 终端作为 Spotlight 居中弹窗，执行 sshs 会话管理器
foot --app-id=sshs-floating --title="SSH Sessions" sshs
MGR_EOF
chmod +x "$SSH_MGR"
echo -e " [${GREEN}OK${NC}] 已部署启动脚本至 $SSH_MGR"

# 3. 配置 Hyprland 浮动窗口规则
RULES_FILE="$HOME/.config/hypr/windowrules.lua"
if [ -f "$RULES_FILE" ]; then
    if ! grep -q "sshs-floating" "$RULES_FILE"; then
        echo -e "正在向 $RULES_FILE 追加 sshs-floating 居中浮动规则..."
        cat << 'RULE_EOF' >> "$RULES_FILE"

-- SSH 会话管理器 (sshs) Spotlight 居中浮动窗口规则
o.window("sshs-floating", {
  float = true,
  center = true,
  size = { 960, 600 },
})
RULE_EOF
        echo -e " [${GREEN}OK${NC}] 浮动窗口规则已追加"
    else
        echo -e " [${GREEN}OK${NC}] $RULES_FILE 中已存在 sshs-floating 规则"
    fi
fi

# 4. 配置 Hyprland 快捷键（带解绑）
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS_FILE" ]; then
    if ! grep -q "SUPER + SHIFT + RETURN.*ssh-manager" "$BINDINGS_FILE"; then
        echo -e "正在向 $BINDINGS_FILE 绑定 Super+Shift+Enter 快捷键..."
        cat << 'BIND_EOF' >> "$BINDINGS_FILE"

-- 解绑系统默认浏览器快捷键并绑定 SSH Spotlight 会话管理器
hl.unbind("SUPER + SHIFT + RETURN")
o.bind("SUPER + SHIFT + RETURN", "SSH Sessions", { launch = "ssh-manager" })
BIND_EOF
        echo -e " [${GREEN}OK${NC}] 快捷键已绑定"
    else
        echo -e " [${GREEN}OK${NC}] $BINDINGS_FILE 中已存在 ssh-manager 快捷键绑定"
    fi
fi

# 5. 重新加载 Hyprland
if command -v hyprctl >/dev/null 2>&1; then
    echo -e "重新加载 Hyprland 配置..."
    hyprctl reload config-only >/dev/null 2>&1 || true
    echo -e " [${GREEN}OK${NC}] Hyprland 配置已重载"
fi

echo -e "\n${GREEN}=== 安装与配置完成！===${NC}"
echo -e "现在您可以随时按下 ${YELLOW}Super + Shift + Enter${NC} 呼出 SSH Spotlight 窗口！"

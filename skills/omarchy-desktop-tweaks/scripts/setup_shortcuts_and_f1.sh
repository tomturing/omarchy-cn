#!/usr/bin/env bash
# 一键配置 Omarchy 实用高频快捷键与 F1 Tensaku 批注截图
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(cd "$SCRIPT_DIR/../../../templates" && pwd)"

echo "=== 开始配置 Omarchy 高频快捷键与 F1 截图标注 ==="

# 1. 部署 Tensaku 批注截图执行脚本与配置
echo "-> [1/3] 部署 ~/.local/bin/tensaku-capture 与 Tensaku 配置 ..."
mkdir -p "$HOME/.local/bin"
cp "$TEMPLATES_DIR/tensaku-capture.sh" "$HOME/.local/bin/tensaku-capture"
chmod +x "$HOME/.local/bin/tensaku-capture"

TENSAKU_CONF="$HOME/.config/tensaku/config.toml"
mkdir -p "$(dirname "$TENSAKU_CONF")"
if [ ! -f "$TENSAKU_CONF" ]; then
    cat > "$TENSAKU_CONF" << 'EOF'
[general]
annotation-size-factor = 2.0
early-exit = true
EOF
elif ! grep -q "early-exit" "$TENSAKU_CONF"; then
    if grep -q "\[general\]" "$TENSAKU_CONF"; then
        sed -i '/\[general\]/a early-exit = true' "$TENSAKU_CONF"
    else
        echo -e "\n[general]\nearly-exit = true" >> "$TENSAKU_CONF"
    fi
fi
echo "   [OK] tensaku-capture 与配置部署完成（已启用复制后自动退出）"

# 2. 写入 ~/.config/hypr/local.lua 按键绑定
echo "-> [2/3] 配置 ~/.config/hypr/local.lua 快捷键绑定 ..."
LOCAL_LUA="$HOME/.config/hypr/local.lua"
mkdir -p "$(dirname "$LOCAL_LUA")"
touch "$LOCAL_LUA"

if ! grep -q "tensaku-capture" "$LOCAL_LUA"; then
    cat >> "$LOCAL_LUA" << 'EOF'

-- Tensaku's own capture overlay on F1: drag a region, Space snaps to
-- the window under the pointer, F takes the whole screen, S switches to
-- a scrolling capture. Replaces Omarchy's grim+slurp omarchy-capture-screenshot.
hl.unbind("F1")
o.bind("F1", "Screenshot", (os.getenv("HOME") or "") .. "/.local/bin/tensaku-capture")
EOF
    echo "   [OK] F1 快捷键已写入 $LOCAL_LUA"
else
    echo "   [OK] F1 快捷键此前已配置"
fi

# 检查 bindings.lua 是否包含 Super+A 与 Super+B
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS_LUA" ]; then
    if ! grep -q "SUPER + A" "$BINDINGS_LUA"; then
        echo 'o.bind("SUPER + A", "Antigravity", { launch = "antigravity" })' >> "$BINDINGS_LUA"
    fi
    if ! grep -q "SUPER + B" "$BINDINGS_LUA"; then
        echo 'o.bind("SUPER + B", "Browser", { omarchy = "browser" })' >> "$BINDINGS_LUA"
    fi
fi

# 3. 重载 Hyprland 配置
echo "-> [3/3] 执行 hyprctl reload 重载桌面按键 ..."
if command -v hyprctl >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
    echo "   [OK] 快捷键已实时生效"
fi

echo -e "\n✅ 快捷键与 F1 截图标注配置完成！按 F1 即可体验现代拖拽框选、空格吸附窗口与就地批注功能。"

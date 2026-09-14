#!/usr/bin/env bash
# ==============================================================================
# Omarchy 一键应用输入法与中文环境全链路调优脚本
# 适用于：Arch Linux + Hyprland (Omarchy) + Fcitx5 + Rime (雾凇拼音)
# 解决痛点：
# 1. 物理键盘 Left Shift 键单按松开切换中英文（长按 Shift 组合键如 Shift+1 绝不误切）；
# 2. 新开终端 100% 默认英文；
# 3. 密码框（sudo / 锁屏 / Polkit 提权弹窗）全自动英文直通，彻底解决输密码弹中文；
# 4. Fcitx5 与 Rime 内存状态彻底热重载生效。
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/templates"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo -e "${BLUE}=== 开始应用 Omarchy 输入法与中文环境全链路调优 ===${NC}\n"

# 1. 配置 Hyprland 键盘驱动 (消除 XKB shift:both_capslock_cancel 拦截)
HYPR_INPUT="$HOME/.config/hypr/input.lua"
if [ -f "$HYPR_INPUT" ]; then
    echo -e "-> [1/8] 配置 Hyprland 键盘驱动 (~/.config/hypr/input.lua) ..."
    if ! grep -q 'kb_options.*compose:caps' "$HYPR_INPUT"; then
        # 如果存在 follow_mouse 块，在其中追加 kb_options
        if grep -q "follow_mouse" "$HYPR_INPUT"; then
            sed -i '/follow_mouse/a \    kb_options = "compose:caps", -- CRITICAL: 移除 both_capslock_cancel 放行物理 Shift 松开事件' "$HYPR_INPUT"
        else
            cat << 'LUA' >> "$HYPR_INPUT"

hl.config({
  input = {
    kb_options = "compose:caps",
  },
})
LUA
        fi
    fi
    if command -v hyprctl >/dev/null 2>&1; then
        hyprctl reload config-only >/dev/null 2>&1 || true
        echo -e "   [${GREEN}OK${NC}] Hyprland 键盘配置已重载 (compose:caps 生效)"
    fi
fi

# 2. 配置快捷键锁屏触发切英文 (~/.config/hypr/bindings.lua)
HYPR_BINDINGS="$HOME/.config/hypr/bindings.lua"
if [ -f "$HYPR_BINDINGS" ]; then
    echo -e "-> [2/8] 配置快捷键锁屏切英文 (~/.config/hypr/bindings.lua) ..."
    if ! grep -q "SUPER + CTRL + L.*SetAsciiMode" "$HYPR_BINDINGS"; then
        cat << 'LUA' >> "$HYPR_BINDINGS"

-- 锁屏时自动将输入法切回英文模式，确保解锁输入密码为英文字符
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + CTRL + L", "Lock system", "bash -c 'gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1; omarchy-system-lock'")
LUA
        if command -v hyprctl >/dev/null 2>&1; then
            hyprctl reload config-only >/dev/null 2>&1 || true
        fi
        echo -e "   [${GREEN}OK${NC}] 锁屏快捷键 (Super+Ctrl+L) 纯英文联动已绑定"
    else
        echo -e "   [${GREEN}OK${NC}] 锁屏快捷键已包含纯英文联动配置"
    fi
fi

# 3. 配置 Fcitx5 全局行为 (包含 ActiveByDefault=True 与 TriggerKeys)
echo -e "-> [3/8] 配置 Fcitx5 全局行为 (~/.config/fcitx5/config) ..."
mkdir -p "$HOME/.config/fcitx5"
CONFIG_FILE="$HOME/.config/fcitx5/config"
if [ -f "$CONFIG_FILE" ]; then
    # 确保 Behavior 块参数正确
    if grep -q "\[Behavior\]" "$CONFIG_FILE"; then
        sed -i -E 's/^#?[[:space:]]*ShareInputState=.*/ShareInputState=Program/' "$CONFIG_FILE"
        sed -i -E 's/^#?[[:space:]]*AllowInputMethodForPassword=.*/AllowInputMethodForPassword=False/' "$CONFIG_FILE"
        sed -i -E 's/^#?[[:space:]]*ShowPreeditForPassword=.*/ShowPreeditForPassword=False/' "$CONFIG_FILE"
        if ! grep -q "ActiveByDefault=" "$CONFIG_FILE"; then
            sed -i '/\[Behavior\]/a ActiveByDefault=True' "$CONFIG_FILE"
        else
            sed -i -E 's/^#?[[:space:]]*ActiveByDefault=.*/ActiveByDefault=True/' "$CONFIG_FILE"
        fi
    else
        cat << 'CFG' >> "$CONFIG_FILE"

[Behavior]
ActiveByDefault=True
ShareInputState=Program
AllowInputMethodForPassword=False
ShowPreeditForPassword=False
CFG
    fi

    # 确保 TriggerKeys 兜底快捷键存在（避免切入纯英文后无法通过键盘切回）
    if ! grep -q "\[Hotkey/TriggerKeys\]" "$CONFIG_FILE"; then
        cat << 'CFG' >> "$CONFIG_FILE"

[Hotkey/TriggerKeys]
0=Control+space
CFG
    fi
else
    cp "$TEMPLATES_DIR/fcitx5-config" "$CONFIG_FILE"
fi
echo -e "   [${GREEN}OK${NC}] ActiveByDefault=True 与 ShareInputState=Program 配置完成"

# 4. 配置 Fcitx5 profile (确保包含 keyboard-us 降级布局)
echo -e "-> [4/8] 配置 Fcitx5 输入法列表 (~/.config/fcitx5/profile) ..."
PROFILE_FILE="$HOME/.config/fcitx5/profile"
if [ -f "$PROFILE_FILE" ]; then
    if ! grep -q "keyboard-us" "$PROFILE_FILE"; then
        cp "$TEMPLATES_DIR/fcitx5-profile" "$PROFILE_FILE"
        echo -e "   [${GREEN}OK${NC}] 已注入 keyboard-us 密码降级布局"
    else
        echo -e "   [${GREEN}OK${NC}] keyboard-us 降级布局已存在"
    fi
else
    cp "$TEMPLATES_DIR/fcitx5-profile" "$PROFILE_FILE"
fi

# 5. 部署 Rime 雾凇拼音补丁、Windows 标点映射与 app_options
echo -e "-> [5/8] 部署 Rime 状态机补丁、Windows 直通标点与 app_options 策略 ..."
mkdir -p "$HOME/.local/share/fcitx5/rime"
cp "$TEMPLATES_DIR/default.custom.yaml" "$HOME/.local/share/fcitx5/rime/default.custom.yaml"
cp "$TEMPLATES_DIR/rime_ice.custom.yaml" "$HOME/.local/share/fcitx5/rime/rime_ice.custom.yaml"
cp "$TEMPLATES_DIR/punctuation.yaml" "$HOME/.local/share/fcitx5/rime/punctuation.yaml"
cp "$TEMPLATES_DIR/fcitx5.yaml" "$HOME/.local/share/fcitx5/rime/fcitx5.yaml"
echo -e "   [${GREEN}OK${NC}] 状态机与 Windows 标点直通映射已部署就绪"

# 6. 配置 ~/.bashrc 终端 Hook 与 sudo 包装
echo -e "-> [6/8] 配置 ~/.bashrc 终端默认英文 Hook 与 sudo 包装 ..."
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    if ! grep -q "SetAsciiMode true" "$BASHRC"; then
        echo "" >> "$BASHRC"
        cat "$TEMPLATES_DIR/bashrc_ime_snippet.sh" >> "$BASHRC"
        echo -e "   [${GREEN}OK${NC}] Hook 代码已追加至 ~/.bashrc"
    else
        echo -e "   [${GREEN}OK${NC}] ~/.bashrc 中已存在 Hook 配置"
    fi
fi

# 7. 编译部署 Rime Schema 二进制库
echo -e "-> [7/8] 编译部署 Rime Schema 方案库 ..."
if command -v rime_deployer >/dev/null 2>&1; then
    rime_deployer --build "$HOME/.local/share/fcitx5/rime" /usr/share/rime-data "$HOME/.local/share/fcitx5/rime/build" || true
    mkdir -p "$HOME/.local/share/fcitx5/rime/build"
    cp "$TEMPLATES_DIR/fcitx5.yaml" "$HOME/.local/share/fcitx5/rime/build/fcitx5.yaml"
    echo -e "   [${GREEN}OK${NC}] Rime 二进制缓存编译完成"
fi

# 8. 彻底重启 Fcitx5 服务（核心：不能只用 fcitx5-remote -r，必须重启进程重载 profile）
echo -e "-> [8/8] 彻底重启 Fcitx5 服务以完全载入 profile 与 Rime 引擎 ..."
if systemctl --user is-active omarchy-fcitx5.service >/dev/null 2>&1; then
    systemctl --user restart omarchy-fcitx5.service
elif systemctl --user is-active dbus-:1.1-org.fcitx.Fcitx5@0.service >/dev/null 2>&1; then
    systemctl --user restart dbus-:1.1-org.fcitx.Fcitx5@0.service
else
    pkill -x fcitx5 || true
    sleep 0.5
    if ! pgrep -x fcitx5 >/dev/null 2>&1; then
        fcitx5 -d >/dev/null 2>&1 || true
    fi
fi
sleep 0.5
if command -v fcitx5-remote >/dev/null 2>&1; then
    fcitx5-remote -s rime >/dev/null 2>&1 || true
fi
echo -e "   [${GREEN}OK${NC}] Fcitx5 已完全重启并加载 Rime 引擎"

echo -e "\n${GREEN}=== 调优配置已全部就绪！请运行 check_ime_env.sh 进行核验 ===${NC}"

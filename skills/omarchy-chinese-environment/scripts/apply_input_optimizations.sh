#!/usr/bin/env bash
# Omarchy 一键应用输入法与中文环境调优脚本
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
TEMPLATES_DIR="$REPO_DIR/templates"

echo "=== 开始应用 Omarchy 输入法与中文环境调优 ==="

# 1. 配置 Fcitx5 全局配置
echo "-> 配置 ~/.config/fcitx5/config ..."
mkdir -p "$HOME/.config/fcitx5"
if [ -f "$HOME/.config/fcitx5/config" ]; then
    sed -i -E 's/^#?[[:space:]]*ShareInputState=.*/ShareInputState=Program/' "$HOME/.config/fcitx5/config"
    sed -i -E 's/^#?[[:space:]]*AllowInputMethodForPassword=.*/AllowInputMethodForPassword=False/' "$HOME/.config/fcitx5/config"
    sed -i -E 's/^#?[[:space:]]*ShowPreeditForPassword=.*/ShowPreeditForPassword=False/' "$HOME/.config/fcitx5/config"
else
    cat << 'CFG' > "$HOME/.config/fcitx5/config"
[Behavior]
ShareInputState=Program
AllowInputMethodForPassword=False
ShowPreeditForPassword=False
CFG
fi

# 2. 配置 Fcitx5 profile 确保包含 keyboard-us
echo "-> 配置 ~/.config/fcitx5/profile ..."
if [ -f "$HOME/.config/fcitx5/profile" ]; then
    if ! grep -q "keyboard-us" "$HOME/.config/fcitx5/profile"; then
        cp "$TEMPLATES_DIR/fcitx5-profile" "$HOME/.config/fcitx5/profile"
    fi
else
    cp "$TEMPLATES_DIR/fcitx5-profile" "$HOME/.config/fcitx5/profile"
fi

# 3. 部署 Rime 补丁
echo "-> 部署 Rime 雾凇拼音补丁与 app_options ..."
mkdir -p "$HOME/.local/share/fcitx5/rime"
cp "$TEMPLATES_DIR/default.custom.yaml" "$HOME/.local/share/fcitx5/rime/default.custom.yaml"
cp "$TEMPLATES_DIR/rime_ice.custom.yaml" "$HOME/.local/share/fcitx5/rime/rime_ice.custom.yaml"
cp "$TEMPLATES_DIR/fcitx5.yaml" "$HOME/.local/share/fcitx5/rime/fcitx5.yaml"

# 4. 追加 ~/.bashrc 终端 Hook 与 sudo 包装
echo "-> 配置 ~/.bashrc 终端 Hook ..."
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    if ! grep -q "SetAsciiMode true" "$BASHRC"; then
        echo "" >> "$BASHRC"
        cat "$TEMPLATES_DIR/bashrc_ime_snippet.sh" >> "$BASHRC"
    fi
fi

# 5. 编译部署 Rime 二进制
echo "-> 编译部署 Rime Schema 方案库 ..."
if command -v rime_deployer >/dev/null 2>&1; then
    rime_deployer --build "$HOME/.local/share/fcitx5/rime" /usr/share/rime-data "$HOME/.local/share/fcitx5/rime/build" || true
    mkdir -p "$HOME/.local/share/fcitx5/rime/build"
    cp "$TEMPLATES_DIR/fcitx5.yaml" "$HOME/.local/share/fcitx5/rime/build/fcitx5.yaml"
fi

# 6. 重启输入法服务
echo "-> 重新加载 Fcitx5 服务 ..."
if command -v fcitx5-remote >/dev/null 2>&1; then
    fcitx5-remote -r || true
fi

echo "=== 调优配置已全部就绪！请运行 check_ime_env.sh 进行核验 ==="

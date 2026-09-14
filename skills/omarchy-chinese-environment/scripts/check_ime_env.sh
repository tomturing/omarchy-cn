#!/usr/bin/env bash
# Omarchy 中文环境与输入法诊断脚本
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy 中文环境与 Fcitx5/Rime 状态诊断 ===${NC}\n"

# 1. 检查物理键盘 XKB 规则
echo -n "[1/5] 检查 XKB 键盘驱动配置 (both_capslock_cancel 检查)... "
KB_OPT=$(hyprctl getoption input:kb_options 2>/dev/null | grep "str:" || true)
if [[ "$KB_OPT" == *"both_capslock_cancel"* ]]; then
    echo -e "${RED}[FAIL] 发现冲突项 shift:both_capslock_cancel！该项会吞掉物理 Shift 键松开事件。${NC}"
else
    echo -e "${GREEN}[PASS] 物理按键放行正常 (${KB_OPT})${NC}"
fi

# 2. 检查 Fcitx5 状态隔离与密码保护
echo -n "[2/5] 检查 Fcitx5 全局状态隔离与密码框保护配置... "
CONFIG_FILE="$HOME/.config/fcitx5/config"
if [ -f "$CONFIG_FILE" ]; then
    SHARE_STATE=$(grep -E "^ShareInputState=" "$CONFIG_FILE" || true)
    PWD_PROTECT=$(grep -E "^AllowInputMethodForPassword=" "$CONFIG_FILE" || true)
    if [[ "$SHARE_STATE" == *"Program"* ]] && [[ "$PWD_PROTECT" == *"False"* ]]; then
        echo -e "${GREEN}[PASS] ShareInputState=Program 且 AllowInputMethodForPassword=False${NC}"
    else
        echo -e "${YELLOW}[WARN] 配置未完全就绪 (ShareInputState: $SHARE_STATE, AllowInputMethodForPassword: $PWD_PROTECT)${NC}"
    fi
else
    echo -e "${RED}[FAIL] 未找到 $CONFIG_FILE${NC}"
fi

# 3. 检查 Fcitx5 输入法列表 (keyboard-us 降级布局检查)
echo -n "[3/5] 检查 Fcitx5 输入法列表中是否包含 keyboard-us 降级布局... "
PROFILE_FILE="$HOME/.config/fcitx5/profile"
if [ -f "$PROFILE_FILE" ]; then
    if grep -q "keyboard-us" "$PROFILE_FILE"; then
        echo -e "${GREEN}[PASS] 已包含 keyboard-us，密码框可自动降级纯英文${NC}"
    else
        echo -e "${RED}[FAIL] 列表中缺少 keyboard-us！密码框将无法降级纯英文而报错或弹中文${NC}"
    fi
else
    echo -e "${YELLOW}[WARN] 未找到 $PROFILE_FILE${NC}"
fi

# 4. 检查 Rime 状态机补丁
echo -n "[4/5] 检查 Rime 雾凇拼音 Shift 松开切换补丁... "
RIME_CUSTOM="$HOME/.local/share/fcitx5/rime/default.custom.yaml"
if [ -f "$RIME_CUSTOM" ]; then
    if grep -q "ascii_composer/switch_key/Shift_L" "$RIME_CUSTOM"; then
        echo -e "${GREEN}[PASS] ascii_composer 状态机补丁已就绪${NC}"
    else
        echo -e "${YELLOW}[WARN] 缺少 ascii_composer 状态机补丁${NC}"
    fi
else
    echo -e "${YELLOW}[WARN] 未找到 $RIME_CUSTOM${NC}"
fi

# 5. 检查 ~/.bashrc 终端 Hook 与密码包装
echo -n "[5/5] 检查 ~/.bashrc 终端英文 Hook 与 sudo 包装... "
BASHRC="$HOME/.bashrc"
if [ -f "$BASHRC" ]; then
    if grep -q "SetAsciiMode true" "$BASHRC" && grep -q "__pwd_cmd in sudo" "$BASHRC"; then
        echo -e "${GREEN}[PASS] 终端默认英文 Hook 与 sudo 密码包装均已配置${NC}"
    else
        echo -e "${YELLOW}[WARN] ~/.bashrc 缺少终端英文 Hook 或 sudo 包装${NC}"
    fi
else
    echo -e "${RED}[FAIL] 未找到 $BASHRC${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

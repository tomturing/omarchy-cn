#!/usr/bin/env bash
# ==============================================================================
# Omarchy 中文环境与输入法全链路诊断脚本
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy 中文环境与 Fcitx5/Rime 状态全链路诊断 ===${NC}\n"

# 1. 检查物理键盘 XKB 规则
echo -n "[1/8] 检查 XKB 键盘驱动配置 (both_capslock_cancel 检查)... "
KB_OPT=$(hyprctl getoption input:kb_options 2>/dev/null | grep "str:" || true)
if [[ "$KB_OPT" == *"both_capslock_cancel"* ]]; then
    echo -e "${RED}[FAIL] 发现冲突项 shift:both_capslock_cancel！该项会吞掉物理 Shift 键松开事件。${NC}"
else
    echo -e "${GREEN}[PASS] 物理按键放行正常 (${KB_OPT})${NC}"
fi

# 2. 检查 Fcitx5 状态隔离与密码保护与默认激活
echo -n "[2/8] 检查 Fcitx5 全局状态隔离、密码框保护与 ActiveByDefault... "
CONFIG_FILE="$HOME/.config/fcitx5/config"
if [ -f "$CONFIG_FILE" ]; then
    SHARE_STATE=$(grep -E "^ShareInputState=" "$CONFIG_FILE" || true)
    PWD_PROTECT=$(grep -E "^AllowInputMethodForPassword=" "$CONFIG_FILE" || true)
    ACTIVE_BY_DEF=$(grep -E "^ActiveByDefault=" "$CONFIG_FILE" || true)
    if [[ "$SHARE_STATE" == *"Program"* ]] && [[ "$PWD_PROTECT" == *"False"* ]] && [[ "$ACTIVE_BY_DEF" == *"True"* ]]; then
        echo -e "${GREEN}[PASS] ShareInputState=Program, AllowInputMethodForPassword=False, ActiveByDefault=True${NC}"
    else
        echo -e "${YELLOW}[WARN] 配置未完全就绪 (ShareInputState: $SHARE_STATE, AllowPassword: $PWD_PROTECT, ActiveByDefault: $ACTIVE_BY_DEF)${NC}"
    fi
else
    echo -e "${RED}[FAIL] 未找到 $CONFIG_FILE${NC}"
fi

# 3. 检查 Fcitx5 TriggerKeys 兜底快捷键
echo -n "[3/8] 检查 Fcitx5 TriggerKeys 兜底激活热键... "
if [ -f "$CONFIG_FILE" ]; then
    if grep -q "\[Hotkey/TriggerKeys\]" "$CONFIG_FILE" || grep -E -q "^TriggerKeys=[^[:space:]]+" "$CONFIG_FILE"; then
        echo -e "${GREEN}[PASS] 已配置 TriggerKeys 兜底快捷键，不会发生英文锁死${NC}"
    else
        echo -e "${YELLOW}[WARN] TriggerKeys 为空，若切入纯英文可能无法通过键盘切回${NC}"
    fi
else
    echo -e "${RED}[FAIL] 未找到 $CONFIG_FILE${NC}"
fi

# 4. 检查 Fcitx5 输入法列表 (keyboard-us 降级布局检查)
echo -n "[4/8] 检查 Fcitx5 输入法列表中是否包含 keyboard-us 降级布局... "
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

# 5. 检查 Rime 状态机补丁与 app_options 隔离
echo -n "[5/8] 检查 Rime 雾凇拼音 Shift 松开切换补丁与 Schema 纯净度... "
RIME_CUSTOM="$HOME/.local/share/fcitx5/rime/default.custom.yaml"
if [ -f "$RIME_CUSTOM" ]; then
    HAS_SHIFT=$(grep -E -q "ascii_composer/switch_key/Shift_L" "$RIME_CUSTOM" && echo "yes" || echo "no")
    HAS_ROGUE_APP=$(grep -E -q "^[[:space:]]*\"?app_options" "$RIME_CUSTOM" && echo "yes" || echo "no")
    if [ "$HAS_SHIFT" = "yes" ] && [ "$HAS_ROGUE_APP" = "no" ]; then
        echo -e "${GREEN}[PASS] ascii_composer 状态机已就绪，且无硬编码 app_options 锁死问题${NC}"
    elif [ "$HAS_SHIFT" = "yes" ] && [ "$HAS_ROGUE_APP" = "yes" ]; then
        echo -e "${YELLOW}[WARN] 状态机已配置，但 default.custom.yaml 中包含 app_options，可能导致部分窗口被硬锁英文${NC}"
    else
        echo -e "${YELLOW}[WARN] 缺少 ascii_composer 状态机补丁${NC}"
    fi
else
    echo -e "${YELLOW}[WARN] 未找到 $RIME_CUSTOM${NC}"
fi

# 6. 检查标点符号映射是否对齐 Windows（顿号、书名号、人民币符号直通上屏）
echo -n "[6/8] 检查中文标点符号映射（Windows 体验：、》￥ 直接上屏，不弹候选）... "
PUNCT_FILE="$HOME/.local/share/fcitx5/rime/punctuation.yaml"
if [ -f "$PUNCT_FILE" ] && grep -q "'\\\\' : { commit: 、 }" "$PUNCT_FILE"; then
    echo -e "${GREEN}[PASS] 已配置 punctuation.yaml，标点符号单按直接上屏${NC}"
else
    echo -e "${YELLOW}[WARN] 缺少定制 punctuation.yaml，输入顿号或书名号将弹出多选项候选框${NC}"
fi

# 7. 检查 ~/.bashrc 终端 Hook 与密码包装
echo -n "[7/8] 检查 ~/.bashrc 终端英文 Hook 与 sudo 包装... "
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

# 8. 检查 Fcitx5 进程运行与输入法激活状态
echo -n "[8/8] 检查 Fcitx5 守护进程与输入法激活状态... "
if pgrep -x fcitx5 >/dev/null 2>&1; then
    CURRENT_IM=$(fcitx5-remote -n 2>/dev/null || true)
    REMOTE_STATE=$(fcitx5-remote 2>/dev/null || true)
    HAS_RIME=$(gdbus call --session --dest org.fcitx.Fcitx5 --object-path /controller --method org.fcitx.Fcitx.Controller1.InputMethodGroupInfo "Default" 2>/dev/null | grep -o "'rime'" || true)
    if [ "$CURRENT_IM" = "rime" ] || [ -n "$HAS_RIME" ]; then
        echo -e "${GREEN}[PASS] Fcitx5 守护进程正常运行 (主方案: rime, 状态码: ${REMOTE_STATE:-1})${NC}"
    else
        echo -e "${YELLOW}[WARN] Fcitx5 运行中，但方案列表中未找到 rime${NC}"
    fi
else
    echo -e "${RED}[FAIL] Fcitx5 守护进程未在运行！${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

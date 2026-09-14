#!/usr/bin/env bash
# Omarchy 桌面调优、快捷键、F1 截图与顶栏网速全链路诊断脚本
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy 桌面调优与组件状态全链路诊断 ===${NC}\n"

# 1. 检查 Tensaku 截图工具与包装脚本
echo -n "[1/7] 检查 Tensaku 截图工具二进制程序... "
if command -v tensaku >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] Tensaku 程序已安装 ($(which tensaku))${NC}"
else
    echo -e "${RED}[FAIL] 未找到 tensaku 程序！请运行 sudo pacman -S tensaku${NC}"
fi

# 2. 检查 ~/.local/bin/tensaku-capture
echo -n "[2/7] 检查 F1 截图包装器 (~/.local/bin/tensaku-capture)... "
CAPTURE_SCRIPT="$HOME/.local/bin/tensaku-capture"
if [ -x "$CAPTURE_SCRIPT" ]; then
    echo -e "${GREEN}[PASS] 包装脚本存在且具备执行权限${NC}"
else
    echo -e "${RED}[FAIL] 缺失 $CAPTURE_SCRIPT 或无执行权限${NC}"
fi

# 3. 检查 F1 截图标注快捷键绑定
echo -n "[3/7] 检查 F1 截图标注快捷键生效状态... "
LOCAL_LUA="$HOME/.config/hypr/local.lua"
if [ -f "$LOCAL_LUA" ] && grep -q "tensaku-capture" "$LOCAL_LUA"; then
    echo -e "${GREEN}[PASS] F1 截图快捷键已在 $LOCAL_LUA 声明生效${NC}"
else
    echo -e "${YELLOW}[WARN] 未在 $LOCAL_LUA 检测到 tensaku-capture 绑定${NC}"
fi

# 4. 检查常用高频应用快捷键 (Super+A / Super+B)
echo -n "[4/7] 检查常用高频快捷键 (Super+A 开发环境 / Super+B 浏览器)... "
BINDINGS_LUA="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS_LUA" ] && grep -q "SUPER + A" "$BINDINGS_LUA" && grep -q "SUPER + B" "$BINDINGS_LUA"; then
    echo -e "${GREEN}[PASS] Super+A 与 Super+B 已就绪${NC}"
else
    echo -e "${YELLOW}[WARN] 快捷键尚未全部绑定 (可在 bindings.lua 中按需补充)${NC}"
fi

# 5. 检查 local.netspeed 插件目录与文件
echo -n "[5/7] 检查顶部栏 local.netspeed 插件工程文件... "
PLUGIN_DIR="$HOME/.config/omarchy/plugins/local.netspeed"
if [ -f "$PLUGIN_DIR/manifest.json" ] && [ -x "$PLUGIN_DIR/netspeed.sh" ] && [ -f "$PLUGIN_DIR/NetSpeed.qml" ]; then
    echo -e "${GREEN}[PASS] manifest.json, netspeed.sh 与 NetSpeed.qml 均已就绪${NC}"
else
    echo -e "${RED}[FAIL] 插件文件不完整或 netspeed.sh 无执行权限${NC}"
fi

# 6. 验证流量采集脚本实时输出
echo -n "[6/7] 验证流量无损采集器 (netspeed.sh) 输出质量... "
if [ -x "$PLUGIN_DIR/netspeed.sh" ]; then
    SAMPLE_JSON=$(timeout 2s bash "$PLUGIN_DIR/netspeed.sh" 2>/dev/null | head -n 1 || true)
    if [[ "$SAMPLE_JSON" == "{"* ]] && [[ "$SAMPLE_JSON" == *"down"* ]] && [[ "$SAMPLE_JSON" == *"up"* ]]; then
        echo -e "${GREEN}[PASS] 成功捕获真实流量流 ($SAMPLE_JSON)${NC}"
    else
        echo -e "${YELLOW}[WARN] 未能即时读取到规范 JSON 流${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 脚本不可执行，跳过输出测试${NC}"
fi

# 7. 检查 shell.json 居中网速布局
echo -n "[7/7] 检查 ~/.config/omarchy/shell.json 顶栏居中布局... "
SHELL_JSON="$HOME/.config/omarchy/shell.json"
if [ -f "$SHELL_JSON" ] && grep -q '"local.netspeed"' "$SHELL_JSON"; then
    echo -e "${GREEN}[PASS] local.netspeed 已纳入 shell.json 布局流${NC}"
else
    echo -e "${RED}[FAIL] 未在 $SHELL_JSON 中声明 local.netspeed${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

#!/usr/bin/env bash
# Voxtype 离线语音输入识别 7 维度全链路诊断脚本
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Voxtype 离线语音输入状态全链路诊断 ===${NC}\n"

# 1. 检查 voxtype-vulkan 二进制
echo -n "[1/7] 检查 Vulkan 硬件加速二进制 (/usr/lib/voxtype/voxtype-vulkan)... "
if [ -x "/usr/lib/voxtype/voxtype-vulkan" ]; then
    echo -e "${GREEN}[PASS] voxtype-vulkan 存在且具备执行权限${NC}"
else
    echo -e "${RED}[FAIL] 缺失 /usr/lib/voxtype/voxtype-vulkan，请安装 voxtype-bin${NC}"
fi

# 2. 检查 Whisper 模型文件
echo -n "[2/7] 检查 Whisper Small 普通话离线模型... "
MODEL_FILE="$HOME/.local/share/voxtype/models/ggml-small.bin"
if [ -f "$MODEL_FILE" ] && [ "$(stat -c%s "$MODEL_FILE")" -gt 400000000 ]; then
    echo -e "${GREEN}[PASS] 模型文件存在且完整 ($(du -h "$MODEL_FILE" | cut -f1))${NC}"
else
    echo -e "${RED}[FAIL] 缺失模型或文件不完整 ($MODEL_FILE)${NC}"
fi

# 3. 检查 config.toml 配置 (mode=paste, model=small, language=zh)
echo -n "[3/7] 检查 ~/.config/voxtype/config.toml 核心配置参数... "
CONFIG_FILE="$HOME/.config/voxtype/config.toml"
if [ -f "$CONFIG_FILE" ]; then
    HAS_SMALL=$(grep -E '^[[:space:]]*model[[:space:]]*=[[:space:]]*"small"' "$CONFIG_FILE" || true)
    HAS_ZH=$(grep -E '^[[:space:]]*language[[:space:]]*=[[:space:]]*"zh"' "$CONFIG_FILE" || true)
    HAS_PASTE=$(grep -E '^[[:space:]]*mode[[:space:]]*=[[:space:]]*"paste"' "$CONFIG_FILE" || true)

    if [ -n "$HAS_SMALL" ] && [ -n "$HAS_ZH" ] && [ -n "$HAS_PASTE" ]; then
        echo -e "${GREEN}[PASS] 配置正确 (model=small, lang=zh, mode=paste 剪贴板直通)${NC}"
    else
        echo -e "${YELLOW}[WARN] 配置文件缺少关键优化项，请检查 model/zh/paste${NC}"
    fi
else
    echo -e "${RED}[FAIL] 未找到配置文件 $CONFIG_FILE${NC}"
fi

# 4. 检查 systemd user service 是否覆盖为 voxtype-vulkan
echo -n "[4/7] 检查 systemd 用户服务 GPU 加速单元定义... "
SERVICE_FILE="$HOME/.config/systemd/user/voxtype.service"
if [ -f "$SERVICE_FILE" ] && grep -q "voxtype-vulkan" "$SERVICE_FILE"; then
    echo -e "${GREEN}[PASS] 服务单元已正确重定向为 voxtype-vulkan${NC}"
else
    echo -e "${YELLOW}[WARN] 服务单元未指向 voxtype-vulkan，可能使用 CPU 慢速模式${NC}"
fi

# 5. 检查 voxtype.service 当前运行状态
echo -n "[5/7] 检查 voxtype.service 进程存活状态... "
if systemctl --user is-active --quiet voxtype.service; then
    PID=$(systemctl --user show -p MainPID --value voxtype.service)
    echo -e "${GREEN}[PASS] voxtype.service 正在运行 (PID: $PID)${NC}"
else
    echo -e "${RED}[FAIL] voxtype.service 未运行！请执行: systemctl --user start voxtype${NC}"
fi

# 6. 验证 GPU 硬件加速加载日志
echo -n "[6/7] 验证 Whisper Vulkan GPU 显存加载状态... "
VULKAN_LOG=$(journalctl --user -u voxtype -b --no-pager -n 50 2>/dev/null | grep -i "Vulkan" | tail -n 1 || true)
if [ -n "$VULKAN_LOG" ]; then
    echo -e "${GREEN}[PASS] 检测到 Vulkan GPU 显存加速日志${NC}"
else
    echo -e "${YELLOW}[INFO] 未在近期日志中直接捕获 Vulkan 字样 (若启动已久属正常)${NC}"
fi

# 7. 检查系统全局快捷键支持
echo -n "[7/7] 检查 Hyprland 快捷键注册状态... "
if grep -rn "voxtype" /usr/share/omarchy/default/hypr/bindings/voxtype.lua >/dev/null 2>&1 || \
   grep -rn "voxtype" "$HOME/.config/hypr/" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] 检测到全局快捷键支持 (Super+Ctrl+X 切换录音 / F9 对讲)${NC}"
else
    echo -e "${YELLOW}[WARN] 未在 Hyprland 配置中发现 voxtype 快捷键绑定${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

#!/usr/bin/env bash
# ==============================================================================
# Omarchy Electron Wayland IME 状态与漏洞诊断脚本
# 用于检测 Electron 类 AI 客户端在 Wayland + Fcitx5 下的输入法健康度及退格漏洞风险
# ==============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BOLD}${BLUE}=== Omarchy Electron Wayland IME 兼容性与退格跳行首漏洞诊断 ===${NC}\n"

# 1. 检查桌面与输入法会话基础
echo -e "${BOLD}1. 检查桌面与输入法运行环境:${NC}"
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
if [[ "$SESSION_TYPE" == "wayland" ]]; then
    echo -e "  [${GREEN}✓${NC}] 会话类型: Wayland (${XDG_CURRENT_DESKTOP:-unknown})"
else
    echo -e "  [${YELLOW}!${NC}] 会话类型: ${SESSION_TYPE} (非 Wayland，部分漏洞仅在 Wayland 下触发)"
fi

if pgrep -x "fcitx5" >/dev/null 2>&1; then
    echo -e "  [${GREEN}✓${NC}] Fcitx5 守护进程: 正在运行 (PID: $(pgrep -x fcitx5 | tr '\n' ' '))"
else
    echo -e "  [${RED}✗${NC}] Fcitx5 守护进程: 未检测到运行！"
fi

# 检查环境变量
for var in GTK_IM_MODULE QT_IM_MODULE XMODIFIERS; do
    val="${!var:-<未设置>}"
    if [[ "$val" =~ fcitx ]]; then
        echo -e "  [${GREEN}✓${NC}] 环境变量 $var=$val"
    else
        echo -e "  [${YELLOW}!${NC}] 环境变量 $var=$val (建议设置为包含 fcitx)"
    fi
done

echo ""

# 2. 扫描并诊断已安装的 Electron AI 客户端
echo -e "${BOLD}2. 扫描常用 Electron AI 客户端与 IME 配置:${NC}"

declare -A APPS=(
    ["qoder-cn-ide"]="Qoder CN IDE"
    ["codebuddy-ide-cn"]="CodeBuddy CN IDE"
    ["workbuddy"]="WorkBuddy 桌面端"
    ["code"]="Visual Studio Code"
    ["trae-cn"]="Trae CN IDE"
)

check_app_config() {
    local app_key="$1"
    local app_name="$2"
    local bin_path=""
    local flags_file="$HOME/.config/${app_key}-flags.conf"
    local has_v1_defense=false
    local has_wayland_flag=false

    # 探测二进制
    if which "$app_key" >/dev/null 2>&1; then
        bin_path="$(which "$app_key")"
    elif [[ -x "$HOME/.local/bin/$app_key" ]]; then
        bin_path="$HOME/.local/bin/$app_key"
    elif [[ -x "$HOME/.local/opt/WorkBuddy/workbuddy" && "$app_key" == "workbuddy" ]]; then
        bin_path="$HOME/.local/opt/WorkBuddy/workbuddy"
    elif [[ -x "/opt/WorkBuddy/workbuddy" && "$app_key" == "workbuddy" ]]; then
        bin_path="/opt/WorkBuddy/workbuddy"
    fi

    if [[ -z "$bin_path" ]]; then
        echo -e "  [-] ${BOLD}${app_name}${NC}: 未安装或未在 PATH 中检测到"
        return
    fi

    echo -e "  [*] ${BOLD}${app_name}${NC} (${bin_path}):"

    # 检查 flags 文件
    if [[ -f "$flags_file" ]]; then
        echo -e "      配置文件: ${flags_file}"
        if grep -q "ozone-platform=wayland" "$flags_file" 2>/dev/null; then
            has_wayland_flag=true
            echo -e "      [${GREEN}✓${NC}] 已配置 Wayland 原生渲染 (--ozone-platform=wayland)"
        else
            echo -e "      [${YELLOW}!${NC}] 未启用原生 Wayland，可能在 XWayland 模糊模式下运行"
        fi

        if grep -q "wayland-text-input-version=1" "$flags_file" 2>/dev/null; then
            has_v1_defense=true
            echo -e "      [${GREEN}✓${NC}] 已开启 text-input-v1 协议防御 (彻底免疫空预编辑退格跳行首漏洞)"
        else
            echo -e "      [${RED}✗${NC}] 未配置 --wayland-text-input-version=1 (存在退格删空跳行首风险！)"
        fi
    else
        echo -e "      [${YELLOW}!${NC}] 未找到专用 flags 配置文件 (${flags_file})"
    fi

    # 针对 VS Code / CodeBuddy 体系检查 argv.json
    if [[ "$app_key" == "codebuddy-ide-cn" || "$app_key" == "code" ]]; then
        for argv_file in "$HOME/.codebuddycn/argv.json" "$HOME/.config/CodeBuddy CN/argv.json" "$HOME/.config/Code/User/argv.json"; do
            if [[ -f "$argv_file" ]]; then
                if grep -q '"wayland-text-input-version": *"1"' "$argv_file" 2>/dev/null; then
                    echo -e "      [${GREEN}✓${NC}] argv.json (${argv_file}): 已配置 v1 协议"
                fi
            fi
        done
    fi
}

for app_key in "${!APPS[@]}"; do
    check_app_config "$app_key" "${APPS[$app_key]}"
done

echo -e "\n${BOLD}${BLUE}=== 诊断完成 ===${NC}"
echo -e "如需一键加固修复上述存在退格漏洞风险的应用，请执行:"
echo -e "  bash $(dirname "$0")/fix_electron_ime.sh <应用名称>"

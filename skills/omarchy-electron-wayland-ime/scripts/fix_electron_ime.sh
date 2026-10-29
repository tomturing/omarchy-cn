#!/usr/bin/env bash
# ==============================================================================
# Omarchy Electron Wayland IME 一键加固修复脚本
# 靶向根治 Electron 客户端在 Wayland 下拼音退格删空跳行首、软键盘失焦与 Vulkan 崩溃
# ==============================================================================
set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

TARGET="${1:-all}"

apply_flags_conf() {
    local app_key="$1"
    local conf_file="$HOME/.config/${app_key}-flags.conf"
    mkdir -p "$HOME/.config"

    echo -e "  [+] 写入配置文件: ${conf_file}"
    cat << 'EOF' > "$conf_file"
# Omarchy Wayland & 中文输入法 (Fcitx5) 调优参数
--ozone-platform=wayland
--ozone-platform-hint=wayland
--enable-wayland-ime
# 核心防御: 强制使用 text-input-v1 协议，规避 Chromium 138 text-input-v3 下空预编辑退格穿透跳行首漏洞
--wayland-text-input-version=1
--enable-features=WaylandWindowDecorations
--use-gl=angle
--disable-features=Vulkan
--password-store=basic
EOF
}

apply_wrapper_bin() {
    local app_key="$1"
    local target_bin="$2"
    local wrapper="$HOME/.local/bin/${app_key}"
    mkdir -p "$HOME/.local/bin"

    echo -e "  [+] 创建高优先级用户包装器: ${wrapper}"
    cat << 'EOF' > "$wrapper"
#!/usr/bin/env bash
set -u

APP_NAME="$(basename "$0")"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
FLAGS_FILE="${XDG_CONFIG_HOME}/${APP_NAME}-flags.conf"
export CHROME_DESKTOP="${APP_NAME}.desktop"
export ELECTRON_OZONE_PLATFORM_HINT="wayland"
export OZONE_PLATFORM="wayland"

# 全局注入 Fcitx5 环境变量
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
export SDL_IM_MODULE=fcitx

declare -a USER_FLAGS=()
if [[ -f "$FLAGS_FILE" ]]; then
    while read -r line || [[ -n "$line" ]]; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        if [[ -n "$trimmed" && ! "$trimmed" =~ ^# ]]; then
            USER_FLAGS+=("$trimmed")
        fi
    done < "$FLAGS_FILE"
fi

EOF
    cat << EOF >> "$wrapper"
TARGET_EXEC="${target_bin}"
if [[ -x "\$TARGET_EXEC" ]]; then
    exec "\$TARGET_EXEC" "\${USER_FLAGS[@]}" "\$@"
elif which "\${APP_NAME}" >/dev/null 2>&1; then
    exec "\$(which "\${APP_NAME}")" "\${USER_FLAGS[@]}" "\$@"
else
    echo "错误: 未找到可执行文件 (\${TARGET_EXEC})。" >&2
    exit 1
fi
EOF
    chmod +x "$wrapper"
}

apply_vscode_argv() {
    local argv_dir="$1"
    local argv_file="${argv_dir}/argv.json"
    mkdir -p "$argv_dir"

    echo -e "  [+] 更新 VS Code 体系运行时: ${argv_file}"
    cat << 'EOF' > "$argv_file"
// This configuration file allows you to pass permanent command line arguments to IDE.
{
	"password-store": "basic",
	"locale": "zh-cn",
	"enable-crash-reporter": false,
	"ozone-platform": "wayland",
	"enable-wayland-ime": true,
	"wayland-text-input-version": "1",
	"enable-features": "WaylandWindowDecorations",
	"disable-features": "Vulkan",
	"use-gl": "angle"
}
EOF
}

echo -e "${BOLD}${BLUE}=== 开始执行 Omarchy Electron Wayland IME 加固 ===${NC}"

case "$TARGET" in
    workbuddy)
        echo -e "\n${BOLD}正在加固 WorkBuddy...${NC}"
        apply_flags_conf "workbuddy"
        WB_BIN="$HOME/.local/opt/WorkBuddy/workbuddy"
        [[ ! -x "$WB_BIN" ]] && WB_BIN="/opt/WorkBuddy/workbuddy"
        apply_wrapper_bin "workbuddy" "$WB_BIN"
        ;;
    codebuddy|codebuddy-ide-cn)
        echo -e "\n${BOLD}正在加固 CodeBuddy CN IDE...${NC}"
        apply_flags_conf "codebuddy-ide-cn"
        CB_BIN="/opt/codebuddy-ide-cn/start.sh"
        [[ ! -x "$CB_BIN" ]] && CB_BIN="/usr/bin/codebuddy-ide-cn"
        apply_wrapper_bin "codebuddy-ide-cn" "$CB_BIN"
        apply_vscode_argv "$HOME/.codebuddycn"
        apply_vscode_argv "$HOME/.config/CodeBuddy CN"
        apply_vscode_argv "$HOME/.config/CodeBuddy CN/User"
        ;;
    qoder|qoder-cn-ide)
        echo -e "\n${BOLD}正在加固 Qoder CN IDE...${NC}"
        apply_flags_conf "qoder-cn-ide"
        apply_wrapper_bin "qoder-cn-ide" "/usr/bin/qoder-cn-ide"
        ;;
    all)
        echo -e "\n${BOLD}正在加固系统已安装的全部 Electron AI 客户端...${NC}"
        # 1. WorkBuddy
        if [[ -x "$HOME/.local/opt/WorkBuddy/workbuddy" || -x "/opt/WorkBuddy/workbuddy" ]]; then
            WB_BIN="$HOME/.local/opt/WorkBuddy/workbuddy"
            [[ ! -x "$WB_BIN" ]] && WB_BIN="/opt/WorkBuddy/workbuddy"
            apply_flags_conf "workbuddy"
            apply_wrapper_bin "workbuddy" "$WB_BIN"
        fi

        # 2. CodeBuddy
        if [[ -x "/opt/codebuddy-ide-cn/start.sh" || -x "/usr/bin/codebuddy-ide-cn" ]]; then
            CB_BIN="/opt/codebuddy-ide-cn/start.sh"
            [[ ! -x "$CB_BIN" ]] && CB_BIN="/usr/bin/codebuddy-ide-cn"
            apply_flags_conf "codebuddy-ide-cn"
            apply_wrapper_bin "codebuddy-ide-cn" "$CB_BIN"
            apply_vscode_argv "$HOME/.codebuddycn"
            apply_vscode_argv "$HOME/.config/CodeBuddy CN"
            apply_vscode_argv "$HOME/.config/CodeBuddy CN/User"
        fi

        # 3. Qoder
        if [[ -x "/usr/bin/qoder-cn-ide" ]]; then
            apply_flags_conf "qoder-cn-ide"
            apply_wrapper_bin "qoder-cn-ide" "/usr/bin/qoder-cn-ide"
        fi
        ;;
    *)
        echo "未知目标: $TARGET。可用选项: workbuddy | codebuddy | qoder | all" >&2
        exit 1
        ;;
esac

echo -e "\n${BOLD}${GREEN}加固完成！请重启目标应用验证输入法体验。${NC}"

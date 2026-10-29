#!/usr/bin/env bash
# ==============================================================================
# Omarchy 平台通用 Electron 应用用户级高优先级启动包装脚本模板
# 存放位置建议: ~/.local/bin/<app> (需配合 chmod +x，确保在 $PATH 中优先于 /usr/bin)
# ==============================================================================
set -u

APP_NAME="$(basename "$0")"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
FLAGS_FILE="${XDG_CONFIG_HOME}/${APP_NAME}-flags.conf"

export CHROME_DESKTOP="${APP_NAME}.desktop"
export ELECTRON_OZONE_PLATFORM_HINT="wayland"
export OZONE_PLATFORM="wayland"
export GDK_BACKEND="wayland,x11,*"
export CLUTTER_BACKEND="wayland"

# 全局注入 Fcitx5 输入法环境变量，确保子进程正常挂载 Wayland 输入管道
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

# 寻址真实二进制
TARGET_BIN=""
if [[ -x "$HOME/.local/opt/${APP_NAME}/${APP_NAME}" ]]; then
    TARGET_BIN="$HOME/.local/opt/${APP_NAME}/${APP_NAME}"
elif [[ -x "/opt/${APP_NAME}/${APP_NAME}" ]]; then
    TARGET_BIN="/opt/${APP_NAME}/${APP_NAME}"
elif [[ -x "/opt/${APP_NAME}/start.sh" ]]; then
    TARGET_BIN="/opt/${APP_NAME}/start.sh"
elif [[ -x "/usr/bin/${APP_NAME}" ]]; then
    TARGET_BIN="/usr/bin/${APP_NAME}"
fi

if [[ -n "$TARGET_BIN" ]]; then
    exec "$TARGET_BIN" "${USER_FLAGS[@]}" "$@"
else
    echo "错误: 未找到 ${APP_NAME} 的真实可执行二进制文件。" >&2
    exit 1
fi

#!/bin/bash
# ==============================================================================
# Tensaku 现代批注截图包装器 (强化加固版 - 第一性原理防光标穿透与输入法无损透明)
# 1. 启动前强制唤醒合成器光标，消除 Xwayland (xfreerdp3) 文本输入工字型光标 (I-beam) 残留
# 2. 强制指定 --initial-tool rectangle，杜绝误触发 text 批注导致全屏输入光标
# 3. 显式绑定 --copy-command "wl-copy --type image/png"，确保剪贴板精准保留图像 MIME 格式
# 4. 【输入法无损透明】严禁主动篡改用户的输入法模式(不调用任何 fcitx5-remote -c/-o)，
#    保持截图前后输入法状态绝对一致，不将中文模式误切为英文
# 5. 【焦点自愈】退出后精准恢复底层原窗口焦点 (兼容 Hyprland 0.56+ Lua 调度器)
# ==============================================================================

user_dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
[[ -f $user_dirs ]] && source "$user_dirs"
dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
mkdir -p "$dir"

# 记录截图前当前聚焦窗口
prev_window=$(hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty')

# 强制重设 Wayland 合成器光标为标准主题，防止宿主机光标被 Xwayland/RDP 窗口文本光标接管
cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
cursor_size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || echo 24)
if [[ -n "$cursor_theme" ]]; then
  hyprctl setcursor "$cursor_theme" "$cursor_size" 2>/dev/null || true
fi

# 启动 Tensaku 进行截图标注 (不使用 exec，确保退出后能执行收尾焦点自愈)
tensaku --capture \
  --output-filename "$dir/tensaku-$(date +%Y-%m-%d_%H-%M-%S).png" \
  --actions-on-enter save-to-clipboard \
  --save-after-copy \
  --initial-tool rectangle \
  --copy-command "wl-copy --type image/png" \
  --early-exit \
  "$@"

# ==============================================================================
# 截图完成退出后的焦点恢复逻辑 (输入法状态原样保留，严禁擅自修改)
# ==============================================================================
if [[ -n "$prev_window" && "$prev_window" != "0x" ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$prev_window' })" >/dev/null 2>&1 \
    || hyprctl dispatch focuswindow "address:$prev_window" >/dev/null 2>&1 || true
fi

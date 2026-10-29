#!/bin/bash
# ==============================================================================
# Tensaku 现代批注截图包装器 (强化加固版 - 第一性原理防光标穿透与焦点自愈设计)
# 1. 启动前强制唤醒合成器光标，消除 Xwayland (xfreerdp3) 文本输入工字型光标 (I-beam) 残留
# 2. 强制指定 --initial-tool rectangle，杜绝误触发 text 批注导致全屏输入光标
# 3. 显式绑定 --copy-command "wl-copy --type image/png"，确保剪贴板精准保留图像 MIME 格式
# 4. 【核心自愈】Tensaku退出后：
#    - 适配 Hyprland 0.56+ Lua 调度器，精准恢复底层原窗口焦点 (特别是 Xwayland/xfreerdp)
#    - 强制关闭/重置 Fcitx5 激活态 (fcitx5-remote -c)，杜绝 LayerShell 退出后输入法悬挂拦截击键
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
# 截图完成退出后的焦点与输入法自愈逻辑
# ==============================================================================
# 1. 强制将焦点归还给原窗口 (同时兼容 Hyprland 0.56+ Lua dispatcher 与旧版语法)
if [[ -n "$prev_window" && "$prev_window" != "0x" ]]; then
  hyprctl dispatch "hl.dsp.focus({ window = 'address:$prev_window' })" >/dev/null 2>&1 \
    || hyprctl dispatch focuswindow "address:$prev_window" >/dev/null 2>&1 || true
fi

# 2. 强制关闭输入法激活态 (确保处于 Inactive/透传状态 1)
#    严禁调用 -o 强制激活，防止宿主机 Fcitx5 截获 Windows 虚拟机或 Xwayland 的物理击键
fcitx5-remote -c >/dev/null 2>&1 || true

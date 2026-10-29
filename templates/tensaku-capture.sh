#!/bin/bash
# ==============================================================================
# Tensaku 现代批注截图包装器 (强化加固版 - 第一性原理与防光标穿透设计)
# 交互特性：
# 1. 拖拽自定义选区
# 2. 空格键 (Space) 自动吸附当前鼠标悬停的窗口
# 3. 按 F 键截取整个屏幕
# 4. 按 S 键进入滚动长截图
# 5. 选定后弹出标注界面（矩形、箭头、文字、马赛克、画笔）
# 6. 回车 (Enter) 或点击复制按钮后，自动复制到剪贴板并存档，同时自动退出关闭截图窗口 (--early-exit)
#
# 稳定性加固：
# - 启动前强制重设 Wayland 合成器光标，消除 Xwayland (xfreerdp3) 文本输入工字型光标 (I-beam) 残留
# - 显式指定 --initial-tool rectangle，杜绝因历史状态记忆导致的“都是输入光标”问题
# - 绑定 --copy-command "wl-copy --type image/png"，确保向 Xwayland 和 Windows RDP 完整传递图像数据
# ==============================================================================

user_dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
[[ -f $user_dirs ]] && source "$user_dirs"
dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
mkdir -p "$dir"

# 强制重设 Wayland 合成器光标为标准主题，防止宿主机光标被 Xwayland/RDP 窗口文本光标接管
cursor_theme=$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'")
cursor_size=$(gsettings get org.gnome.desktop.interface cursor-size 2>/dev/null || echo 24)
if [[ -n "$cursor_theme" ]]; then
  hyprctl setcursor "$cursor_theme" "$cursor_size" 2>/dev/null || true
fi

exec tensaku --capture \
  --output-filename "$dir/tensaku-$(date +%Y-%m-%d_%H-%M-%S).png" \
  --actions-on-enter save-to-clipboard \
  --save-after-copy \
  --initial-tool rectangle \
  --copy-command "wl-copy --type image/png" \
  --early-exit \
  "$@"

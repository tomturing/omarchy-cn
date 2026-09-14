#!/bin/bash
# Tensaku 现代批注截图包装器
# 交互特性：
# 1. 拖拽自定义选区
# 2. 空格键 (Space) 自动吸附当前鼠标悬停的窗口
# 3. 按 F 键截取整个屏幕
# 4. 按 S 键进入滚动长截图
# 5. 选定后弹出标注界面（矩形、箭头、文字、马赛克、画笔）
# 6. 回车 (Enter) 自动复制到剪贴板并存档至图片目录

user_dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
[[ -f $user_dirs ]] && source "$user_dirs"
dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
mkdir -p "$dir"

exec tensaku --capture \
  --output-filename "$dir/tensaku-$(date +%Y-%m-%d_%H-%M-%S).png" \
  --actions-on-enter save-to-clipboard \
  --save-after-copy \
  --copy-command wl-copy \
  "$@"

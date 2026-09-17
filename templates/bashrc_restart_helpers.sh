# ==============================================================================
# 快捷恢复与重启命令规范: restart-<component>
# 规范说明: 统一采用 kebab-case (中划线)，输入 "restart-" + Tab 即可自动补全所有可用恢复命令
# ==============================================================================

# 1. 剪贴板管道重置 (针对跨机剪贴板假死/挂起)
restart-clip() {
    pkill -9 -f "capture.sh text" 2>/dev/null
    echo "Clipboard pipeline reset successfully."
}
alias restart-clipboard='restart-clip'
alias fix-clip='restart-clip'

# 2. 桌面 Shell / 菜单恢复 (针对 Omarchy 菜单、顶栏、Quickshell 死锁卡顿)
restart-shell() {
    echo "Restarting Quickshell / Omarchy shell..."
    killall -9 quickshell 2>/dev/null
    omarchy-restart-shell
}
alias restart-quickshell='restart-shell'
alias restartquickshell='restart-shell'
alias rshell='restart-shell'

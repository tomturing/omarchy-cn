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

# 3. Windows 虚拟机快速彻底重启 (针对 Apps 打开 xfreerdp 窗口黑屏/假死/卡登录)
#
# 第一性原理: 黑屏主因是 Guest 侧 RDP 会话长时间运行后劣化/锁屏假死, 而非宿主机。
#   网页 8006(VNC 原始显存)正常但窗口(RDP→H264)黑 = 故障隔离在 RDP 会话状态。
#   解法 = 冷重启彻底复位 Guest 会话(先 stop 优雅关机→超时 SIGKILL→再 start 冷启动)。
# 对抗性审查要点:
#   - 不用软 restart: stop+start 才能清掉卡死态(本次 Exited(137) 证明旧会话已假死)
#   - 容器名自动探测(omarchy-windows / image dockurr/windows 兜底), 不硬编
#   - docker 权限自动降级: 优先免 sudo, 失败回退 sudo -n
#   - 重启后轮询等待 RDP 3389 真正就绪再提示, 避免过早连接又闪黑
#   - 先清理僵死 xfreerdp 窗口, 防止旧会话残留干扰
restart-windows() {
    local C IMG rc ready
    local RELAUNCH=0
    [[ " $* " == *" -l "* || " $* " == *" --launch "* ]] && RELAUNCH=1

    # 自动锁定容器(名称优先, 其次镜像兜底)
    C=$(docker ps -aq -f name=omarchy-windows 2>/dev/null)
    [[ -z $C ]] && C=$(docker ps -aq -f ancestor=dockurr/windows 2>/dev/null | head -1)
    if [[ -z $C ]]; then
        echo "✗ 未找到 Windows 容器(omarchy-windows / dockurr/windows)，无需重启。" >&2
        return 1
    fi
    IMG=$(docker inspect -f '{{.Name}} {{.Config.Image}}' "$C" 2>/dev/null)

    # docker 权限自适应
    local DK=(docker)
    docker info >/dev/null 2>&1 || DK=(sudo -n docker)

    echo "▶ 清理残留 RDP 窗口..."
    pkill -9 -f 'xfreerdp' 2>/dev/null

    echo "▶ 优雅关机(最多等 15s, 卡死则强杀)..."
    "${DK[@]}" stop -t 15 "$C" >/dev/null 2>&1

    echo "▶ 冷启动 Windows (${IMG})..."
    "${DK[@]}" start "$C" >/dev/null 2>&1 || { echo "✗ 启动失败" >&2; return 1; }

    echo "▶ 等待 RDP(3389) 就绪(最多 90s)..."
    for rc in $(seq 1 45); do
        if timeout 2 bash -c 'cat </dev/null >/dev/tcp/127.0.0.1/3389' 2>/dev/null; then ready=1; break; fi
        sleep 2
    done

    if [[ ${ready:-0} == 1 ]]; then
        echo "✓ Windows 已冷重启并就绪，可从 Apps 重新打开(或用 omarchy-windows-vm launch)。"
    else
        echo "⚠ 90s 内 3389 仍未就绪，Windows 可能仍在开机自检，请稍候或用网页确认: http://127.0.0.1:8006"
    fi

    (( RELAUNCH == 1 )) && omarchy-windows-vm launch --keep-alive
    return 0
}
alias restartwindows='restart-windows'
alias rwin='restart-windows'
alias fix-windows='restart-windows'

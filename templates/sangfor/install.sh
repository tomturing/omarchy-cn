#!/bin/bash
# ==============================================================================
# 深信服自启治理与智能生命周期管理一键安装脚本
# 支持自动化安装包装器、sudoers 提权规则与初始服务锁定
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | cut -c1-8 || tr -dc 'a-f0-9' < /dev/urandom | head -c 8)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][${TRACE_ID}][INFO] $1"
}

log "开始部署深信服自启治理体系..."

# 1. 安装统一管理脚本与客户端包装器至 /usr/local/bin
log "正在安装执行脚本至 /usr/local/bin/..."
sudo cp "${SCRIPT_DIR}/sangfor-mgr" /usr/local/bin/sangfor-mgr
sudo chmod 755 /usr/local/bin/sangfor-mgr
sudo chown root:root /usr/local/bin/sangfor-mgr

sudo cp "${SCRIPT_DIR}/atrust" /usr/local/bin/atrust
sudo chmod 755 /usr/local/bin/atrust

sudo cp "${SCRIPT_DIR}/easyconnect" /usr/local/bin/easyconnect
sudo chmod 755 /usr/local/bin/easyconnect

sudo cp "${SCRIPT_DIR}/ec-stop" /usr/local/bin/ec-stop
sudo chmod 755 /usr/local/bin/ec-stop

sudo cp "${SCRIPT_DIR}/patch-easyconnect.sh" /usr/local/bin/patch-easyconnect
sudo chmod 755 /usr/local/bin/patch-easyconnect

# 2. 安装开机权限守护规则至 /etc/tmpfiles.d/easyconnect.conf
if [ -f "${SCRIPT_DIR}/easyconnect.conf" ]; then
    log "正在配置开机权限守护规则至 /etc/tmpfiles.d/easyconnect.conf..."
    sudo cp "${SCRIPT_DIR}/easyconnect.conf" /etc/tmpfiles.d/easyconnect.conf
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/easyconnect.conf
fi

# 3. 安装 Sudoers 免密提权规则
log "正在配置 Sudoers 权限规则至 /etc/sudoers.d/sangfor..."
CURRENT_USER="${USER:-$(whoami)}"
cat << EOF | sudo tee /etc/sudoers.d/sangfor > /dev/null
# Allow ${CURRENT_USER} to manage Sangfor services via sangfor-mgr without password
${CURRENT_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/sangfor-mgr *
EOF
sudo chmod 0440 /etc/sudoers.d/sangfor

# 校验 sudoers 语法有效性
sudo visudo -c > /dev/null

# 4. 固化 EasyConnect 核心监控服务开机自启
log "确保 EasyMonitor.service 处于开机自启状态..."
sudo systemctl unmask EasyMonitor.service 2>/dev/null || true
sudo systemctl enable EasyMonitor.service 2>/dev/null || true
sudo systemctl start EasyMonitor.service 2>/dev/null || true

# 5. 初始状态物理加锁 aTrust（避免开机自启争抢资源）
log "执行 aTrust 状态安全锁定与进程深度清理..."
sudo /usr/local/bin/sangfor-mgr stop-atrust

# 6. 可选：清理 Remmina 开机自启
if [ -f "$HOME/.config/autostart/remmina-applet.desktop" ]; then
    log "检测到 Remmina 开机自启条目，正在移除..."
    rm -f "$HOME/.config/autostart/remmina-applet.desktop"
    killall remmina 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
fi

log "部署完成！现在你可以在应用程序菜单中直接启动 EasyConnect，已保障开机自启与免密调用。"
log "若需配置 EasyConnect 凭据持久化与真正一键自动登录，请运行: patch-easyconnect"

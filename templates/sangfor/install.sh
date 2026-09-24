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

# 2. 安装 Sudoers 免密提权规则
log "正在配置 Sudoers 权限规则至 /etc/sudoers.d/sangfor..."
CURRENT_USER="${USER:-$(whoami)}"
cat << EOF | sudo tee /etc/sudoers.d/sangfor > /dev/null
# Allow ${CURRENT_USER} to manage Sangfor services via sangfor-mgr without password
${CURRENT_USER} ALL=(ALL) NOPASSWD: /usr/local/bin/sangfor-mgr *
EOF
sudo chmod 0440 /etc/sudoers.d/sangfor

# 校验 sudoers 语法有效性
sudo visudo -c > /dev/null

# 3. 初始状态物理加锁（Masking）并终止任何存活残余
log "执行初始系统状态加锁（Masking）与进程深度清理..."
sudo /usr/local/bin/sangfor-mgr stop-atrust
sudo /usr/local/bin/sangfor-mgr stop-easyconnect

# 4. 可选：清理 Remmina 开机自启
if [ -f "$HOME/.config/autostart/remmina-applet.desktop" ]; then
    log "检测到 Remmina 开机自启条目，正在移除..."
    rm -f "$HOME/.config/autostart/remmina-applet.desktop"
    killall remmina 2>/dev/null || true
    systemctl --user daemon-reload 2>/dev/null || true
fi

log "部署完成！现在你可以在应用程序菜单中直接启动 aTrust 与 EasyConnect，无需输入密码，退出时全自动清理加锁。"

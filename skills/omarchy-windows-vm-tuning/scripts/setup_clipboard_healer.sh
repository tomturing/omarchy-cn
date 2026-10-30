#!/bin/bash
# ==============================================================================
# 部署与固化 Omarchy 剪贴板字符集防乱码哨兵服务 (开机持久化自启)
# ==============================================================================

set -euo pipefail

echo "==> [1/4] 安装剪贴板单步提纯脚本..."
install -Dm755 templates/omarchy-clipboard-mojibake-healer-step "$HOME/.local/bin/omarchy-clipboard-mojibake-healer-step"

echo "==> [2/4] 安装守护进程包装器..."
install -Dm755 templates/omarchy-clipboard-sentinel "$HOME/.local/bin/omarchy-clipboard-sentinel"

echo "==> [3/4] 配置 systemd 用户开机自启服务..."
SERVICE_DIR="$HOME/.config/systemd/user"
mkdir -p "$SERVICE_DIR"
cat << 'EOF' > "$SERVICE_DIR/omarchy-clipboard-sentinel.service"
[Unit]
Description=Omarchy Clipboard Deadlock Sentinel & Auto-Healer
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/.local/bin/omarchy-clipboard-sentinel
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

echo "==> [4/4] 重新加载并激活守护服务..."
systemctl --user daemon-reload
systemctl --user enable --now omarchy-clipboard-sentinel.service

echo "==> 剪贴板防乱码自愈服务已成功固化并开机自启！"
systemctl --user status omarchy-clipboard-sentinel.service --no-pager | head -n 12

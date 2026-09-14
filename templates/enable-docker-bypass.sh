#!/usr/bin/env bash
# 一键在 Linux 宿主机上注入 Docker 绕过 Clash TUN 的策略路由并配置开机自启
set -euo pipefail

echo "正在为 Docker 和 Windows VM 配置内核策略路由 (绕过 Clash TUN)..."

# 1. 注入策略路由
sudo ip rule show pref 8990 2>/dev/null | grep -q "172.16.0.0/12" || sudo ip rule add from 172.16.0.0/12 lookup main pref 8990
sudo ip rule show pref 8991 2>/dev/null | grep -q "172.16.0.0/12" || sudo ip rule add to 172.16.0.0/12 lookup main pref 8991

# 2. 写入 systemd 持久化开机服务
sudo tee /etc/systemd/system/docker-bypass-clash.service > /dev/null << 'SERVICE'
[Unit]
Description=Bypass Clash TUN for Docker and Windows VM
After=network.target network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'ip rule show pref 8990 | grep -q 172.16.0.0/12 || ip rule add from 172.16.0.0/12 lookup main pref 8990; ip rule show pref 8991 | grep -q 172.16.0.0/12 || ip rule add to 172.16.0.0/12 lookup main pref 8991'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable --now docker-bypass-clash.service

echo "✅ 配置完成并持久化生效！当前 Windows VM 网络已直通物理网卡。"

#!/usr/bin/env bash
# 一键在 Linux 宿主机上注入 Docker 绕过 Clash TUN 的策略路由并配置开机自启与容器 DNS 解耦
set -euo pipefail

echo "正在为 Docker 和 Windows VM 配置内核策略路由与纯净 DNS (绕过 Clash TUN 与 Fake-IP)..."

# 1. 注入策略路由
echo "-> [1/4] 配置内核策略路由 pref 8990/8991..."
sudo ip rule show pref 8990 2>/dev/null | grep -q "172.16.0.0/12" || sudo ip rule add from 172.16.0.0/12 lookup main pref 8990
sudo ip rule show pref 8991 2>/dev/null | grep -q "172.16.0.0/12" || sudo ip rule add to 172.16.0.0/12 lookup main pref 8991

# 2. 写入 systemd 持久化开机服务
echo "-> [2/4] 配置 systemd 开机自启服务 (docker-bypass-clash.service)..."
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

# 3. 修复 Docker daemon.json 与 docker-compose.yml 避免 Fake-IP 污染
echo "-> [3/4] 解耦 Windows VM 容器 DNS (防止继承 Clash 172.17.0.1 Fake-IP)..."
COMPOSE_FILE="/var/lib/omarchy/windows/docker-compose.yml"
if [ -f "$COMPOSE_FILE" ]; then
    if ! grep -q "223.5.5.5" "$COMPOSE_FILE"; then
        sudo python3 -c '
path = "/var/lib/omarchy/windows/docker-compose.yml"
with open(path, "r") as f:
    text = f.read()
if "dns:" not in text:
    text = text.replace("    cap_add:\n      - NET_ADMIN\n", "    cap_add:\n      - NET_ADMIN\n    dns:\n      - 223.5.5.5\n      - 119.29.29.29\n      - 8.8.8.8\n")
if "DNSMASQ_OPTS" not in text:
    text = text.replace("      ARGUMENTS: \"-rtc base=localtime,clock=host,driftfix=slew\"\n", "      ARGUMENTS: \"-rtc base=localtime,clock=host,driftfix=slew\"\n      DNSMASQ_OPTS: \"--server=223.5.5.5 --server=119.29.29.29 --server=8.8.8.8\"\n")
with open(path, "w") as f:
    f.write(text)
'
        echo "   [OK] 已向 $COMPOSE_FILE 注入公网 DNS 与 dnsmasq 配置"
    else
        echo "   [OK] $COMPOSE_FILE 已配置公网 DNS"
    fi
fi

# 确保启动脚本模板同步补齐
VM_BIN="/usr/share/omarchy/bin/omarchy-windows-vm"
if [ -f "$VM_BIN" ] && ! grep -q "223.5.5.5" "$VM_BIN"; then
    sudo python3 -c '
path = "/usr/share/omarchy/bin/omarchy-windows-vm"
with open(path, "r") as f:
    text = f.read()
target1 = "      ARGUMENTS: \"-rtc base=localtime,clock=host,driftfix=slew\"\n    devices:"
rep1 = "      ARGUMENTS: \"-rtc base=localtime,clock=host,driftfix=slew\"\n      DNSMASQ_OPTS: \"--server=223.5.5.5 --server=119.29.29.29 --server=8.8.8.8\"\n    devices:"
target2 = "    cap_add:\n      - NET_ADMIN\n    ports:"
rep2 = "    cap_add:\n      - NET_ADMIN\n    dns:\n      - 223.5.5.5\n      - 119.29.29.29\n      - 8.8.8.8\n    ports:"
if target1 in text:
    text = text.replace(target1, rep1, 1)
if target2 in text:
    text = text.replace(target2, rep2, 1)
with open(path, "w") as f:
    f.write(text)
'
    echo "   [OK] 已向 $VM_BIN 模板同步注入公网 DNS"
fi

# 4. 若容器当前正在运行，热更新其 resolv.conf 与 dnsmasq
echo "-> [4/4] 检查并热生效运行中的 Windows 容器网络..."
if sudo docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^omarchy-windows$"; then
    echo "   检测到 omarchy-windows 正在运行，热更新其内部 DNS 并重载 dnsmasq..."
    sudo docker exec omarchy-windows bash -c '
echo "nameserver 223.5.5.5" > /etc/resolv.conf
pkill -HUP dnsmasq 2>/dev/null || true
' || true
    echo "   [OK] 容器内热更新完成"
fi

echo -e "\n✅ 配置完成并持久化生效！当前 Windows VM 网络已直通物理网卡且使用纯净公网 DNS。"

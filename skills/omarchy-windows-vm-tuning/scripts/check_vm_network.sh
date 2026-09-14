#!/usr/bin/env bash
# 检查宿主机策略路由与 Docker 虚拟机网络隔离状态
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy Windows VM 网络隔离与运行状态诊断 ===${NC}\n"

# 1. 检查 Linux 内核策略路由 8990
echo -n "[1/4] 检查内核策略路由 (pref 8990: Docker 流量强制直连物理网卡)... "
if ip rule show pref 8990 2>/dev/null | grep -q "172.16.0.0/12"; then
    echo -e "${GREEN}[PASS] 策略路由已生效 (直连 main 表)${NC}"
else
    echo -e "${RED}[FAIL] 缺少 pref 8990 策略路由！VM 流量可能正被 Clash TUN 劫持${NC}"
fi

# 2. 检查 systemd 开机持久化自启服务
echo -n "[2/4] 检查 docker-bypass-clash.service 开机自启服务... "
if systemctl is-enabled docker-bypass-clash.service >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] 服务已设置为开机自启${NC}"
else
    echo -e "${YELLOW}[WARN] 未启用开机自启，重启后隔离规则将丢失${NC}"
fi

# 3. 检查 Windows VM 物理磁盘镜像与 Btrfs 快照状态
echo -n "[3/4] 检查 Windows VM 磁盘镜像 (~/.windows/data.img)... "
if [ -f "$HOME/.windows/data.img" ]; then
    SIZE=$(du -h "$HOME/.windows/data.img" | cut -f1)
    echo -e "${GREEN}[PASS] 镜像存在 (占用物理空间: $SIZE)${NC}"
    if [ -f "$HOME/.windows/data.img.snapshot" ]; then
        echo -e "       ${BLUE}-> 发现本地快照备份 (~/.windows/data.img.snapshot)${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 未在 ~/.windows/data.img 找到虚拟磁盘${NC}"
fi

# 4. 检查 Docker 与容器状态
echo -n "[4/4] 检查 Windows VM 运行进程... "
if pgrep -f "xfreerdp" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] FreeRDP 会话正在运行中${NC}"
else
    echo -e "${YELLOW}[INFO] FreeRDP 会话未运行${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

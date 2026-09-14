#!/usr/bin/env bash
# 检查宿主机策略路由、Docker 虚拟机网络隔离与 FreeRDP 客户端稳定性状态
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy Windows VM 状态与稳定性诊断 ===${NC}\n"

# 1. 检查 Linux 内核策略路由 8990
echo -n "[1/5] 检查内核策略路由 (pref 8990: Docker 流量强制直连物理网卡)... "
if ip rule show pref 8990 2>/dev/null | grep -q "172.16.0.0/12"; then
    echo -e "${GREEN}[PASS] 策略路由已生效 (直连 main 表)${NC}"
else
    echo -e "${RED}[FAIL] 缺少 pref 8990 策略路由！VM 流量可能正被 Clash TUN 劫持${NC}"
fi

# 2. 检查 systemd 开机持久化自启服务
echo -n "[2/5] 检查 docker-bypass-clash.service 开机自启服务... "
if systemctl is-enabled docker-bypass-clash.service >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] 服务已设置为开机自启${NC}"
else
    echo -e "${YELLOW}[WARN] 未启用开机自启，重启后隔离规则将丢失${NC}"
fi

# 3. 检查 Windows VM 物理磁盘镜像与 Btrfs 快照状态
echo -n "[3/5] 检查 Windows VM 磁盘镜像 (~/.windows/data.img)... "
if [ -f "$HOME/.windows/data.img" ]; then
    SIZE=$(du -h "$HOME/.windows/data.img" | cut -f1)
    echo -e "${GREEN}[PASS] 镜像存在 (占用物理空间: $SIZE)${NC}"
    if [ -f "$HOME/.windows/data.img.snapshot" ]; then
        echo -e "       ${BLUE}-> 发现本地快照备份 (~/.windows/data.img.snapshot)${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 未在 ~/.windows/data.img 找到虚拟磁盘${NC}"
fi

# 4. 检查 Windows VM 启动器 RDP 客户端选型与缩放兼容性
echo -n "[4/5] 检查 omarchy-windows-vm 客户端选型 (xfreerdp3 vs sdl-freerdp3)... "
VM_SCRIPT="/usr/share/omarchy/bin/omarchy-windows-vm"
if [ -f "$VM_SCRIPT" ]; then
    if grep -q "xfreerdp3 /u:" "$VM_SCRIPT"; then
        echo -e "${GREEN}[PASS] 当前使用 xfreerdp3 (享有 100% 完美的 Hyprland 分数缩放与无黑边全屏)${NC}"
    elif grep -q "sdl-freerdp3 /u:" "$VM_SCRIPT"; then
        echo -e "${YELLOW}[WARN] 当前使用实验性 sdl-freerdp3！在 Hyprland 1.25x 缩放下会出现黑边与分辨率异常！${NC}"
        echo -e "       ${BLUE}-> 推荐运行: bash skills/omarchy-windows-vm-tuning/scripts/rebuild_freerdp_with_patch.sh${NC}"
    else
        echo -e "${YELLOW}[WARN] 未检测到标准 freerdp 启动行${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 未找到 $VM_SCRIPT${NC}"
fi

# 5. 检查 Windows VM 运行进程
echo -n "[5/5] 检查 Windows VM 运行进程... "
if pgrep -f "xfreerdp" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] xfreerdp3 会话正在运行中${NC}"
elif pgrep -f "freerdp" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] FreeRDP 会话正在运行中${NC}"
elif pgrep -f "qemu-system-x86_64.*Windows" >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] QEMU 虚拟机后台运行中 (当前未连接 RDP 桌面)${NC}"
else
    echo -e "${YELLOW}[INFO] 虚拟机目前未运行${NC}"
fi

echo -e "\n${BLUE}=== 诊断完成 ===${NC}"

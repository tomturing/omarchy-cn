#!/usr/bin/env bash
# 检查宿主机策略路由、Docker 虚拟机网络隔离、DNS 解耦与 FreeRDP 客户端稳定性状态
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Omarchy Windows VM 状态与稳定性全链路诊断 ===${NC}\n"

# 1. 检查 Linux 内核策略路由 8990
echo -n "[1/7] 检查内核策略路由 (pref 8990: Docker 流量强制直连物理网卡)... "
if ip rule show pref 8990 2>/dev/null | grep -q "172.16.0.0/12"; then
    echo -e "${GREEN}[PASS] 策略路由已生效 (直连 main 表)${NC}"
else
    echo -e "${RED}[FAIL] 缺少 pref 8990 策略路由！VM 流量可能正被 Clash TUN 劫持${NC}"
fi

# 2. 检查 systemd 开机持久化自启服务
echo -n "[2/7] 检查 docker-bypass-clash.service 开机自启服务... "
if systemctl is-enabled docker-bypass-clash.service >/dev/null 2>&1; then
    echo -e "${GREEN}[PASS] 服务已设置为开机自启${NC}"
else
    echo -e "${YELLOW}[WARN] 未启用开机自启，重启后隔离规则将丢失${NC}"
fi

# 3. 检查 Docker Compose 文件 DNS 配置 (防止继承 Clash 172.17.0.1 Fake-IP)
echo -n "[3/7] 检查 Windows VM Compose 文件 DNS 配置... "
COMPOSE_FILE="/var/lib/omarchy/windows/docker-compose.yml"
COMPOSE_CONTENT=$(sudo -n cat "$COMPOSE_FILE" 2>/dev/null || cat "$COMPOSE_FILE" 2>/dev/null || true)
if [ -n "$COMPOSE_CONTENT" ]; then
    if echo "$COMPOSE_CONTENT" | grep -q "223.5.5.5" && echo "$COMPOSE_CONTENT" | grep -q "dns:"; then
        echo -e "${GREEN}[PASS] 已显式配置公网纯净 DNS (223.5.5.5 / 119.29.29.29)${NC}"
    else
        echo -e "${RED}[FAIL] 缺失 dns: 配置！容器将继承宿主机 DNS 并触发 Fake-IP 冲突${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 无法读取 $COMPOSE_FILE${NC}"
fi

# 4. 检查运行中容器内部 DNS 解析 (Fake-IP 专项检测)
echo -n "[4/7] 检查 VM 容器实时 DNS 解析是否摆脱 Fake-IP... "
DOCKER_RUN="docker"
if ! docker ps >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
        DOCKER_RUN="sudo -n docker"
    else
        DOCKER_RUN=""
    fi
fi

if [ -n "$DOCKER_RUN" ] && $DOCKER_RUN ps --format '{{.Names}}' 2>/dev/null | grep -q "^omarchy-windows$"; then
    RESOLVED_IP=$($DOCKER_RUN exec omarchy-windows python3 -c '
import socket
try:
    print(socket.gethostbyname("www.baidu.com"))
except Exception as e:
    print("ERR:" + str(e))
' 2>/dev/null || echo "FAIL")
    if [[ "$RESOLVED_IP" == 198.18.* ]]; then
        echo -e "${RED}[FAIL] 容器解析出 Clash Fake-IP ($RESOLVED_IP)！外网 TCP 将全部超时${NC}"
    elif [[ "$RESOLVED_IP" == "FAIL" || "$RESOLVED_IP" == ERR:* ]]; then
        echo -e "${YELLOW}[WARN] 容器解析异常: $RESOLVED_IP${NC}"
    else
        echo -e "${GREEN}[PASS] 解析正常 (真实公网 IP: $RESOLVED_IP)${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] omarchy-windows 容器未运行或无免密权限，跳过动态 DNS 探测${NC}"
fi

# 5. 检查 Windows VM 物理磁盘镜像与 Btrfs 快照状态
echo -n "[5/7] 检查 Windows VM 磁盘镜像 (data.img)... "
DISK_PATH=""
TARGET_UID="${SUDO_UID:-$(id -u)}"
if [ -f "/var/lib/omarchy/windows/mounts/users/$TARGET_UID/storage/data.img" ]; then
    DISK_PATH="/var/lib/omarchy/windows/mounts/users/$TARGET_UID/storage/data.img"
elif [ -f "$HOME/.windows/data.img" ]; then
    DISK_PATH="$HOME/.windows/data.img"
else
    # 模糊查找是否存在其他 uid 下的 data.img
    FOUND_IMG=$(ls /var/lib/omarchy/windows/mounts/users/*/storage/data.img 2>/dev/null | head -n 1 || true)
    if [ -n "$FOUND_IMG" ]; then
        DISK_PATH="$FOUND_IMG"
    fi
fi

if [ -n "$DISK_PATH" ]; then
    SIZE=$(du -h "$DISK_PATH" | cut -f1)
    echo -e "${GREEN}[PASS] 镜像存在 ($DISK_PATH, 实际占用: $SIZE)${NC}"
    if [ -f "${DISK_PATH}.snapshot" ]; then
        echo -e "       ${BLUE}-> 发现本地快照备份 (${DISK_PATH}.snapshot)${NC}"
    fi
else
    echo -e "${YELLOW}[INFO] 未找到 data.img 磁盘镜像${NC}"
fi

# 6. 检查 Windows VM 启动器 RDP 客户端选型与缩放兼容性
echo -n "[6/7] 检查 omarchy-windows-vm 客户端选型 (xfreerdp3 vs sdl-freerdp3)... "
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

# 7. 检查 Windows VM 运行进程
echo -n "[7/7] 检查 Windows VM 运行进程... "
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

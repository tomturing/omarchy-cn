#!/bin/bash
# ==============================================================================
# check_vpn_governance.sh: 诊断企业级 VPN（aTrust/EasyConnect）及开机自启治理状态
# ==============================================================================

set -o pipefail

echo "========================================================"
echo "          企业级 VPN 与开机自启治理状态诊断"
echo "========================================================"

# 1. 检查 aTrust 状态
echo -e "\n[1/4] aTrustDaemon 服务状态:"
if systemctl cat aTrustDaemon.service >/dev/null 2>&1; then
    if systemctl is-active --quiet aTrustDaemon.service; then
        STATE="active"
    else
        STATE="inactive"
    fi
    ENABLED=$(systemctl is-enabled aTrustDaemon.service 2>/dev/null || true)
    [ -z "$ENABLED" ] && ENABLED="disabled"

    echo "  - 活跃状态: ${STATE}"
    echo "  - 自启策略: ${ENABLED}"
    if [ "$ENABLED" = "masked" ]; then
        echo "  - 状态判定: [PASS] 服务已被成功物理锁定 (Masked)"
    else
        echo "  - 状态判定: [WARN] 服务处于 ${ENABLED} 状态，未被 Mask 锁定，存在开机自启风险"
    fi
else
    echo "  - 状态判定: [INFO] 未安装 aTrustDaemon.service"
fi

# 2. 检查 EasyMonitor 状态
echo -e "\n[2/4] EasyMonitor 服务状态:"
if systemctl cat EasyMonitor.service >/dev/null 2>&1; then
    if systemctl is-active --quiet EasyMonitor.service; then
        STATE="active"
    else
        STATE="inactive"
    fi
    ENABLED=$(systemctl is-enabled EasyMonitor.service 2>/dev/null || true)
    [ -z "$ENABLED" ] && ENABLED="disabled"

    echo "  - 活跃状态: ${STATE}"
    echo "  - 自启策略: ${ENABLED}"
    if [ "$ENABLED" = "masked" ]; then
        echo "  - 状态判定: [PASS] 服务已被成功物理锁定 (Masked)"
    else
        echo "  - 状态判定: [WARN] 服务处于 ${ENABLED} 状态，未被 Mask 锁定，存在开机自启风险"
    fi
else
    echo "  - 状态判定: [INFO] 未安装 EasyMonitor.service"
fi

# 3. 检查存活的后台孤儿进程
echo -e "\n[3/4] 存活关联进程扫描:"
PROCS=$(ps aux | grep -E "aTrust|sangfor|EasyConnect|EasyMonitor|ECAgent|CSClient|svpnservice" | grep -v grep || true)
if [ -n "$PROCS" ]; then
    echo "  [WARN] 发现存活后台进程:"
    echo "$PROCS" | awk '{print "    PID: "$2" | USER: "$1" | CMD: "$11}'
else
    echo "  [PASS] 当前系统无任何深信服后台进程残留。"
fi

# 4. 检查包装器与免密提权检查
echo -e "\n[4/4] 智能生命周期包装器与免密提权检查:"
[ -x "/usr/local/bin/sangfor-mgr" ] && echo "  - [PASS] /usr/local/bin/sangfor-mgr 统一管理器已就绪" || echo "  - [FAIL] 缺少 /usr/local/bin/sangfor-mgr"
[ -x "/usr/local/bin/atrust" ] && echo "  - [PASS] /usr/local/bin/atrust 包装器已接管" || echo "  - [FAIL] 未部署 atrust 包装器"
[ -x "/usr/local/bin/easyconnect" ] && echo "  - [PASS] /usr/local/bin/easyconnect 包装器已接管" || echo "  - [FAIL] 未部署 easyconnect 包装器"
[ -x "/usr/local/bin/ec-stop" ] && echo "  - [PASS] /usr/local/bin/ec-stop 一键工具已就绪" || echo "  - [FAIL] 未部署 ec-stop"

if sudo -n /usr/local/bin/sangfor-mgr status >/dev/null 2>&1; then
    echo "  - [PASS] Sudoers 免密提权执行已生效 (无密码阻断)"
else
    echo "  - [WARN] 当前用户尚未获得 sangfor-mgr 的免密执行权限"
fi

echo -e "\n========================================================"

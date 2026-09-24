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
echo -e "\n[2/5] EasyMonitor 服务状态:"
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
        echo "  - 状态判定: [WARN] 服务已被 Mask 锁定到 /dev/null！若要开机后直接使用 EasyConnect，这会导致 'Local environment contains error'，请执行 unmask 并 enable"
    elif [ "$ENABLED" = "enabled" ]; then
        echo "  - 状态判定: [PASS] 服务已启用开机自启 (enabled)，保证客户端启动时守护环境正常"
    else
        echo "  - 状态判定: [INFO] 服务处于 ${ENABLED} 状态 (非自启)"
    fi
else
    echo "  - 状态判定: [INFO] 未安装 EasyMonitor.service"
fi

# 3. 检查存活的后台孤儿进程
echo -e "\n[3/5] 存活关联进程扫描:"
PROCS=$(ps aux | grep -E "aTrust|sangfor|EasyConnect|EasyMonitor|ECAgent|CSClient|svpnservice" | grep -v grep || true)
if [ -n "$PROCS" ]; then
    echo "  [INFO] 发现运行中后台进程:"
    echo "$PROCS" | awk '{print "    PID: "$2" | USER: "$1" | CMD: "$11}'
else
    echo "  [INFO] 当前系统无任何深信服后台进程。"
fi

# 4. 检查包装器与免密提权检查
echo -e "\n[4/5] 智能生命周期包装器与免密提权检查:"
[ -x "/usr/local/bin/sangfor-mgr" ] && echo "  - [PASS] /usr/local/bin/sangfor-mgr 统一管理器已就绪" || echo "  - [FAIL] 缺少 /usr/local/bin/sangfor-mgr"
[ -x "/usr/local/bin/atrust" ] && echo "  - [PASS] /usr/local/bin/atrust 包装器已接管" || echo "  - [FAIL] 未部署 atrust 包装器"
[ -x "/usr/local/bin/easyconnect" ] && echo "  - [PASS] /usr/local/bin/easyconnect 包装器已接管" || echo "  - [FAIL] 未部署 easyconnect 包装器"
[ -x "/usr/local/bin/ec-stop" ] && echo "  - [PASS] /usr/local/bin/ec-stop 一键工具已就绪" || echo "  - [FAIL] 未部署 ec-stop"
[ -x "/usr/local/bin/patch-easyconnect" ] && echo "  - [PASS] /usr/local/bin/patch-easyconnect 补丁工具已就绪" || echo "  - [INFO] 未部署 patch-easyconnect 工具"

if sudo -n /usr/local/bin/sangfor-mgr status >/dev/null 2>&1; then
    echo "  - [PASS] Sudoers 免密提权执行已生效 (无密码阻断)"
else
    echo "  - [WARN] 当前用户尚未获得 sangfor-mgr 的免密执行权限"
fi

# 5. 检查 EasyConnect 凭据持久化与自动登录熔断补丁
echo -e "\n[5/5] EasyConnect 凭据持久化与防卡死熔断补丁检查:"
ASAR="/usr/share/sangfor/EasyConnect/resources/app.asar"
if [ -f "$ASAR" ]; then
    if strings "$ASAR" 2>/dev/null | grep -q "EC-AutoLogin-V4"; then
        echo "  - [PASS] app.asar 已注入 V4 自动登录与 Loading 死锁熔断保护补丁"
    else
        echo "  - [WARN] app.asar 未检测到 V4 补丁，登录后可能卡在 'Loading resources' 遮罩"
    fi
fi
if [ -f "/etc/tmpfiles.d/easyconnect.conf" ]; then
    echo "  - [PASS] /etc/tmpfiles.d/easyconnect.conf 开机权限守护已部署"
else
    echo "  - [WARN] 缺少 /etc/tmpfiles.d/easyconnect.conf，系统重启后可能因权限问题无法保存凭据"
fi
CONF_FILE=$(ls /usr/share/sangfor/EasyConnect/resources/conf/setting_*.json 2>/dev/null | head -n 1 || true)
if [ -n "$CONF_FILE" ]; then
    echo "  - [PASS] 检测到持久化配置文件: $CONF_FILE"
else
    echo "  - [INFO] 尚未生成用户凭据持久化文件 setting_<user>.json"
fi

echo -e "\n========================================================"

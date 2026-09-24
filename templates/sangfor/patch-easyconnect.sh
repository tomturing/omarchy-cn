#!/bin/bash
# ==============================================================================
# patch-easyconnect.sh: 深信服 EasyConnect 凭据持久化、自动登录与服务死锁熔断补丁工具
#
# 功能特性：
# 1. 自动解包 /usr/share/sangfor/EasyConnect/resources/app.asar
# 2. 注入针对 SPA 路由时延两阶段状态机与 Loading resources 遮罩熔断保护的 preload.js 补丁
# 3. 自动生成标准 RC4 加密的 setting_<user>.json 配置文件并实现自动持久化
# 4. 固化 /etc/tmpfiles.d/easyconnect.conf 开机权限守护与 EasyMonitor.service 开机自启
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_ID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null | cut -c1-8 || tr -dc 'a-f0-9' < /dev/urandom | head -c 8)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][${TRACE_ID}][INFO] $1"
}

warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][${TRACE_ID}][WARN] $1"
}

error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')][${TRACE_ID}][ERROR] $1"
    exit 1
}

# 默认凭据与配置（可通过环境变量注入覆盖）
VPN_HOST="${VPN_HOST:-113.108.13.8:4430}"
VPN_USER="${VPN_USER:-42187}"
VPN_PASS="${VPN_PASS:-1q2w3e.comA}"
CURRENT_USER="${SUDO_USER:-$USER}"

ASAR_FILE="/usr/share/sangfor/EasyConnect/resources/app.asar"
TMP_DIR="/tmp/ec_asar_patch_${TRACE_ID}"

log "=== 开始执行 EasyConnect 自动登录与防卡死固化补丁 ==="
log "目标网关: https://${VPN_HOST}"
log "登录账号: ${VPN_USER}"
log "宿主用户: ${CURRENT_USER}"

# 1. 环境校验
if [ ! -f "$ASAR_FILE" ]; then
    error "未找到 EasyConnect asar 资源文件: $ASAR_FILE"
fi

if ! command -v npx >/dev/null 2>&1; then
    error "系统未安装 npx，无法打包/解包 asar 归档，请先安装 Node.js"
fi

# 2. 备份原包
if [ ! -f "${ASAR_FILE}.orig" ]; then
    log "首次打补丁，创建原始备份: ${ASAR_FILE}.orig"
    sudo cp -p "$ASAR_FILE" "${ASAR_FILE}.orig"
fi

# 3. 解包 asar
log "正在解包 app.asar 至临时目录: $TMP_DIR"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
npx asar extract "$ASAR_FILE" "$TMP_DIR/app"

PRELOAD_FILE="$TMP_DIR/app/src/service/preload.js"
if [ ! -f "$PRELOAD_FILE" ]; then
    error "解包异常，未在 asar 中找到 src/service/preload.js"
fi

# 4. 注入加固补丁 (清洗旧补丁并写入最新 V4 熔断补丁)
log "正在向 preload.js 注入自动连接、双向状态机与 Loading 熔断补丁..."
sed -i '/\/\/ === \[EC-AutoLogin/,$d' "$PRELOAD_FILE"

cat << 'EOF' >> "$PRELOAD_FILE"

// === [EC-AutoLogin-V4] EasyConnect 自动登录与资源加载状态加固补丁 ===
(function() {
    try {
EOF

cat << EOF >> "$PRELOAD_FILE"
        var VPN_HOST = "${VPN_HOST}";
        var TARGET_URL = "https://" + VPN_HOST;
        var USERNAME = "${VPN_USER}";
        var PASSWORD = "${VPN_PASS}";
EOF

cat << 'EOF' >> "$PRELOAD_FILE"
        // -------------------------------------------------------------
        // 场景 1：连接地址选择窗口 (connect.html)
        // -------------------------------------------------------------
        if (location.href.indexOf('connect.html') !== -1) {
            var connectChecks = 0;
            var connectTimer = setInterval(function() {
                connectChecks++;
                if (connectChecks > 50) {
                    clearInterval(connectTimer);
                    return;
                }

                var vm = window.avalon && window.avalon.vmodels && window.avalon.vmodels.connect;
                var input = document.getElementById('connAddrInput');

                if (vm && input) {
                    if (vm.connControl) {
                        clearInterval(connectTimer);
                        return;
                    }

                    if (!vm.address || vm.address !== TARGET_URL) {
                        vm.address = TARGET_URL;
                        input.value = TARGET_URL;
                    }

                    if (vm.errorValue) {
                        vm.errorValue = "";
                    }

                    if (connectChecks >= 6 && !vm.connControl) {
                        clearInterval(connectTimer);
                        if (typeof vm.onSubmit === 'function') {
                            input.dispatchEvent(new Event('change', { bubbles: true }));
                            vm.onSubmit();
                        }
                    }
                }
            }, 200);
        }

        // -------------------------------------------------------------
        // 场景 2：网关用户认证窗口 (在 VPN 主机下的非 shortcut 页面持续检测登录表单)
        // -------------------------------------------------------------
        if (location.href.indexOf(VPN_HOST) !== -1 && location.href.indexOf('shortcut.html') === -1) {
            var loginAttempts = 0;
            var maxWait = 100; // 最多持续等待 20 秒
            var hasSubmitted = false;
            var filled = false;
            var submitWait = 0;

            var loginTimer = setInterval(function() {
                loginAttempts++;
                if (loginAttempts > maxWait) {
                    clearInterval(loginTimer);
                    return;
                }

                // 对抗性防御：若当前已经离开登录页面（如进入 service 资源页面），立即清除登录定时器，绝不干扰
                if (location.hash.indexOf('service') !== -1 || location.href.indexOf('service') !== -1 || location.hash.indexOf('logout') !== -1) {
                    clearInterval(loginTimer);
                    return;
                }

                var vm = window.avalon && window.avalon.vmodels && window.avalon.vmodels.password;
                var usrInput = document.querySelector('.auto-input-usr input') || document.querySelector('input[type=text]');
                var pwdInput = document.querySelector('.auto-input-pwd input') || document.querySelector('input[type=password]');
                var btn = document.querySelector('.auto-click-login button') || document.querySelector('.auto-click-login') || document.querySelector('button[type=submit]');

                if (vm && usrInput && pwdInput) {
                    var isLoggingIn = vm.loading || (vm.buttonText && (vm.buttonText.indexOf('登录中') !== -1 || vm.buttonText.indexOf('Log') !== -1));
                    if (hasSubmitted && isLoggingIn) {
                        clearInterval(loginTimer);
                        return;
                    }

                    // 如果出现非凭据类的其他错误，停止自动重试
                    if (vm.errorData && vm.errorData.indexOf('username') === -1 && vm.errorData.indexOf('用户名') === -1 && vm.errorData.indexOf('password') === -1 && vm.errorData.indexOf('密码') === -1) {
                        clearInterval(loginTimer);
                        return;
                    }

                    if (!filled) {
                        vm.username = USERNAME;
                        usrInput.value = USERNAME;
                        usrInput.dispatchEvent(new Event('input', { bubbles: true }));
                        usrInput.dispatchEvent(new Event('change', { bubbles: true }));

                        vm.password = PASSWORD;
                        pwdInput.value = PASSWORD;
                        pwdInput.dispatchEvent(new Event('input', { bubbles: true }));
                        pwdInput.dispatchEvent(new Event('change', { bubbles: true }));

                        if (vm.errorData) {
                            vm.errorData = "";
                        }
                        filled = true;
                    } else {
                        // 已经完成填充，等待两个周期（约 400ms）确保 avalon 模型与双向绑定完全生效后提交
                        submitWait++;
                        if (submitWait >= 2 && !hasSubmitted && !vm.loading) {
                            hasSubmitted = true;
                            clearInterval(loginTimer);
                            setTimeout(function() {
                                if (typeof vm.login === 'function') {
                                    vm.login();
                                } else if (btn) {
                                    btn.click();
                                }
                            }, 100);
                        }
                    }
                }
            }, 200);
        }

        // -------------------------------------------------------------
        // 场景 3：登录成功后的服务/资源页面与 Loading 状态熔断保护
        // -------------------------------------------------------------
        if (location.href.indexOf(VPN_HOST) !== -1) {
            var serviceCheckCount = 0;
            var serviceTimer = setInterval(function() {
                serviceCheckCount++;
                if (serviceCheckCount > 60) {
                    clearInterval(serviceTimer);
                    return;
                }

                var loadingVm = window.avalon && window.avalon.vmodels && window.avalon.vmodels.common_loading;
                var serviceVm = window.avalon && window.avalon.vmodels && window.avalon.vmodels.service;
                var isServiceRoute = (location.hash.indexOf('service') !== -1) || !!serviceVm;

                if (isServiceRoute) {
                    // 1. 若出现“正在加载资源 (Loading resources)”遮罩，在确认进入服务页后主动关闭它
                    if (loadingVm && loadingVm.toggle) {
                        loadingVm.toggle = false;
                    }

                    // 2. 触发全局事件隐藏 loading
                    if (window.$eventManager && typeof window.$eventManager.$fire === 'function') {
                        window.$eventManager.$fire('all!onHideLoading', true);
                        window.$eventManager.$fire('all!onServiceInitLoadingClose', true);
                    }

                    // 3. 将 service 模型的 rsInit 置为 true，消除 hide:!rsInit 样式，使资源页面正常显示
                    if (serviceVm && !serviceVm.rsInit) {
                        serviceVm.rsInit = true;
                    }

                    // 4. 清理窗口超时定时器，防止主进程 11 秒后弹出异常弹窗
                    var ecWindow = window.ecWindow || (window.serviceInit && window.serviceInit.winMgr);
                    if (ecWindow && ecWindow.showTimer) {
                        clearTimeout(ecWindow.showTimer);
                        ecWindow.showTimer = null;
                    }
                }
            }, 500);
        }
    } catch (e) {
        console.error("[EC-AutoLogin-V4] 运行异常:", e);
    }
})();
EOF

# 5. 重新打包 asar
log "正在重新打包 app.asar..."
npx asar pack "$TMP_DIR/app" "$TMP_DIR/app.asar"
sudo cp "$TMP_DIR/app.asar" "$ASAR_FILE"
sudo cp -p "$TMP_DIR/app.asar" "${ASAR_FILE}.autologin_working"
sudo chmod 644 "$ASAR_FILE" "${ASAR_FILE}.autologin_working"
rm -rf "$TMP_DIR"

# 6. 配置持久化 JSON 生成 (RC4 算法)
log "正在配置凭据持久化文件 setting_${CURRENT_USER}.json..."
CONF_DIR="/usr/share/sangfor/EasyConnect/resources/conf"
sudo mkdir -p "$CONF_DIR"

node -e "
const crypto = require('crypto');
const fs = require('fs');

const host = '${VPN_HOST}';
const user = '${VPN_USER}';
const pass = '${VPN_PASS}';
const salt = '__user_psw_salt_for_local_conf__';
const rc4Key = 'sangfor_cn';

// RC4 加密
const cipher = crypto.createCipheriv('rc4', rc4Key, '');
let enc = cipher.update(pass + salt, 'utf8', 'hex');
enc += cipher.final('hex');

const encUrl = encodeURIComponent('https://' + host);
const config = {
    global: {
        lang__sysconfig: 'en_US',
        version: '1',
        ecPort: '54530',
        lastVPNURL: JSON.stringify('https://' + host),
        vpnURLList: ['https://' + host],
        lang: JSON.stringify('en_US'),
        privacy__sysconfig: 1
    },
    vpn: {
        [encUrl]: {
            firstAuth: JSON.stringify('auth/psw'),
            lastTime: Date.now(),
            loginInfo: {
                password: enc,
                userName: user
            }
        }
    }
};

const target = '${CONF_DIR}/setting_${CURRENT_USER}.json';
fs.writeFileSync(target, JSON.stringify(config, null, 4), 'utf8');
console.log('成功写入持久化配置: ' + target);
"

# 7. 部署开机权限守护
if [ -f "${SCRIPT_DIR}/easyconnect.conf" ]; then
    log "正在安装 /etc/tmpfiles.d/easyconnect.conf 开机权限守护..."
    sudo cp "${SCRIPT_DIR}/easyconnect.conf" /etc/tmpfiles.d/easyconnect.conf
    sudo systemd-tmpfiles --create /etc/tmpfiles.d/easyconnect.conf
fi

# 8. 确保 EasyMonitor.service 开机自启
log "确保 EasyMonitor.service 处于 unmask 并已设置开机自启..."
sudo systemctl unmask EasyMonitor.service 2>/dev/null || true
sudo systemctl enable EasyMonitor.service 2>/dev/null || true
sudo systemctl restart EasyMonitor.service 2>/dev/null || true

log "=== EasyConnect 固化补丁部署完成！重启后点击桌面图标即可一键全自动连通 ==="

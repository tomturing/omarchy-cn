---
name: omarchy-enterprise-vpn-governance
description: Diagnose, optimize, and govern enterprise VPN clients (Sangfor aTrust and EasyConnect) and autostart programs on Omarchy (Arch Linux + Hyprland). Use when the user asks about Sangfor aTrust/EasyConnect autostarting on boot, background daemon resource drain, Wayland floating tray window (TrayWindow) interactions, passwordless on-demand manual launch, or completely cleaning up lingering tunnel/monitor processes upon exit.
---

# Omarchy 企业级 VPN 自启治理与智能生命周期管理技能

本技能提供针对 **深信服 aTrust** 与 **EasyConnect** 等企业级 VPN 客户端在 **Omarchy (Arch Linux + Hyprland on Wayland)** 环境下的开机自启溯源、全系统物理锁定（Masking）、密码穿透自动提权与生命周期全自动闭环治理方案。

---

## 1. 触发场景

当用户在 Omarchy / Arch Linux 下遇到以下问题时激活本技能：
* **发现深信服软件开机偷偷自启**：系统启动后发现 `aTrustAgent`、`aTrustXtunnel-64`、`EasyMonitor`、`ECAgent` 常驻后台；
* **杀掉进程后自动复活**：通过 `killall` 杀掉深信服进程后，几秒内又被 systemd 保活机制（`Restart=always`）强行拉起；
* **Wayland 下托盘图标表现异构**：
  * aTrust 支持现代 Wayland SNI 托盘；
  * EasyConnect 采用旧版自绘的右上角 32x32 `Float Tray` 悬浮窗，关掉主窗口以为断网但实际上处于后台保持连通；
* **希望按需启动、用完即彻底清空**：平时 100% 物理锁死防隐式唤醒，点击应用图标时全自动免密提权启动，退出时全自动杀光所有孤儿进程并重新上锁。

---

## 2. 快速诊断命令

运行内置诊断脚本评估当前环境自启与治理状态：

```bash
bash <skill_dir>/scripts/check_vpn_governance.sh
```

### 诊断核对清单：
| 检查项 | 目标期望状态 | 异常与风险成因 |
| :--- | :--- | :--- |
| **`aTrustDaemon.service`** | `masked` | 处于 `enabled` 状态，开机直接被 PID 1 拉起并常驻。 |
| **`EasyMonitor.service`** | `masked` | 处于 `enabled` 状态，EasyConnect 监控后台开机自启。 |
| **存活孤儿进程** | 0 进程存活 | `ECAgent`、`CSClient`、`svpnservice` 或 `aTrustXtunnel-64` 在后台窃取流量或占内存。 |
| **管理包装器** | `/usr/local/bin/{atrust,easyconnect,sangfor-mgr,ec-stop}` 就绪 | 缺少包装器导致启动时因服务被 Mask 而报错。 |
| **Sudoers 免密规则** | `/etc/sudoers.d/sangfor` 语法有效 | 用户无权自动执行 systemctl 操作，产生密码/指纹阻断。 |

---

## 3. 核心治理方案与操作步骤

### 方案 1：一键应用自动化治理体系

```bash
bash <skill_dir>/scripts/apply_vpn_governance.sh
```

该脚本将自动完成：
1. 部署 `/usr/local/bin/sangfor-mgr` 统一管理脚本（具备 UUID 唯一调用链路追踪日志）；
2. 部署 `/usr/local/bin/atrust` 与 `/usr/local/bin/easyconnect` 前端透明包装器；
3. 部署一键彻底强断工具 `/usr/local/bin/ec-stop`；
4. 配置 `/etc/sudoers.d/sangfor` 授权无密管理；
5. 执行初始状态 `systemctl mask` 物理锁定，并强杀全部存活残余。

---

## 4. 关键使用准则（第一性原理与工作流）

1. **零终端命令日常使用**：
   * **启动**：直接在应用程序菜单中点击 **aTrust** 或 **EasyConnect**，无需打开终端、无需输密码；
   * **运行**：
     * aTrust：通过系统状态栏右下角的托盘图标管理；
     * EasyConnect：登录后**直接关闭主大窗口**释放工作区桌面；右上角的蓝绿“S”小悬浮窗（TrayWindow）将持续维持 VPN 连接；
   * **退出**：
     * aTrust：右键状态栏托盘图标点击退出；
     * EasyConnect：右键屏幕右上角小“S”图标点击【退出】（或执行 `ec-stop`）；
     * 程序退出后包装脚本立即接管，自动彻底断开并清理底层残留进程。
2. **EasyMonitor 开机自启守护（避免本地环境异常）**：
   * 原厂 EasyConnect 启动时强制要求 root 权限的 `EasyMonitor` 监听本地环回端口（54530~54618）；
   * 严禁无脑 `systemctl mask EasyMonitor.service`，否则开机重启后将出现红色错误 `Local environment contains error.`；
   * 必须通过 `systemctl enable EasyMonitor.service` 保持开机自启。

---

## 5. EasyConnect 凭据持久化与 Loading 资源死锁熔断治理

针对 Linux 版 EasyConnect 普遍存在的“无法记住密码”、“登录后一直转圈显示 Loading resources”以及“重启后配置丢失”三大顽疾，基于第一性原理彻底根治：

### 核心物理/逻辑根因剖析：
1. **密码持久化加密**：Linux 端使用 RC4 算法（密钥 `sangfor_cn`，Salt `__user_psw_salt_for_local_conf__`）加密保存密码到 `resources/conf/setting_<user>.json`，但前端官方代码未实现密码自动回填。
2. **SPA 路由时延与状态机死锁**：认证窗口初始载入 `/portal`，随后通过 Hash 路由导航至 `#!/login`。若脚本在页面初期做静态 URL 判断，会导致监听器直接夭折；若缺乏两阶段状态机防抖，avalon.js 双向绑定尚未同步即触发提交会导致提交空密码。
3. **Loading resources 遮罩死锁**：登录成功跳转至 `#!/service` 时，前端 Promise 链条在 `needGoDefault` 条件下未正常触发 resolve，导致 `common_loading` 模态遮罩永远 pending，且 `service.rsInit` 未激活导致页面被 `hide:!rsInit` 隐藏，11 秒后触发主进程超时弹窗。

### 自动化治理与补丁工具：
运行自动化补丁工具注入加固补丁：
```bash
# 默认使用配置向导或直接运行
sudo patch-easyconnect
# 或通过环境变量传入自定义网关与凭据
sudo VPN_HOST="113.108.13.8:4430" VPN_USER="42187" VPN_PASS="xxx" patch-easyconnect
```

### 开机权限防篡改固化：
通过 `/etc/tmpfiles.d/easyconnect.conf` 在每次系统开机时强制重置目录权限（0777）与凭据权限（0666），彻底解决重启后权限丢失问题。

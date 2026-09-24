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
     * 程序退出后包装脚本立即接管，自动彻底断开、杀除底层 SUID 进程并重新物理锁死。
2. **对抗性锁定保证**：
   * 在软件未使用期间，`aTrustDaemon.service` 和 `EasyMonitor.service` 符号链接始终指向 `/dev/null`；
   * 即使执行系统全量升级（`pacman -Syu`），包管理器也无法重新自动启用服务。

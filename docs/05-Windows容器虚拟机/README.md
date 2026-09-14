# 05 - Windows 容器虚拟机 (Windows VM & Enterprise Apps)

本专栏记录在 Omarchy (Arch Linux + Hyprland) 环境下，通过 Docker 运行轻量化 Windows 虚拟机（`omarchy-windows-vm` / `dockurr/windows`）的**安装加速、宿主机网络完全隔离、Windows 11 极致性能精简、远程客户端崩溃排查与企业微信/深信服 VPN 稳定适配实践**。

---

## 核心文档索引

| 文档名称 | 核心解决问题 | 适用场景 |
| :--- | :--- | :--- |
| [**Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md**](./Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md) | • Docker 与 Windows 11 ISO 5GB 镜像下载加速与本地注入<br>• 宿主机策略路由 `pref 8990` 与 Clash TUN 双轨完全隔离持久化<br>• 深信服 VPN 报“网络连接错误”排查与真实 DNS 解绑<br>• 企业微信 15 小时时差与北京时间校正<br>• Windows 11 视觉特效、流氓服务 (`SysMain`/`WSearch`/`DiagTrack`) 极致精简<br>• 一键 PowerShell 优化脚本与 Btrfs 秒级 CoW 快照备份 | **核心综合手册**<br>涵盖从安装避坑、网络隔离到性能极致优化的全流程 |
| [**Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（从xfreerdp3迁移至sdl-freerdp3深度实录）.md**](./Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（从xfreerdp3迁移至sdl-freerdp3深度实录）.md) | • 虚拟机窗口突然消失闪退真实根因排查（QEMU 仍在运行，并非虚拟机崩溃）<br>• GDB 与 Core Dump 定位 FreeRDP 3.31.1 `xf_cliprdr.c:396` 空指针解引用与 SIGSEGV<br>• 跨系统剪贴板格式同步触发回归缺陷机理剖析<br>• 一键迁移至官方新一代 `sdl-freerdp3` 客户端彻底免疫 Bug<br>• Omarchy 官方 Issue [#11789](https://github.com/omacom/omarchy/issues/11789) 协同记录 | **深度故障复盘**<br>解决远程桌面窗口在使用剪贴板或多应用切换时频繁闪退的致命问题 |

---

## 涉及的关键技术与系统组件

1. **宿主机端 (Omarchy Linux)**：
   * `dockurr/windows`：KVM/QEMU 容器化虚拟化引擎；
   * `sdl-freerdp3`：基于 SDL2/SDL3 的官方新一代 RDP 客户端，彻底替代易崩溃的 `xfreerdp3`；
   * `ip rule`：Linux 内核高级策略路由（优先级 `8990/8991` 绕过 Clash TUN）；
   * `systemd`：`docker-bypass-clash.service` 开机持久化注入；
   * `Btrfs reflink`：虚拟机物理镜像（`~/.windows/data.img`）秒级写时复制快照。
2. **虚拟机端 (Windows 11)**：
   * PowerShell 自动化调优引擎；
   * 视觉效果与窗口动画性能优先（提升 FreeRDP 传输速率）；
   * 停用三大高磁盘 I/O 抢占服务 (`SysMain`, `WSearch`, `DiagTrack`)；
   * 深信服 EasyConnect / aTrust SSL VPN 与 Athena EPP 安全联动。

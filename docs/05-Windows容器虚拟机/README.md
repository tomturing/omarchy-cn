# 05 - Windows 容器虚拟机 (Windows VM & Enterprise Apps)

本专栏记录在 Omarchy (Arch Linux + Hyprland) 环境下，通过 Docker 运行轻量化 Windows 虚拟机（`omarchy-windows-vm` / `dockurr/windows`）的**安装加速、宿主机网络完全隔离、Windows 11 极致性能精简、远程客户端崩溃排查与企业微信/深信服 VPN 稳定适配实践**。

---

## 核心文档索引

| 文档名称 | 核心解决问题 | 适用场景 |
| :--- | :--- | :--- |
| [**Windows虚拟机剪贴板乱码根治与F1截图标注光标穿透修复指南（FreeRDP字符集协商、CF_DIB图像桥接与Tensaku选区加固实录）.md**](./Windows虚拟机剪贴板乱码根治与F1截图标注光标穿透修复指南（FreeRDP字符集协商、CF_DIB图像桥接与Tensaku选区加固实录）.md) | • 从 Windows 复制文本到 Omarchy 宽字符错位与乱码根治（如 `Ahzy@2026.` 变 `桁祺㉀㈰⸶`）<br>• FreeRDP 剪贴板通道 `use-selection:CLIPBOARD` 与 UTF-8 Locale 强制约束<br>• F1 截图标注 Tensaku 初始工具矩形锁定与 LayerShell 合成器光标唤醒（消除 I-beam 穿透）<br>• Linux `image/png` 向 Windows `CF_DIB` 图像剪贴板桥接与跨端秒级粘贴<br>• Windows 虚拟机端 `rdpclip.exe` 一键自愈脚本 | **交互体验与稳定性加固**<br>彻底解决跨系统文本乱码、截图光标残留及图片无法粘贴至 Windows 内部的核心痛点 |
| [**Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md**](./Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md) | • Docker 与 Windows 11 ISO 5GB 镜像下载加速与本地注入<br>• 宿主机策略路由 `pref 8990` 与 Clash TUN 双轨完全隔离持久化<br>• 深信服 VPN 报“网络连接错误”排查与真实 DNS 解绑<br>• 企业微信 15 小时时差与北京时间校正<br>• Windows 11 视觉特效、流氓服务 (`SysMain`/`WSearch`/`DiagTrack`) 极致精简<br>• 一键 PowerShell 优化脚本与 Btrfs 秒级 CoW 快照备份 | **核心综合手册**<br>涵盖从安装避坑、网络隔离到性能极致优化的全流程 |
| [**Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（sdl-freerdp3黑边避坑与xfreerdp3源码级修补终极实录）.md**](./Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（sdl-freerdp3黑边避坑与xfreerdp3源码级修补终极实录）.md) | • 虚拟机窗口突然消失闪退真实根因排查（QEMU 仍在运行，并非虚拟机崩溃）<br>• GDB 与 Core Dump 定位 FreeRDP 3.31.1 `xf_cliprdr.c:396` 空指针解引用与 SIGSEGV<br>• 盲目切换 `sdl-freerdp3` 引发的 Hyprland 1.25x 分数缩放黑边与画面压缩避坑<br>• 官方单行补丁重新编译 `freerdp` 实现 100% 满屏无黑边且剪贴板彻底稳定的终极方案<br>• Omarchy 官方 Issue [#11789](https://github.com/omacom/omarchy/issues/11789) 及追踪实测反馈协同记录 | **深度故障与避坑实录**<br>解决远程桌面窗口在使用剪贴板或多应用切换时频繁闪退的致命问题 |
| [**Windows容器虚拟机性能与宿主机内存全栈治理实录（16GB宿主机防OOM与分级Swap架构、Btrfs碎片整理、6vCPU扩容与秒级唤醒工作流）.md**](./Windows容器虚拟机性能与宿主机内存全栈治理实录（16GB宿主机防OOM与分级Swap架构、Btrfs碎片整理、6vCPU扩容与秒级唤醒工作流）.md) | • 16GB 宿主机分配 6GB 运行 Windows 11 时的内存颠簸与 Chromium 渲染器退出代码 9（SIGKILL）排查<br>• 破除误区：确认非系统内核 OOM Killer，而是无限制 zram 膨胀（8.8GB）反吞噬物理内存引发看门狗强杀<br>• 4GB 封顶 zram + NVMe swapfile 分级 Swap 溢出架构治理<br>• THP `madvise` 虚胖脱水、KSM 内存去重与桌面 Session 1GB 软保护<br>• Btrfs 虚拟镜像在线碎片整理（碎片暴降 92%）、QEMU writeback 缓存与 VirtIO Ballooning 注入<br>• 开机 20 秒冷启动耗时第一性原理拆解、6 vCPU 超线程扩容与“休眠挂起”0 秒瞬开工作流 | **内存与性能全栈深度实录**<br>彻底解决宿主机多重应用并发内存挤压、冷启动延迟与 I/O 寻道瓶颈 |

---

## 涉及的关键技术与系统组件

1. **宿主机端 (Omarchy Linux)**：
   * `dockurr/windows`：KVM/QEMU 容器化虚拟化引擎；
   * `xfreerdp3 (Patched & Hardened)`：应用了官方修复与 UTF-8 语言加固的 X11/Wayland 客户端，兼备 1.25x 满屏无黑边、剪贴板零乱码与图像跨端互通；
   * `Tensaku`：基于 Rust 的现代 Wayland 批注工具，集成防光标穿透与指定 `image/png` 导出；
   * `ip rule`：Linux 内核高级策略路由（优先级 `8990/8991` 绕过 Clash TUN）；
   * `systemd`：`docker-bypass-clash.service` 开机持久化注入；
   * `Btrfs reflink`：虚拟机物理镜像（`~/.windows/data.img`）秒级写时复制快照。
2. **虚拟机端 (Windows 11)**：
   * PowerShell 自动化调优引擎；
   * `rdpclip.exe` 守护与一键自愈机制；
   * 视觉效果与窗口动画性能优先（提升 FreeRDP 传输速率）；
   * 停用三大高磁盘 I/O 抢占服务 (`SysMain`, `WSearch`, `DiagTrack`)；
   * 深信服 EasyConnect / aTrust SSL VPN 与 Athena EPP 安全联动。

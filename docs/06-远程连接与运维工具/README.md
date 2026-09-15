# 06 - 远程连接与运维工具 (Remote & DevOps Tools)

本目录收录 Omarchy (Arch Linux + Hyprland) 环境下 SSH 远程连接、服务器会话管理、文件传输与运维终端的方案选型、调优指南与踩坑排查。

---

## 收录文档

1. [**Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）**](./Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）.md)
   * **平铺玩家天花板组合**：Foot 原生 Wayland 极速终端 + `sshs` 会话管理器 + Hyprland Spotlight 居中浮动窗口 + `Super+Shift+Enter` 全局呼出（解绑冲突键避坑）；
   * **WindTerm 全功能图形终端深度调优**：解决 XWayland 多窗格平铺冲突、systemd OSC 3008 转义序列提示符乱码与 Fcitx5 中文输入法适配。
2. [**Remmina与FreeRDP远程Windows桌面无响应排查与调优（NLA认证假死、krb5.conf超时根治与自适应分辨率实录）**](./Remmina与FreeRDP远程Windows桌面无响应排查与调优（NLA认证假死、krb5.conf超时根治与自适应分辨率实录）.md)
   * **NLA 认证假死排查**：分析 Arch Linux 默认 `/etc/krb5.conf` 占位域 `ATHENA.MIT.EDU` 导致的 60~80 秒 Kerberos 超时风暴，提供一键 sed 修复使协商耗时骤降至 0.26 秒；
   * **凭据与证书避坑**：剖析 Quick Connect 顶栏直连缺失凭据的交互陷阱，规范新建 Profile 与自签名证书忽略；
   * **自适应分辨率与黑边消除**：详解 RDP 客户端主导的虚拟视口协商原理，利用 Remmina 动态分辨率图标（左侧第 7 个）与 Profile 固化，彻底根除低分辨率居中黑边。

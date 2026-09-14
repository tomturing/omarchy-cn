# 06 - 远程连接与运维工具 (Remote & DevOps Tools)

本目录收录 Omarchy (Arch Linux + Hyprland) 环境下 SSH 远程连接、服务器会话管理、文件传输与运维终端的方案选型、调优指南与踩坑排查。

---

## 收录文档

1. [**Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）**](./Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）.md)
   * **平铺玩家天花板组合**：Foot 原生 Wayland 极速终端 + `sshs` 会话管理器 + Hyprland Spotlight 居中浮动窗口 + `Super+Shift+Enter` 全局呼出（解绑冲突键避坑）；
   * **WindTerm 全功能图形终端深度调优**：解决 XWayland 多窗格平铺冲突、systemd OSC 3008 转义序列提示符乱码与 Fcitx5 中文输入法适配。

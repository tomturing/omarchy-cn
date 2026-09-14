# 01 - 输入法与按键 (Input & Keyboard)

本目录记录在 Omarchy (Arch Linux + Hyprland) 环境下，针对 **Fcitx5 + Rime（雾凇拼音）** 的完整调优实践、踩坑记录与底层排查方案。

---

## 核心文档索引

| 文档名称 | 核心解决问题 | 适用场景 |
| :--- | :--- | :--- |
| [**Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md**](./Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md) | • 单按 Shift 松开切换中英文（Windows 原生手感）<br>• 长按 Shift 组合键（如 `Shift+1` 输入 `!`）绝不误切<br>• 统一标点映射（中英文均输出半角 `!`）<br>• 终端新开 100% 默认英文模式且随时可切中文<br>• 密码场景（sudo/su、系统锁屏、Polkit 提权弹窗、网页密码框）全链路 100% 纯英文直通 | **主要部署指南**<br>适合在全新设备或现有设备上快速落地全套调优配置 |
| [**物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md**](./物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md) | • 剖析为何软件模拟按键有效，但真实物理键盘按 Shift 无反应<br>• Linux XKB 驱动层 `shift:both_capslock_cancel` 规则如何拦截吃掉 KeyUp 信号<br>• Rime `key_binder`（按下即触发）与 `ascii_composer`（状态机松开触发）机制对比 | **深度排查与原理解析**<br>适合遇到输入法怪异按键行为、深入理解 Linux 输入栈原理时查阅 |

---

## 涉及的核心系统配置文件

* `~/.config/hypr/input.lua` 或 `~/.config/hypr/hyprland.conf`：物理键盘驱动参数（移除 XKB 冲突规则）
* `~/.config/fcitx5/config`：Fcitx5 全局行为（应用程序独立隔离记忆、密码框禁用输入法）
* `~/.config/fcitx5/profile`：输入法列表与降级布局（必须包含 `keyboard-us` 才能使密码保护生效）
* `~/.local/share/fcitx5/rime/default.custom.yaml` 与 `rime_ice.custom.yaml`：Rime 引擎状态机补丁
* `~/.local/share/fcitx5/rime/fcitx5.yaml`：桌面组件应用级模式配置
* `~/.bashrc`：终端交互式会话英文初始化 Hook 与密码命令包装

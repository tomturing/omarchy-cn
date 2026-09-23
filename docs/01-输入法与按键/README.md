# 01 - 输入法与按键 (Input & Keyboard)

本目录记录在 Omarchy (Arch Linux + Hyprland) 环境下，针对 **Fcitx5 + Rime（雾凇拼音）** 的完整调优实践、踩坑记录与底层排查方案。

---

## 核心文档索引

| 文档名称 | 核心解决问题 | 适用场景 |
| :--- | :--- | :--- |
| [**Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md**](./Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md) | • 单按 Shift 松开切换中英文（Windows 原生手感）<br>• 长按 Shift 组合键（如 `Shift+1` 输入 `!`）绝不误切<br>• 统一标点映射（中英文均输出半角 `!`）<br>• 终端新开 100% 默认英文模式且随时可切中文<br>• 密码场景（sudo/su、系统锁屏、Polkit 提权弹窗、网页密码框）全链路 100% 纯英文直通 | **主要部署指南**<br>适合在全新设备或现有设备上快速落地全套调优配置 |
| [**物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md**](./物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md) | • 剖析为何软件模拟按键有效，但真实物理键盘按 Shift 无反应<br>• Linux XKB 驱动层 `shift:both_capslock_cancel` 规则如何拦截吃掉 KeyUp 信号<br>• Rime `key_binder`（按下即触发）与 `ascii_composer`（状态机松开触发）机制对比 | **深度排查与原理解析**<br>适合遇到输入法怪异按键行为、深入理解 Linux 输入栈原理时查阅 |
| [**Omarchy高频快捷键与F1截图标注全攻略（Hyprland按键拓扑、Tensaku现代标注集成与一键配置脚本）.md**](./Omarchy高频快捷键与F1截图标注全攻略（Hyprland按键拓扑、Tensaku现代标注集成与一键配置脚本）.md) | • Hyprland Lua 快捷键加载拓扑与 `hl.unbind` 冲突消除法则<br>• 汇总整理终端、IDE、浏览器、Spotlight 与工作区高频核心快捷键清单<br>• Tensaku 现代截图工具深度整合（F1 一键选区、Space 窗口吸附、箭头/方框/马赛克标注、Enter/复制自动关闭窗口并回写剪贴板） | **日常操作与效率进阶**<br>打造类微信/Snipaste无缝截图体验，避免快捷键重复触发冲突 |
| [**Omarchy离线语音输入识别配置指南（Voxtype与Whisper普通话模型、RTX显卡GPU加速及剪贴板直通）.md**](./Omarchy离线语音输入识别配置指南（Voxtype与Whisper普通话模型、RTX显卡GPU加速及剪贴板直通）.md) | • 100% 本地离线语音识别转文字（Whisper 普通话模型）<br>• 破解蓝牙耳机 A2DP/HFP 切换延迟引发的静音幻觉（"请按赞、订阅、转发"）<br>• 解决 Wayland 虚拟键盘事件丢失与吞字问题（`mode = "paste"` 剪贴板直通）<br>• NVIDIA RTX 2060 6GB 显存分配策略与 Vulkan 亚秒级硬件加速 | **智能语音输入必备**<br>提供 Super+Ctrl+X 切换与 F9 对讲机级语音转文字实操指南 |
| [**Winmaxle无线蓝牙双模键盘在Omarchy下的HID驱动剖析、陀螺仪飞鼠激活与Hyprland定制按键映射实战指南（XKB层KP_Add映射Super_R、专用快捷键绑定与零冲突调优）.md**](./Winmaxle无线蓝牙双模键盘在Omarchy下的HID驱动剖析、陀螺仪飞鼠激活与Hyprland定制按键映射实战指南（XKB层KP_Add映射Super_R、专用快捷键绑定与零冲突调优）.md) | • 破解迷你键盘蓝牙连接打字正常但陀螺仪空中飞鼠“假死”的硬件防误触锁机制<br>• 证伪“驱动缺失”与“外接罗技鼠标冲突”假说，剖析 Linux uhid 累加模型<br>• 纯用户态 Python/GTK3 事件捕获器，零 root 识别非常规硬件 Keycode<br>• 纯用户态 XKB `superkpad(super_r)` 将小键盘加号 `<KPAD>` 升格为 `Super_R` 修饰键<br>• 4 大定制多媒体物理按键直连绑定终端、AI 助手与浏览器 Scratchpad | **紧凑外设与飞鼠实战**<br>专为迷你无线双模外设打造的高效平铺桌面单手操作优化指南 |

---

## 涉及的核心系统配置文件

* `~/.config/hypr/input.lua` 或 `~/.config/hypr/hyprland.conf`：物理键盘驱动参数（移除 XKB 冲突规则）
* `~/.config/hypr/local.lua` 与 `bindings.lua`：自定义快捷键拓扑与 `hl.unbind` 规则
* `~/.local/bin/tensaku-capture`：F1 截图包装器（含 `--early-exit` 复制自动关闭退出）与剪贴板回写逻辑
* `~/.config/tensaku/config.toml`：Tensaku 全局配置（批注字体尺寸与 `early-exit` 自动退出）
* `~/.config/fcitx5/config`：Fcitx5 全局行为（应用程序独立隔离记忆、密码框禁用输入法）
* `~/.config/fcitx5/profile`：输入法列表与降级布局（必须包含 `keyboard-us` 才能使密码保护生效）
* `~/.local/share/fcitx5/rime/default.custom.yaml` 与 `rime_ice.custom.yaml`：Rime 引擎状态机补丁
* `~/.config/voxtype/config.toml` 与 `~/.config/systemd/user/voxtype.service`：离线语音识别守护进程与 Vulkan 加速单元
* `~/.local/share/voxtype/models/`：Whisper GGUF/GGML 模型存放目录
* `~/.bashrc`：终端交互式会话英文初始化 Hook 与密码命令包装

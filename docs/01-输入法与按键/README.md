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
| [**Fcitx5在Wayland下退格跳行首、回车空格误删与候选框漂移排查调优指南（Preedit预编辑机制、WaylandV2虚拟键盘常驻、字号与高亮黑底定制）.md**](./Fcitx5在Wayland下退格跳行首、回车空格误删与候选框漂移排查调优指南（Preedit预编辑机制、WaylandV2虚拟键盘常驻、字号与高亮黑底定制）.md) | • 彻底剖析 Monaco 虚拟编辑器双状态机推导算法与退格跳行首、回车空格误删机理<br>• 单引擎（Rime）常驻架构彻底消灭 Inactive 休眠与 `keyboard-us` 备选项，免除每次手动按 `Ctrl+Space` 救场<br>• CodeBuddy 解除 `Ctrl+Space` 抢键劫持与 `ShareInputState=All` 全局状态归一化<br>• 解密 Wayland 惰性光标上报导致首字候选框漂移在左侧的底层物理机理<br>• 激活 `Ctrl+Alt+P` 动态预编辑切换，经典 UI 字体调大至 12pt 与首选候选词纯黑背景高对比度定制 | **输入体验与疑难排查必备**<br>彻底攻克 Wayland 桌面下拼音输入法跳跃、误吞、IDE 死锁与排版漂移顽疾 |

---

## 涉及的核心系统配置文件

* `~/.config/hypr/input.lua` 或 `~/.config/hypr/hyprland.conf`：物理键盘驱动参数（移除 XKB 冲突规则）
* `~/.config/hypr/local.lua` 与 `bindings.lua`：自定义快捷键拓扑与 `hl.unbind` 规则
* `~/.local/bin/tensaku-capture`：F1 截图包装器（含 `--early-exit` 复制自动关闭退出）与剪贴板回写逻辑
* `~/.config/tensaku/config.toml`：Tensaku 全局配置（批注字体尺寸与 `early-exit` 自动退出）
* `~/.config/fcitx5/config`：Fcitx5 全局行为（全局统一共享状态 `ShareInputState=All`、`TogglePreedit` 动态热键）
* `~/.config/fcitx5/profile`：输入法列表（单引擎常驻架构，仅保留 `rime` 消除休眠态与状态孤岛）
* `~/.config/CodeBuddy CN/User/keybindings.json`：CodeBuddy 用户按键配置（解绑 `Ctrl+Space` 抢键劫持）
* `~/.local/share/fcitx5/rime/default.custom.yaml` 与 `rime_ice.custom.yaml`：Rime 引擎状态机补丁
* `~/.config/voxtype/config.toml` 与 `~/.config/systemd/user/voxtype.service`：离线语音识别守护进程与 Vulkan 加速单元
* `~/.local/share/voxtype/models/`：Whisper GGUF/GGML 模型存放目录
* `~/.bashrc`：终端交互式会话英文初始化 Hook 与密码命令包装

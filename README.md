# Omarchy 中文环境调优与避坑指南 (omarchy-cn)

<p align="center">
  <b>专注于 Arch Linux + Hyprland (Omarchy) 桌面中文使用体验的配置调优、踩坑排查与自动化 Agent 技能库</b>
</p>

---

## 📖 项目简介

[Omarchy](https://github.com/basecamp/omarchy) 是一套极具生产力的 Arch Linux + Hyprland 开箱即用配置系统。然而在真实的**中文桌面日常、企业办公与远程运维环境**下，常常会面临诸多特有的挑战：

* 输入法 Shift 键在驱动层与状态机层冲突导致误切、连打感叹号 `!！！！` 或物理键盘失效；
* 新开终端窗口不能默认英文、应用间输入状态相互污染；
* 终端敲 `sudo` 或图形提权弹窗输密码时混入拼音候选框；
* 汉字字符默认 fallback 显示为日文字形（门、骨、复等字异体）；
* 微信、企业微信 (WeCom) 等国内日常办公软件在 Wayland / XWayland 下的缩放、输入法光标跟随与托盘问题；
* 平铺桌面下多服务器 SSH 会话管理与文件传输工具链割裂，快捷键与系统默认热键冲突；
* WindTerm 等全功能终端在现代 Linux 下出现致命的 systemd OSC 3008 提示符乱码与 XWayland 窗格挤压。

本项目旨在系统性记录并沉淀**经过真实硬件端到端验证的调优指南**，提供开箱即用的配置模板，并严格遵循 `anthropics/skills` 官方规范构建 AI Agent Skill，让用户和 AI 编码助手均能一键调用与排错。

---

## 📂 仓库目录规划与知识库导航

```text
omarchy-cn/
├── docs/                                          # 核心调优与避坑指南文档库
│   ├── 01-输入法与按键/                            # Fcitx5 + Rime 全链路调优、快捷键与语音识别
│   │   ├── Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md
│   │   ├── 物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md
│   │   ├── Omarchy高频快捷键与F1截图标注全攻略（Hyprland按键拓扑、Tensaku现代标注集成与一键配置脚本）.md
│   │   ├── Omarchy离线语音输入识别配置指南（Voxtype与Whisper普通话模型、RTX显卡GPU加速及剪贴板直通）.md
│   │   └── README.md
│   ├── 02-中文字体与本地化/                         # 系统 Locale、思源字体优先级、Fontconfig 避坑
│   │   └── README.md
│   ├── 03-国产办公软件适配/                         # 企业微信 (WeCom)、微信、飞书、钉钉、WPS
│   │   └── README.md
│   ├── 04-桌面环境与终端显示/                       # Hyprland 规则、Quickshell 顶栏实时网速、终端中文字符对齐
│   │   ├── Omarchy顶部栏居中实时网速显示配置指南（Quickshell组件开发、流量无损采集与一键部署脚本）.md
│   │   └── README.md
│   ├── 05-Windows容器虚拟机/                        # Windows 11 容器虚拟机、网络隔离与性能极致精简
│   │   ├── Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md
│   │   ├── Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（sdl-freerdp3黑边避坑与xfreerdp3源码级修补终极实录）.md
│   │   └── README.md
│   └── 06-远程连接与运维工具/                        # SSH 选型、平铺天花板组合、WindTerm避坑
│       ├── Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）.md
│       └── README.md
├── skills/                                        # Agent Skill 规范目录 (anthropics/skills)
│   ├── omarchy-chinese-environment/               # 输入法与本地化全链路诊断技能
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── check_ime_env.sh
│   │       └── apply_input_optimizations.sh
│   ├── omarchy-desktop-tweaks/                    # 桌面快捷键拓扑、F1 Tensaku 截图标注与顶栏居中网速组件技能
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── check_desktop_tweaks.sh
│   │       ├── setup_shortcuts_and_f1.sh
│   │       └── setup_topbar_netspeed.sh
│   ├── omarchy-voice-dictation/                   # 离线语音输入转文字技能（Voxtype + Whisper GPU加速）
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── check_voxtype.sh
│   │       └── setup_voxtype.sh
│   ├── omarchy-windows-vm-tuning/                 # Windows 虚拟机网络隔离与性能精简技能
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── check_vm_network.sh
│   │       ├── enable_docker_bypass_clash.sh
│   │       ├── fix_vm_freerdp_crash.sh
│   │       ├── rebuild_freerdp_with_patch.sh
│   │       ├── optimize_windows_vm.ps1
│   │       └── snapshot_vm_btrfs.sh
│   └── omarchy-ssh-management/                    # SSH 运维管理与终端避坑技能
│       ├── SKILL.md
│       └── scripts/
│           ├── check_ssh_env.sh
│           ├── install_ssh_manager.sh
│           ├── fix_windterm_prompt.sh
│           └── set_windterm_icon.sh
└── templates/                                     # 开箱即用的配置文件片段
    ├── default.custom.yaml                        # Rime 全局方案补丁模板
    ├── rime_ice.custom.yaml                       # 雾凇拼音专属方案补丁模板
    ├── fcitx5.yaml                                # 桌面组件与密码应用级策略模板
    ├── fcitx5-profile                             # 包含 keyboard-us 降级布局的 profile 模板
    ├── fcitx5-config                              # 全局配置模板（含 ActiveByDefault 与 TriggerKeys）
    ├── rime.conf                                  # Rime 独立会话隔离配置模板（解除全局会话共享）
    ├── punctuation.yaml                           # Windows 体验标点直出模板（零候选弹窗）
    ├── bashrc_ime_snippet.sh                      # 终端默认英文与 sudo 包装 Hook 片段
    ├── hypr_input_snippet.lua                     # 物理键盘驱动参数配置片段
    ├── tensaku-capture.sh                         # Tensaku F1 智能截图标注包装脚本
    ├── hypr_shortcuts_snippet.lua                 # Hyprland 常用快捷键与 F1 绑定模板
    ├── netspeed/                                  # Quickshell 顶栏网速组件模板
    │   ├── manifest.json
    │   ├── netspeed.sh
    │   └── NetSpeed.qml
    ├── voxtype/                                   # Voxtype 语音识别配置模板
    │   └── config.toml
    ├── docker-bypass-clash.service                # 宿主机网络隔离 systemd 模板
    ├── enable-docker-bypass.sh                    # 宿主机网络隔离脚本模板
    ├── optimize_windows_vm.ps1                    # 虚拟机内部一键精简脚本模板
    ├── fix-cliprdr-segfault.patch                 # FreeRDP 剪贴板段错误官方单行补丁
    ├── ssh-manager                                # SSH Spotlight 快速启动脚本
    ├── hypr_ssh_windowrules.lua                   # SSH 浮动与 WindTerm 窗口规则模板
    ├── hypr_ssh_bindings.lua                      # Super+Shift+Enter 解绑与绑定模板
    └── bashrc_windterm_fix.sh                     # WindTerm OSC 3008 提示符乱码拦截模板
```

---

## 📑 核心优化指南索引

### 1. 输入法与按键优化 (`docs/01-输入法与按键`)
* [**Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）**](./docs/01-输入法与按键/Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md)
  * **Shift 键松开切换**：移除 XKB 驱动层 `shift:both_capslock_cancel` 拦截，借助 Rime `ascii_composer` 状态机实现 Windows 原生级单按松开切换体验，长按组合键（如 `Shift + 1` 输入 `!`）绝不误切；
  * **统一标点输出与零候选直出**：中英文状态下均输出标准半角感叹号 `!`；彻底修正 `\` 输出顿号 `、`、`>` 输出书名号 `》` 等标点弹出多选悬浮窗和 Enter 键输出 ASCII 字符的异常交互；
  * **终端默认英文**：通过 Fcitx5 `ShareInputState=Program` 隔离与 `~/.bashrc` 轻量级异步 DBus Hook，实现新开终端 100% 默认英文且随时单按 Shift 切中文；
  * **密码框全场景纯英文直通（双重闭环保障）**：
    * 深度揭秘并修复两大隐蔽陷阱：Fcitx5 底层 `AllowInputMethodForPassword=False` 必须依赖在输入法列表中显式配置 `keyboard-us` 降级布局；以及 `fcitx5-rime` 源码默认硬编码 `SharedStatePolicy::All` 导致全局会话串用绕过 `app_options` 的问题（配置 `conf/rime.conf` 解除共享）；
    * 深度修复 Omarchy Quickshell Polkit 提权弹窗缺少 `inputMethodHints` 导致 Wayland 协议无法识别密码框的 QML 缺陷；
    * 终端 `sudo`/`su`/`pkexec` 预触发英文切换；
    * 锁屏界面（`Super+Ctrl+L`）与 Polkit 图形提权弹窗 100% 纯英文输入，彻底根除输密码弹中文候选框问题。
* [**物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）**](./docs/01-输入法与按键/物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md)
  * 深度技术复盘：为何虚拟按键测试通过而物理键盘无效？详细分析从物理按键、Linux XKB 内核驱动、Wayland 合成器到 Fcitx5/Rime 内部状态机的全链路事件传递。
* [**Omarchy高频快捷键与F1截图标注全攻略（Hyprland按键拓扑、Tensaku现代标注集成与一键配置脚本）**](./docs/01-输入法与按键/Omarchy高频快捷键与F1截图标注全攻略（Hyprland按键拓扑、Tensaku现代标注集成与一键配置脚本）.md)
  * **Hyprland Lua 按键拓扑与解绑法则**：剖析 Omarchy `default.hypr` 与用户级 `local.lua` 的继承层级，强调必须调用 `hl.unbind` 消除双重触发（如同时打开 SSH 与浏览器）；
  * **高频快捷键拓扑清单**：汇总应用启动（`Super+A` IDE / `Super+B` 浏览器 / `Super+Return` 终端）、窗口操控、跨屏移动与全系统锁屏标准按键；
  * **Tensaku 现代截图深度整合**：打造看齐微信/Snipaste的截图体验，实现 F1 一键选区、Space 窗口吸附、箭头/矩形/马赛克标注、S 键长截图与 Enter 键自动复制到剪贴板。
* [**Omarchy离线语音输入识别配置指南（Voxtype与Whisper普通话模型、RTX显卡GPU加速及剪贴板直通）**](./docs/01-输入法与按键/Omarchy离线语音输入识别配置指南（Voxtype与Whisper普通话模型、RTX显卡GPU加速及剪贴板直通）.md)
  * **100% 本地离线识别**：部署 Whisper Small 普通话离线模型，告别云端 API 依赖与隐私泄漏；
  * **蓝牙耳机静音幻觉攻克**：深入解决蓝牙 A2DP $\to$ HFP 切换延迟导致的无声录音与 YouTube 字幕幻觉（"请按赞、订阅、转发"）；
  * **Wayland 虚拟按键防吞字**：揭秘 `mode = "type"` 在 Electron/Fcitx5 下字符被拦截吞掉的机理，切换为 `mode = "paste"` 剪贴板直通实现 100% 零漏字；
  * **RTX 2060 6GB 显存兼顾策略**：`voxtype-vulkan` 硬件加速将识别延迟从 CPU 的 6 秒压缩至 850 毫秒，且显存仅占 466MB，与本地大模型（`llama-server`）稳定共存。

### 2. 桌面环境与终端显示 (`docs/04-桌面环境与终端显示`)
* [**Omarchy顶部栏居中实时网速显示配置指南（Quickshell组件开发、流量无损采集与一键部署脚本）**](./docs/04-桌面环境与终端显示/Omarchy顶部栏居中实时网速显示配置指南（Quickshell组件开发、流量无损采集与一键部署脚本）.md)
  * **Quickshell 现代组件架构**：阐明 Omarchy 抛弃传统 Waybar、全面拥抱 QtQuick/QML Quickshell 的技术演进；
  * **`/proc/net/dev` 极轻量流式采集器**：0% CPU 占用无损差值计算，自动过滤虚拟接口与 Docker 网桥，精准锚定主物理网卡；
  * **交互式 QML 顶栏挂件**：单击即时切换简略模式（`12K 156K`）与精细模式（`↑ 12.4 KB/s ↓ 156.8 KB/s`），悬浮气泡查看接口名与累计网络总吞吐；
  * **`shell.json` 居中插槽优雅接入**：修改 `sections.center` 数组动态挂载插件，提供单行一键安装与平滑重启脚本。

### 3. Windows 容器虚拟机调优 (`docs/05-Windows容器虚拟机`)
* [**Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）**](./docs/05-Windows容器虚拟机/Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md)
  * **下载加速与 ISO 注入**：剖析 Docker 拉取慢与 5GB Windows 11 ISO 在线下载卡顿根因，提供本地一键注入直接跳过下载的方案；
  * **网络隔离与 Clash 防互扰**：
    * 深度解决 Clash TUN 模式 Fake-IP（`198.18.x.x`）导致深信服 VPN（EasyConnect / aTrust）报“网络连接错误”的问题；
    * 宿主机注入内核策略路由 `pref 8990`，强制将 Docker 虚拟机流量直通物理网卡路由表（main 表），并配置 systemd 开机持久化；
    * 宿主机容器编排层（`docker-compose.yml` / `daemon.json`）直接解耦纯净公网 DNS（`223.5.5.5` / `119.29.29.29`），从源头彻底根除 Fake-IP 冲突导致的外网超时假死（`ERR_TIMED_OUT`、微软语言包 `0x80240438`），实现虚拟机启动即用、无需在 Windows 敲命令；校正北京时间 UTC+8 消除企业微信 15 小时时差；
  * **Windows 11 极致性能精简**：
    * 100% 可逆、纯非破坏性优化理念；
    * 一键 PowerShell 脚本彻底禁用高 I/O 争抢服务（`SysMain`、`WSearch`、`DiagTrack`），切换视觉特效为性能优先，关闭小组件与休眠；
    * 空闲 CPU 从 50%+ 降至 0%~2%，静态内存降至 1.8GB，FreeRDP 操作极度跟手；
  * **Btrfs 秒级 CoW 快照备份**：利用写时复制特性，0.1 秒完成虚拟磁盘快照备份与还原，零额外物理磁盘空间占用。
* [**Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（sdl-freerdp3黑边避坑与xfreerdp3源码级修补终极实录）**](./docs/05-Windows容器虚拟机/Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（sdl-freerdp3黑边避坑与xfreerdp3源码级修补终极实录）.md)
  * **假死排查**：窗口瞬间消失并非虚拟机崩溃，后台 QEMU 进程依然存活运行；
  * **缺陷溯源**：`coredumpctl` 与 GDB 符号化定位 `freerdp 3.31.1` 的 `xf_cliprdr.c:396` 在格式遍历时非法越界，导致 SIGSEGV 段错误闪退；
  * **避坑大陷阱**：实测揭示盲目切换至 `sdl-freerdp3` 会在 Hyprland 1.25x 等分数缩放下产生严重的黑边（Letterboxing）与分辨率失真，阐明官方坚守 `xfreerdp3` 的底层缘由；
  * **终极完美方案**：保留 `xfreerdp3` 100% 满屏无黑边渲染，注入官方单行补丁重编 `freerdp`，兼得极致显示与坚如磐石的剪贴板稳定性；
  * **开源协同**：向 Omarchy 官方提交 Issue [#11789](https://github.com/omacom/omarchy/issues/11789) 及追加实测反馈。

### 4. 远程连接与运维工具 (`docs/06-远程连接与运维工具`)
* [**Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）**](./docs/06-远程连接与运维工具/Omarchy下SSH高效运维方案选型（平铺天花板TUI组合与WindTerm避坑深度指南）.md)
  * **平铺玩家天花板组合**：
    * 原生 Wayland Foot 终端 + `sshs`（读取标准 `~/.ssh/config`，实时模糊检索）+ Spotlight 居中浮动窗口（`960x600`）；
    * 深度解决 Omarchy 预置快捷键冲突：显式调用 `hl.unbind("SUPER + SHIFT + RETURN")` 根除同时触发默认浏览器的 Bug；
    * 搭配 `yazi` / `rsync` / `sshfs` 构建完全解耦、零鼠标依赖的高效运维链路；
  * **WindTerm 方案深度调优与避坑**：
    * 剖析现代 systemd Shell Integration 注入 OSC 3008 上下文转义序列导致 WindTerm 提示符出现 `3008;...` / `133;A` 严重乱码的底层根因；
    * 提供 `~/.bashrc` 细粒度环境检测补丁，在保障其他原生终端功能的同时彻底根治 WindTerm 乱码；
    * 配置 Hyprland 浮动与工作区隔离规则，规避 XWayland 多窗格平铺挤压；
    * 解决 XWayland 下 Qt5 下拉弹窗指针抓取（Pointer Grab）失效导致鼠标移入失焦/点击穿透，提供直接编辑 `user.sessions` 与 `session.config` 修改图标（`session.icon: session::cmd`）的优雅方案。

---

## ⚡ 快速诊断与一键调优

本项目提供了可以直接运行的诊断与自动化应用脚本：

### 1. 输入法与按键环境诊断与调优
```bash
# 诊断输入法与键盘驱动状态
bash skills/omarchy-chinese-environment/scripts/check_ime_env.sh

# 一键应用全套输入法优化配置
bash skills/omarchy-chinese-environment/scripts/apply_input_optimizations.sh
```

### 2. Windows 虚拟机网络隔离与快照工具
```bash
# 诊断虚拟机网络隔离与运行状态
bash skills/omarchy-windows-vm-tuning/scripts/check_vm_network.sh

# 宿主机一键注入网络隔离策略路由并配置自启
bash skills/omarchy-windows-vm-tuning/scripts/enable_docker_bypass_clash.sh

# 利用 Btrfs 秒级创建虚拟机物理快照备份
bash skills/omarchy-windows-vm-tuning/scripts/snapshot_vm_btrfs.sh backup

# 发生意外时一秒还原快照
bash skills/omarchy-windows-vm-tuning/scripts/snapshot_vm_btrfs.sh restore

# 一键为 FreeRDP 打入官方剪贴板单行补丁重编安装（彻底消除黑边与段错误闪退）
bash skills/omarchy-windows-vm-tuning/scripts/rebuild_freerdp_with_patch.sh
```

### 3. SSH 运维环境与终端乱码诊断
```bash
# 诊断 SSH 天花板组合与终端环境
bash skills/omarchy-ssh-management/scripts/check_ssh_env.sh

# 一键安装并配置 SSH Spotlight 浮动弹窗
bash skills/omarchy-ssh-management/scripts/install_ssh_manager.sh

# 一键修复 WindTerm 下 systemd OSC 3008 提示符乱码
bash skills/omarchy-ssh-management/scripts/fix_windterm_prompt.sh

# 一键设置 WindTerm 会话图标（绕过 XWayland 弹窗失焦）
bash skills/omarchy-ssh-management/scripts/set_windterm_icon.sh "session::cmd"
```

### 4. 桌面快捷键、F1截图标注与顶栏网速诊断调优
```bash
# 7维度全链路诊断桌面快捷键、Tensaku截图与顶栏网速组件
bash skills/omarchy-desktop-tweaks/scripts/check_desktop_tweaks.sh

# 一键安装配置 Tensaku 截图标注包装器并注入 F1 / Super+A / Super+B 快捷键
bash skills/omarchy-desktop-tweaks/scripts/setup_shortcuts_and_f1.sh

# 一键部署 Quickshell 顶栏居中实时上下行网速挂件并平滑重载
bash skills/omarchy-desktop-tweaks/scripts/setup_topbar_netspeed.sh
```

### 5. 离线语音输入转文字（Voxtype + Whisper GPU）诊断与部署
```bash
# 7维度全链路诊断 Voxtype 运行状态、Whisper 模型与 GPU 加速
bash skills/omarchy-voice-dictation/scripts/check_voxtype.sh

# 一键部署 Voxtype-Vulkan、下载 Small 普通话模型并配置剪贴板直通
bash skills/omarchy-voice-dictation/scripts/setup_voxtype.sh
```

---

## 🤖 作为 AI Agent Skill 使用 (Anthropics Skills 规范)

本项目在 `skills/` 目录下严格遵循 [anthropics/skills](https://github.com/anthropics/skills) 标准构建了五套开箱即用的 Agent Skills：
1. **`omarchy-chinese-environment`**：负责输入法按键切换、终端默认英文、密码框纯英文直通与本地化排错；
2. **`omarchy-desktop-tweaks`**：负责桌面快捷键拓扑管理、F1 Tensaku 现代截图标注集成以及 Quickshell 顶部栏居中实时网速挂件开发与部署；
3. **`omarchy-voice-dictation`**：负责 100% 本地离线语音识别转文字（Whisper 普通话模型）、RTX 显卡 Vulkan 亚秒级硬件加速、解决蓝牙耳机静音幻觉与 Wayland 虚拟键盘防吞字；
4. **`omarchy-windows-vm-tuning`**：负责 Windows 容器虚拟机网络隔离（Clash 防互扰、VPN 报错排查）、Windows 11 深度精简与 Btrfs 快照管理；
5. **`omarchy-ssh-management`**：负责 SSH 天花板组合部署、快捷键冲突排查与 WindTerm systemd OSC 3008 乱码修复。

当您使用 **Antigravity** 或 **Claude Code** 等智能编码助手时，可以直接引入该 Skill：
* **自动识别**：当用户提出“快捷键配置”、“F1截图”、“顶栏网速”、“语音输入/听写”、“SSH管理”、“WindTerm乱码”、“平铺终端选型”、“输入法无法切换”或“虚拟机网络互扰”时，Agent 会自动激活对应 Skill；
* **精准排查**：Agent 将调用内置诊断脚本扫描系统存在的冲突项并输出修复配方。

---

## 🤝 贡献与扩展规划

本项目欢迎广大 Omarchy 与 Arch Linux 中文用户共同建设！后续将持续扩充以下方向的避坑指南与最佳实践：
1. **企业微信与微信**：针对 `wechat-universal-bwrap` 与企业微信在 Wayland/Hyprland 下的托盘、截图与光标跟随适配；
2. **中文字体渲染**：Noto CJK 与 JetBrains Mono 字体混排、Fontconfig 字体优先级规避异体字；
3. **终端宽字符排版**：Foot / Ghostty / WindTerm 中文等宽对齐方案。

欢迎提交 PR 与 Issue！

---

## 📄 开源许可证

本项目基于 [MIT License](./LICENSE) 协议开源。

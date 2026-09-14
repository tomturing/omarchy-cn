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
│   ├── 01-输入法与按键/                            # Fcitx5 + Rime 全链路调优与底层排查
│   │   ├── Fcitx5与Rime雾凇拼音全场景优化配置指南（Shift键松开切换、终端与密码框自动英文）.md
│   │   ├── 物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md
│   │   └── README.md
│   ├── 02-中文字体与本地化/                         # 系统 Locale、思源字体优先级、Fontconfig 避坑
│   │   └── README.md
│   ├── 03-国产办公软件适配/                         # 企业微信 (WeCom)、微信、飞书、钉钉、WPS
│   │   └── README.md
│   ├── 04-桌面环境与终端显示/                       # Hyprland 规则、面板时间、终端中文字符对齐
│   │   └── README.md
│   ├── 05-Windows容器虚拟机/                        # Windows 11 容器虚拟机、网络隔离与性能极致精简
│   │   ├── Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md
│   │   ├── Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（从xfreerdp3迁移至sdl-freerdp3深度实录）.md
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
│   ├── omarchy-windows-vm-tuning/                 # Windows 虚拟机网络隔离与性能精简技能
│   │   ├── SKILL.md
│   │   └── scripts/
│   │       ├── check_vm_network.sh
│   │       ├── enable_docker_bypass_clash.sh
│   │       ├── fix_vm_freerdp_crash.sh
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
    ├── bashrc_ime_snippet.sh                      # 终端默认英文与 sudo 包装 Hook 片段
    ├── hypr_input_snippet.lua                     # 物理键盘驱动参数配置片段
    ├── docker-bypass-clash.service                # 宿主机网络隔离 systemd 模板
    ├── enable-docker-bypass.sh                    # 宿主机网络隔离脚本模板
    ├── optimize_windows_vm.ps1                    # 虚拟机内部一键精简脚本模板
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
  * **统一标点输出**：中英文状态下均输出标准半角感叹号 `!`；
  * **终端默认英文**：通过 Fcitx5 `ShareInputState=Program` 隔离与 `~/.bashrc` 轻量级异步 DBus Hook，实现新开终端 100% 默认英文且随时单按 Shift 切中文；
  * **密码框全场景纯英文直通**：
    * 深度解决 Fcitx5 底层 `AllowInputMethodForPassword=False` 必须依赖在输入法列表中显式配置 `keyboard-us` 降级布局的机制；
    * 终端 `sudo`/`su`/`pkexec` 预触发英文切换；
    * 锁屏界面（`Super+Ctrl+L`）与 Polkit 图形提权弹窗 100% 纯英文输入，彻底根除输密码弹中文候选框问题。
* [**物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）**](./docs/01-输入法与按键/物理键盘Shift键无响应底层排查与修复（XKB驱动拦截与Rime状态机冲突深度解析）.md)
  * 深度技术复盘：为何虚拟按键测试通过而物理键盘无效？详细分析从物理按键、Linux XKB 内核驱动、Wayland 合成器到 Fcitx5/Rime 内部状态机的全链路事件传递。

### 2. Windows 容器虚拟机调优 (`docs/05-Windows容器虚拟机`)
* [**Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）**](./docs/05-Windows容器虚拟机/Windows容器虚拟机全链路优化指南（宿主机网络隔离与Clash防互扰、Windows11极致性能精简与PowerShell一键脚本）.md)
  * **下载加速与 ISO 注入**：剖析 Docker 拉取慢与 5GB Windows 11 ISO 在线下载卡顿根因，提供本地一键注入直接跳过下载的方案；
  * **网络隔离与 Clash 防互扰**：
    * 深度解决 Clash TUN 模式 Fake-IP（`198.18.x.x`）导致深信服 VPN（EasyConnect / aTrust）报“网络连接错误”的问题；
    * 宿主机注入内核策略路由 `pref 8990`，强制将 Docker 虚拟机流量直通物理网卡路由表（main 表），并配置 systemd 开机持久化；
    * 虚拟机内活跃网卡解绑宿主机 DNS，切换为纯净公网 DNS，校正北京时间 UTC+8 消除企业微信 15 小时时差；
  * **Windows 11 极致性能精简**：
    * 100% 可逆、纯非破坏性优化理念；
    * 一键 PowerShell 脚本彻底禁用高 I/O 争抢服务（`SysMain`、`WSearch`、`DiagTrack`），切换视觉特效为性能优先，关闭小组件与休眠；
    * 空闲 CPU 从 50%+ 降至 0%~2%，静态内存降至 1.8GB，FreeRDP 操作极度跟手；
  * **Btrfs 秒级 CoW 快照备份**：利用写时复制特性，0.1 秒完成虚拟磁盘快照备份与还原，零额外物理磁盘空间占用。
* [**Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（从xfreerdp3迁移至sdl-freerdp3深度实录）**](./docs/05-Windows容器虚拟机/Windows虚拟机假死崩溃排查与FreeRDP剪贴板段错误修复（从xfreerdp3迁移至sdl-freerdp3深度实录）.md)
  * **假死排查**：窗口瞬间消失并非虚拟机崩溃，后台 QEMU 进程依然存活运行；
  * **缺陷溯源**：`coredumpctl` 与 GDB 符号化定位 `freerdp 3.31.1` 的 `xf_cliprdr.c:396` 在格式遍历时非法越界，导致 SIGSEGV 段错误闪退；
  * **官方迁移**：一键将启动器替换为官方新一代 `sdl-freerdp3`，彻底免疫剪贴板闪退，保持 100% 参数无缝兼容；
  * **开源协同**：向 Omarchy 官方提交 Issue [#11789](https://github.com/omacom/omarchy/issues/11789)，推动上游版本迭代。

### 3. 远程连接与运维工具 (`docs/06-远程连接与运维工具`)
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

# 一键修复剪贴板触发虚拟机窗口崩溃闪退（迁移至 sdl-freerdp3）
bash skills/omarchy-windows-vm-tuning/scripts/fix_vm_freerdp_crash.sh
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

---

## 🤖 作为 AI Agent Skill 使用 (Anthropics Skills 规范)

本项目在 `skills/` 目录下严格遵循 [anthropics/skills](https://github.com/anthropics/skills) 标准构建了三套可直接加载的 Agent Skills：
1. **`omarchy-chinese-environment`**：负责输入法按键切换、终端默认英文、密码框纯英文直通与本地化排错；
2. **`omarchy-windows-vm-tuning`**：负责 Windows 容器虚拟机网络隔离（Clash 防互扰、VPN 报错排查）、Windows 11 深度精简与 Btrfs 快照管理；
3. **`omarchy-ssh-management`**：负责 SSH 天花板组合部署、快捷键冲突排查与 WindTerm systemd OSC 3008 乱码修复。

当您使用 **Antigravity** 或 **Claude Code** 等智能编码助手时，可以直接引入该 Skill：
* **自动识别**：当用户提出“SSH管理”、“WindTerm乱码”、“平铺终端选型”、“输入法无法切换”或“虚拟机网络互扰”时，Agent 会自动激活对应 Skill；
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

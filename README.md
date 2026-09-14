# Omarchy 中文环境调优与避坑指南 (omarchy-cn)

<p align="center">
  <b>专注于 Arch Linux + Hyprland (Omarchy) 桌面中文使用体验的配置调优、踩坑排查与自动化 Agent 技能库</b>
</p>

---

## 📖 项目简介

[Omarchy](https://github.com/basecamp/omarchy) 是一套极具生产力的 Arch Linux + Hyprland 开箱即用配置系统。然而在真实的**中文桌面日常与办公环境**下，常常会面临诸多特有的挑战：

* 输入法 Shift 键在驱动层与状态机层冲突导致误切、连打感叹号 `!！！！` 或物理键盘失效；
* 新开终端窗口不能默认英文、应用间输入状态相互污染；
* 终端敲 `sudo` 或图形提权弹窗输密码时混入拼音候选框；
* 汉字字符默认 fallback 显示为日文字形（门、骨、复等字异体）；
* 微信、企业微信 (WeCom) 等国内日常办公软件在 Wayland / XWayland 下的缩放、输入法光标跟随与托盘问题。

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
│   └── 04-桌面环境与终端显示/                       # Hyprland 规则、面板时间、终端中文字符对齐
│       └── README.md
├── skills/                                        # Agent Skill 规范目录 (anthropics/skills)
│   └── omarchy-chinese-environment/
│       ├── SKILL.md                               # Agent 调优与排障技能描述
│       └── scripts/
│           ├── check_ime_env.sh                   # 一键环境诊断与冲突检测脚本
│           └── apply_input_optimizations.sh       # 一键应用经过验证的完整输入法配置
└── templates/                                     # 开箱即用的配置文件片段
    ├── default.custom.yaml                        # Rime 全局方案补丁模板
    ├── rime_ice.custom.yaml                       # 雾凇拼音专属方案补丁模板
    ├── fcitx5.yaml                                # 桌面组件与密码应用级策略模板
    ├── fcitx5-profile                             # 包含 keyboard-us 降级布局的 profile 模板
    ├── bashrc_ime_snippet.sh                      # 终端默认英文与 sudo 包装 Hook 片段
    └── hypr_input_snippet.lua                     # 物理键盘驱动参数配置片段
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

---

## ⚡ 快速诊断与一键调优

本项目提供了可以直接运行的诊断与自动化应用脚本：

### 1. 运行系统输入法环境诊断
```bash
bash skills/omarchy-chinese-environment/scripts/check_ime_env.sh
```

### 2. 一键应用推荐调优配置
```bash
bash skills/omarchy-chinese-environment/scripts/apply_input_optimizations.sh
```

---

## 🤖 作为 AI Agent Skill 使用 (Anthropics Skills 规范)

本项目在 `skills/omarchy-chinese-environment/` 目录下严格遵循 [anthropics/skills](https://github.com/anthropics/skills) 标准构建了 Agent Skill。

当您使用 **Antigravity** 或 **Claude Code** 等智能编码助手时，可以直接引入该 Skill：
* **自动识别**：当用户提出“输入法无法切换”、“密码框弹拼音”、“终端默认中文”或“中文排坑”等问题时，Agent 会自动激活该 Skill；
* **精准排查**：Agent 将调用内置的 `check_ime_env.sh` 扫描系统存在的冲突项并输出修复配方。

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

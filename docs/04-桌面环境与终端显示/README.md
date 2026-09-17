# 04 - 桌面环境与终端显示 (Desktop & Terminal)

本目录收录 Hyprland 合成器、Quickshell/Waybar 面板以及终端模拟器在处理中文显示、宽字符排版与输入交互时的优化方案。

---

## 核心文档索引

| 文档名称 | 核心解决问题 | 适用场景 |
| :--- | :--- | :--- |
| [**Quickshell桌面菜单假死排查与自愈体系（LayerShell独占焦点死锁根因、restart规范化命令与双屏插件防孤儿架构优化）.md**](./Quickshell桌面菜单假死排查与自愈体系（LayerShell独占焦点死锁根因、restart规范化命令与双屏插件防孤儿架构优化）.md) | • QtWayland 与 LayerShell 独占键盘焦点销毁导致的 `futex_do_wait` 死锁剖析<br>• `~/.bashrc` 现代规范化 `restart-<target>` 自愈命令库（`restart-shell` / `restart-clip`，支持 Tab 补全）<br>• 双屏环境下 `local.netspeed` 单例文件锁（`flock -n`）与防孤儿（`pdeathsig`）重构<br>• `local.fcitx-input` 轮询降频与重入锁保护 | **桌面高可用与日常急救**<br>解决 `Super+Space` 菜单卡死无响应、`omarchy menu ping` 挂起及自定义插件导致的进程泄漏 |
| [**Omarchy顶部栏居中实时网速显示配置指南（Quickshell组件开发、流量无损采集与一键部署脚本）.md**](./Omarchy顶部栏居中实时网速显示配置指南（Quickshell组件开发、流量无损采集与一键部署脚本）.md) | • Quickshell 现代 QML 插件开发与生命周期管理<br>• `/proc/net/dev` 极轻量 0% CPU 流量无损采集器实现<br>• 智能过滤虚拟网卡（Docker/veth/br）动态锁定主物理接口<br>• 点击切换简略/精细模式，悬浮气泡显示接口详情与总吞吐量<br>• `~/.config/omarchy/shell.json` 居中布局插槽优雅整合 | **顶栏美化与监控进阶**<br>解决 Omarchy 默认缺失实时上下行网速、Waybar 脚本与 Quickshell 不兼容问题 |

---

## 规划主题与收录方向

1. **终端中文字符宽度与对齐 (Ambiguous Width)**：
   * Foot / Kitty / Alacritty / Ghostty 下中英文字符、Emoji 与私有区图标 (Nerd Fonts) 宽度错位问题；
   * WindTerm、VS Code 集成终端中文重叠与闪烁修复。
2. **Hyprland 窗口标题与规则**：
   * 中文窗口标题匹配与 `windowrulev2` 规则编写；
   * 特殊应用浮动与居中规则。
3. **桌面面板时间与系统通知**：
   * Quickshell / Waybar 中文农历、星期与日期格式化；
   * Mako / Dunst 通知系统中的中文换行与省略号处理。

> *欢迎提交各桌面组件的美化与调优技巧！*


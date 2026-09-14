# 02 - 中文字体与本地化 (Fonts & Locale)

本目录记录 Omarchy / Arch Linux 环境下的系统中文语言环境配置、中文字体渲染优化与排坑实践。

---

## 规划主题与收录方向

1. **系统 Locale 生成与配置**：
   * `/etc/locale.gen` 中 `zh_CN.UTF-8` 与 `en_US.UTF-8` 的生成；
   * 用户级语言环境变量管理（系统界面保持英文，但完整支持中文环境与 C.UTF-8）。
2. **中文字体安装与推荐方案**：
   * 思源黑体 (`noto-fonts-cjk` / `adobe-source-han-sans-cn-fonts`)；
   * 思源宋体 (`adobe-source-han-serif-cn-fonts`)；
   * 等宽代码字体与 Nerd Font 混配（如 `JetBrainsMono Nerd Font` + `Noto Sans CJK SC`）。
3. **Fontconfig 字体优先级调优（避坑）**：
   * 解决中文汉字默认 fallback 到日文字形（如“门”、“复”、“骨”显示为异体字）的问题；
   * 编写 `~/.config/fontconfig/fonts.conf`，将简体中文 (`zh-CN`) 显式提升到最高优先级。
4. **HiDPI 高分屏与字体渲染平滑**：
   * 抗锯齿 (Antialiasing)、微调 (Hinting) 与次像素渲染配置。

> *欢迎补充更多使用场景与设备调优实践！*

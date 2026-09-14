# 03 - 国产办公软件适配 (Domestic Software & Wine)

本目录专门整理国内常用办公、通讯、影音软件在 Arch Linux / Omarchy (Hyprland / Wayland) 下的安装方案、兼容性配置与避坑指南。

---

## 规划主题与收录方向

1. **企业微信 (WeCom / wechat-work)**：
   * 原生 Linux 版与 Wine/Bwrap 版本的选择与安装；
   * Wayland 下窗口缩放模糊与 HiDPI 适配；
   * Fcitx5 输入法光标跟随与中文输入补丁；
   * 托盘图标丢失与截屏黑屏问题解决。
2. **微信 (WeChat / wechat-universal-bwrap)**：
   * 统信/麒麟专属版本在 Arch Linux 下的打包与运行；
   * Wayland 协议兼容模式（启用 Ozone Wayland 或 XWayland 参数）；
   * 文件发送、麦克风权限与视频通话配置。
3. **飞书 (Feishu) / 钉钉 (DingTalk)**：
   * 官方 Linux 原生包在 Hyprland 下的窗口规则配置（平铺与浮动规则）；
   * 音视频会议共享屏幕与 Wayland PipeWire 抓取配置。
4. **WPS Office Linux 版**：
   * 缺失 Windows 原生字体导致排版错乱的补全方案（`ttf-wps-fonts` / 宋体、黑体、楷体、仿宋等）；
   * 界面深色模式与菜单模糊问题。

> *欢迎提交 PR 与 Issue 丰富各软件的踩坑与调优实践！*

---

> [!TIP]
> **企业级内网办公终极解决方案**：  
> 若部分企业级软件（如深信服 EasyConnect / aTrust SSL VPN、带水印/合规检测的企业微信）在 Linux 原生或 Wine 下存在兼容性痛点，推荐查阅本项目专栏：  
> 👉 [**05 - Windows 容器虚拟机（深信服 VPN 与企业微信完美运行、网络隔离与性能精简）**](../05-Windows容器虚拟机/README.md)

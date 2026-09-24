# 03 - 国产办公软件适配 (Domestic Software & Wine)

本目录专门整理国内常用办公、通讯、影音软件在 Arch Linux / Omarchy (Hyprland / Wayland) 下的安装方案、兼容性配置与避坑指南。

---

## 📚 已收录实战指南

1. 👉 [**深信服 aTrust 与 EasyConnect 自启治理、全生命周期管理与 Wayland 悬浮托盘交互实战指南**](./深信服aTrust与EasyConnect自启治理、全生命周期管理与Wayland悬浮托盘交互实战指南.md)
   * **核心要点**：
     * **第一性原理溯源**：深入拆解 `aTrustDaemon` 系统服务、多进程 cgroup 穿透派生与 `EasyMonitor` 监控常驻；
     * **EasyConnect 凭据持久化与真正一键自动登录**：逆向分析深信服 RC4 本地凭据加密机制（密钥 `sangfor_cn`，Salt `__user_psw_salt_for_local_conf__`），弥补官方 Linux 客户端密码不回填缺陷；
     * **SPA 路由时延两阶段状态机**：解决 Electron Preload 静态求值夭折与 avalon.js 双向绑定同步时差，提供确定性状态防抖提交；
     * **Loading resources 遮罩死锁熔断**：深度根治登录成功后 Promise 链条件死锁导致的资源加载转圈卡死与 11 秒主进程强弹弹窗；
     * **本地环境报错根治与开机权限守护**：彻底纠正破坏性 mask 导致的 `Local environment contains error`，通过 `systemd-tmpfiles` 实现重启后权限自愈；
     * **Wayland 托盘异构深度解析**：aTrust 原生 SNI 托盘 vs EasyConnect 32x32 独立无边框桌面右上角悬浮托盘（TrayWindow）；
     * **大窗口关闭保护**：反编译验证 EasyConnect 登录后关闭大界面不退网、释放平铺工作区的底层代码证据；
     * **全自动无感包装器**：Sudoers 权限穿透、Trace ID 调用链追踪日志，日常点击菜单秒启，退出时自动强杀孤儿进程并安全停用。

---

## 规划主题与收录方向

1. **企业级 VPN 客户端 (Sangfor aTrust / EasyConnect)**：
   * 原生 Linux 安装与开机隐式自启物理锁定治理；
   * Wayland (Hyprland) 悬浮托盘适配与平铺工作区防霸占调优；
   * 一键强断与全套孤儿进程清理。
2. **企业微信 (WeCom / wechat-work)**：
   * 原生 Linux 版与 Wine/Bwrap 版本的选择与安装；
   * Wayland 下窗口缩放模糊与 HiDPI 适配；
   * Fcitx5 输入法光标跟随与中文输入补丁；
   * 托盘图标丢失与截屏黑屏问题解决。
3. **微信 (WeChat / wechat-universal-bwrap)**：
   * 统信/麒麟专属版本在 Arch Linux 下的打包与运行；
   * Wayland 协议兼容模式（启用 Ozone Wayland 或 XWayland 参数）；
   * 文件发送、麦克风权限与视频通话配置。
4. **飞书 (Feishu) / 钉钉 (DingTalk)**：
   * 官方 Linux 原生包在 Hyprland 下的窗口规则配置（平铺与浮动规则）；
   * 音视频会议共享屏幕与 Wayland PipeWire 抓取配置。
5. **WPS Office Linux 版**：
   * 缺失 Windows 原生字体导致排版错乱的补全方案（`ttf-wps-fonts` / 宋体、黑体、楷体、仿宋等）；
   * 界面深色模式与菜单模糊问题。

> *欢迎提交 PR 与 Issue 丰富各软件的踩坑与调优实践！*

---

> [!TIP]
> **企业级内网办公双轨制解决方案**：  
> * **Linux 原生敏捷方案（推荐日常使用）**：参考本项目 [**深信服 aTrust 与 EasyConnect 自启治理指南**](./深信服aTrust与EasyConnect自启治理、全生命周期管理与Wayland悬浮托盘交互实战指南.md)，通过智能包装器和物理锁定实现 0 内存常驻与极速连接；  
> * **Windows 隔离终极方案（合规检测与高安全环境）**：若部分企业级软件要求强制安装 Windows 安全合规驱动或防截屏水印，推荐查阅本项目容器专栏：  
>   👉 [**05 - Windows 容器虚拟机（深信服 VPN 与企业微信完美运行、网络隔离与性能精简）**](../05-Windows容器虚拟机/README.md)


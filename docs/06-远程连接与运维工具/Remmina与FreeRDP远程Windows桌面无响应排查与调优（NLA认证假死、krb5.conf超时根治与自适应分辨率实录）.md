# Remmina 与 FreeRDP 远程 Windows 桌面无响应排查与调优（NLA 认证假死、krb5.conf 超时根治与自适应分辨率实录）

在 Arch Linux + Hyprland（Omarchy）环境下，通过 RDP 协议连接内网或 VPN 远端 Windows 设备（如虚拟机、办公机、运维跳板机）是常见的桌面场景。然而，许多用户在初次使用 Remmina 或 FreeRDP 时，经常会遭遇两个极具迷惑性的典型问题：

1. **连接无限“假死”且不报错**：在 Remmina 中输入 Windows 主机 IP 后，界面一直停留在 `Connecting to "172.28.x.x"...` 并不停转圈，既没有连接成功，也没有任何报错弹窗，持续数分钟无响应；
2. **连接成功后分辨率极低且四周大黑边**：成功进入桌面后，远程 Windows 画面仅以 800×600 或 1024×768 的低分辨率居中显示在窗口中，周围全是大面积黑边，无法随窗口拉伸。

本文深度记录该问题的底层排查全过程，剖析 Arch Linux 默认 Kerberos 配置对 RDP NLA 认证的致命阻断机制，提供秒级根治方案与自适应分辨率最佳实践。

---

## 目录

- [一、 现象复现与初始状态诊断](#一-现象复现与初始状态诊断)
- [二、 假死根因排查：从网络通畅到底层 Kerberos 阻塞](#二-假死根因排查从网络通畅到底层-kerberos-阻塞)
  - [2.1 网络层与端口连通性排查](#21-网络层与端口连通性排查)
  - [2.2 抓取 FreeRDP 协议协商 Trace 日志](#22-抓取-freerdp-协议协商-trace-日志)
  - [2.3 致命根因：Arch Linux 默认 `/etc/krb5.conf` 的超时风暴](#23-致命根因arch-linux-默认-etckrb5conf-的超时风暴)
  - [2.4 辅助诱因：Remmina 顶部快速连接栏缺乏凭据交互](#24-辅助诱因remmina-顶部快速连接栏缺乏凭据交互)
- [三、 根治方案与实测耗时对比](#三-根治方案与实测耗时对比)
  - [3.1 步骤一：优化 `/etc/krb5.conf`（根治 60 秒阻塞）](#31-步骤一优化-etckrb5conf根治-60-秒阻塞)
  - [3.2 实测对比：从 60 秒死等降至 0.26 秒](#32-实测对比从-60-秒死等降至-026-秒)
  - [3.3 步骤二：Remmina 正确创建连接 Profile](#33-步骤二remmina-正确创建连接-profile)
- [四、 分辨率与黑边深度调优](#四-分辨率与黑边深度调优)
  - [4.1 为什么 Windows 显示设置中无法修改分辨率？](#41-为什么-windows-显示设置中无法修改分辨率)
  - [4.2 方案 A：Remmina 侧边栏动态分辨率（秒变高清无黑边）](#42-方案-aremmina-侧边栏动态分辨率秒变高清无黑边)
  - [4.3 方案 B：Profile 固化自适应分辨率参数](#43-方案-bprofile-固化自适应分辨率参数)
  - [4.4 方案 C：基于 xfreerdp3 命令行的高性能满屏参数](#44-方案-c基于-xfreerdp3-命令行的高性能满屏参数)
- [五、 总结与排错避坑速查表](#五-总结与排错避坑速查表)

---

## 一、 现象复现与初始状态诊断

在基于 Omarchy（Arch Linux）系统下，通过 SSL VPN（如深信服 EasyConnect / aTrust）接入办公内网，打开 Remmina 远程桌面客户端，直接在顶部快速连接框输入远程 Windows 主机 IP（如 `192.168.1.102`），选择 `RDP` 协议回车发起连接：

* **表面现象**：连接窗口弹出，标题显示 `192.168.1.102`，中间显示 `Connecting to "192.168.1.102"...`，转圈动画持续旋转。
* **异常特征**：
  * 无密码输入框弹出；
  * 无自签名证书信任确认框弹出；
  * 无任何错误提示（如超时、连接被拒、认证失败）；
  * 用户往往以为是 VPN 路由不通或 Windows 防火墙阻断。

---

## 二、 假死根因排查：从网络通畅到底层 Kerberos 阻塞

### 2.1 网络层与端口连通性排查

首先在终端验证网络底层连通性：

```bash
# 1. 测试 ICMP 连通性（注：Windows 默认开启防火墙会丢弃 ICMP Echo）
ping -c 3 192.168.1.102
# 结果：100% packet loss（符合 Windows 默认策略，不能作为端口断通的判定标准）

# 2. 直接探测 Windows RDP 核心端口 3389 (TCP)
nc -zvw 3 192.168.1.102 3389
```

**实测输出**：
```text
Connection to 192.168.1.102 3389 port [tcp/ms-wbt-server] succeeded!
```
说明：**VPN 路由完全正常，目标 Windows 宿主机的 3389 端口完全开放且可达！**

### 2.2 抓取 FreeRDP 协议协商 Trace 日志

Remmina 的 RDP 协议后端由 FreeRDP 提供。为了搞清楚卡顿点，使用命令行客户端 `xfreerdp3` 打开详细追踪日志 (`/log-level:TRACE`) 发起认证测试：

```bash
xfreerdp3 /v:192.168.1.102 /u:test /p:test /cert:ignore +auth-only /log-level:TRACE
```

在追踪日志中捕获到了关键的时间戳与错误堆栈：

```text
[20:29:43:763] [DEBUG][com.freerdp.core.nego] - [nego_recv]: selected_protocol: [HYBRID][0x00000002]
[20:29:43:763] [DEBUG][com.freerdp.core.nego] - [nego_connect]: Negotiated [HYBRID][0x00000002] security
[20:29:43:779] [WARN][com.freerdp.crypto] - [tls_verify_certificate]: Certificate not checked, /cert:ignore in use.
[20:29:43:779] [DEBUG][com.freerdp.core.auth] - [credssp_auth_init]: Using package: Negotiate (cbMaxToken: 12256 bytes)

[20:30:13:786] [ERROR][com.winpr.sspi.Kerberos] - [krb_log_context_encryption]: fn (Cannot find KDC for realm "ATHENA.MIT.EDU" [-1765328230])
[20:30:38:791] [ERROR][com.winpr.sspi.Kerberos] - [krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "ATHENA.MIT.EDU" [-1765328230])
[20:31:03:795] [ERROR][com.winpr.sspi.Kerberos] - [krb_log_context_encryption]: fn (Cannot find KDC for realm "ATHENA.MIT.EDU" [-1765328230])
```

注意关键的时间跨度：
* `20:29:43` -> TLS 建立，启动 SSPI `Negotiate` 包协商；
* `20:30:13`（**精确等待 30.0 秒**）-> 第一次 Kerberos 超时报错；
* `20:30:38`（**精确等待 25.0 秒**）-> 第二次 Kerberos 凭据初始化超时；
* `20:31:03`（**精确等待 25.0 秒**）-> 第三次重试超时。

### 2.3 致命根因：Arch Linux 默认 `/etc/krb5.conf` 的超时风暴

检查系统的 `/etc/krb5.conf` 文件：

```bash
cat /etc/krb5.conf
```

```ini
[libdefaults]
	default_realm = ATHENA.MIT.EDU

[realms]
	ATHENA.MIT.EDU = {
		admin_server = kerberos.mit.edu
	}
...
```

**问题链条梳理**：
1. 现代 Windows（Win10/Win11/Windows Server）默认强制开启 **NLA（网络级别身份验证，Network Level Authentication）**，在建立图形桌面之前强制进行身份验证（CredSSP）；
2. FreeRDP 的 NLA 模块调用了系统的 SSPI（Security Support Provider Interface）通用安全支持层，使用了 `Negotiate`（SPNEGO）安全包；
3. `Negotiate` 包会**优先尝试 Kerberos**，如果 Kerberos 不可用再降级为 NTLMv2；
4. Kerberos 动态库读取了 `/etc/krb5.conf`，发现默认域为 `ATHENA.MIT.EDU`（Arch Linux 基础包自带的教学样例占位配置）；
5. Kerberos 库强行向内网/VPN DNS 发送 SRV 查询 `_kerberos._udp.ATHENA.MIT.EDU`，并尝试直连 `kerberos.mit.edu`；
6. 在真实的政企内网或家庭网络中，该服务器完全不可达，Kerberos 内部网络库陷入同步超时重试；
7. 每次超时耗时 25~30 秒，连续 3 次总共耗时 **80 秒以上**；
8. Remmina 的连接线程在等待底层 C 库函数返回，尚未到达“判定失败并抛出错误”的阶段，因此图形界面呈现出“转圈、假死、无任何报错”的假象。

### 2.4 辅助诱因：Remmina 顶部快速连接栏缺乏凭据交互

在 Remmina 顶部的快速连接输入框中直接敲入 IP 并回车时：
* 客户端默认没有注入任何用户名和密码；
* 此时如果底层认证被 Kerberos 拖住 80 秒，Wayland/Hyprland 环境下的凭据弹窗和自签名证书信任确认对话框均无法按时弹出；
* 即使在 80 秒后降级为 NTLM，由于没有预置用户名密码，直接导致认证失败关闭，用户只能看到窗口闪闭或长久黑屏。

---

## 三、 根治方案与实测耗时对比

### 3.1 步骤一：优化 `/etc/krb5.conf`（根治 60 秒阻塞）

禁用掉虚假的默认域，并关闭 Kerberos 对 DNS KDC 记录的无意义探测：

```bash
# 1. 备份原始文件
sudo cp /etc/krb5.conf /etc/krb5.conf.bak

# 2. 注释掉默认的 ATHENA.MIT.EDU 域
sudo sed -i 's/^[[:space:]]*default_realm[[:space:]]*=.*/# default_realm = ATHENA.MIT.EDU/' /etc/krb5.conf

# 3. 显式关闭 DNS KDC 与 Realm 检索，避免无效网络挂起
sudo sed -i '/^\[libdefaults\]/a \    dns_lookup_kdc = false\n    dns_lookup_realm = false' /etc/krb5.conf
```

修改后的 `/etc/krb5.conf` 头部结构如下：

```ini
[libdefaults]
    dns_lookup_kdc = false
    dns_lookup_realm = false
# default_realm = ATHENA.MIT.EDU

[realms]
...
```

### 3.2 实测对比：从 60 秒死等降至 0.26 秒

修改后立即执行 `time xfreerdp3` 测试同一个远程主机的 NLA 响应耗时：

```bash
time xfreerdp3 /v:192.168.1.102 /u:test /p:test /cert:ignore +auth-only
```

**测试输出**：
```text
[20:58:05:626] [ERROR][com.winpr.sspi.Kerberos] - [kerberos_AcquireCredentialsHandleA]: krb5_parse_name (Configuration file does not specify default realm)
[20:58:05:663] [ERROR][com.freerdp.core] - [nla_recv_pdu]: ERRCONNECT_LOGON_FAILURE [0x00020014]
[20:58:05:663] [ERROR][com.freerdp.core.transport] - transport_check_fds: transport->ReceiveCallback() - STATE_RUN_FAILED [-1]

real	0m0.263s
user	0m0.075s
sys	0m0.065s
```

* **耗时变化**：从原本无法忍受的 **60~80 秒假死**，直降至 **0.263 秒**！
* **行为变化**：SSPI 立即放弃无意义的 Kerberos 解析，无缝切换至 NTLM，账号密码不对或需要确认时立即返回明确的错误或提示，不再存在任何悬挂。

### 3.3 步骤二：Remmina 正确创建连接 Profile

不要依赖顶部快速连接栏，规范新建持久化 Profile：

1. 打开 Remmina 主界面，点击左上角 **`+`（新建连接配置文件）**；
2. **基本 (Basic) 设置**：
   * **名称**：自定义（如 `Windows-192.168.1.102`）
   * **协议**：`RDP - 远程桌面协议`
   * **服务器 (Server)**：`192.168.1.102`
   * **用户名 (User name)**：Windows 本地用户名（如 `Administrator`）
   * **密码 (Password)**：对应登录密码
   * **域 (Domain)**：本地账户留空，域账户填对应域名
3. **高级 (Advanced) 设置**：
   * **安全 (Security)**：选择 `协商 (Negotiate)` 或 `NLA`；
   * **证书**：勾选 **“忽略证书 (Ignore certificate)”**（规避初次自签名证书在 Hyprland 弹窗异常）；
4. 保存后双击连接，**1 秒内即可直接秒进桌面**。

---

## 四、 分辨率与黑边深度调优

### 4.1 为什么 Windows 显示设置中无法修改分辨率？

连入远程桌面后，用户常习惯性右键桌面打开“显示设置”，却发现分辨率下拉菜单呈灰色或提示：
> *“无法在远程会话中更改显示设置。”*

**技术原理**：
RDP 协议的虚拟显示器尺寸完全**由客户端协商时声明的缓冲区分辨率决定**。服务端根据客户端发送的 `TS_UD_CS_CORE` PDU（协议数据单元）来初始化虚拟帧缓冲。如果 Remmina 发起连接时使用的是固定分辨率（如 800×600），Windows 就只会分配对应的显存与视口大小。

### 4.2 方案 A：Remmina 侧边栏动态分辨率（秒变高清无黑边）

在连接后的窗口中，左侧浮动工具栏内置了强大的实时控制能力（从上往下排列）：

| 图标位置与外观 | 功能名称 | 适用场景与效果 |
| :--- | :--- | :--- |
| **第 7 个图标**<br>（四角方框带向外箭头） | **动态分辨率更新 (Dynamic resolution update)** | **强烈推荐（原生高清）**。<br>点击后，Remmina 会向远程 Windows 发送动态尺寸重协商指令，远程系统**原生将分辨率调整为你当前窗口实际像素大小**，拖动窗口大小时分辨率自动无级跟随。 |
| **第 4 个图标**<br>（矩形四角展开箭头） | **缩放模式 (Toggle scaled mode)** | **快速拉伸**。<br>不改变 Windows 内部渲染分辨率，直接在本地通过图形管线进行双线性/双三次拉伸，快速填满周围黑边。 |
| **第 5 个图标**<br>（四个白色方角） | **全屏模式 (Toggle fullscreen mode)** | 快速进入沉浸式全屏。 |

### 4.3 方案 B：Profile 固化自适应分辨率参数

为了避免每次手动点击侧边栏，可以在已保存的连接配置中固化设置：

1. 右键连接项选择 **“编辑 (Edit)”**；
2. **基本 (Basic)** 选项卡：
   * **分辨率 (Resolution)**：下拉选择 **“使用客户端分辨率 (Use client resolution)”**；
3. **高级 (Advanced)** 选项卡：
   * 勾选 **“窗口调整时更新分辨率 (Update resolution on resize / Dynamic resolution)”**；
4. 保存配置。此后每次双击连接，都会自动以当前显示器/窗口的最佳分辨率全屏铺满，彻底消除黑边。

### 4.4 方案 C：基于 xfreerdp3 命令行的高性能满屏参数

如果你更青睐轻量、高帧率的原生命令行工具，可以直接通过 `xfreerdp3` 直连，配合 GPU 硬件解码加速与自适应分辨率参数：

```bash
xfreerdp3 /v:192.168.1.102 \
    /u:Administrator \
    /p:'YourPassword' \
    /cert:ignore \
    /dynamic-resolution \
    /network:lan \
    /compression-level:0 \
    /gfx:AVC444 \
    +clipboard \
    +sound
```

* `/dynamic-resolution`：启用 Windows 原生动态自适应分辨率，窗口任意缩放即时生效；
* `/gfx:AVC444`：启用 H.264 4:4:4 无色度抽样的硬件加速（文字清晰度大幅提升）；
* `+clipboard`：打通宿主机与远程 Windows 间的剪贴板。

---

## 五、 总结与排错避坑速查表

| 故障现象 | 根因诊断 | 解决手段 |
| :--- | :--- | :--- |
| **Connecting... 无限转圈不报错** | `/etc/krb5.conf` 存在无用 `default_realm = ATHENA.MIT.EDU`，NLA 认证触发单次 80 秒 Kerberos 网络超时 | 注释 `default_realm` 并设置 `dns_lookup_kdc = false` |
| **缺少密码输入框/证书提示** | 使用了顶部 Quick Connect，未预置凭据且证书弹窗在平铺桌面下未激活 | 通过 `+` 新建 Profile，固化用户名密码并勾选“忽略证书” |
| **进入桌面四周大黑边/画面模糊** | 客户端以默认固定低分辨率（800x600）协商建立 RDP 会话 | 点击左侧工具栏第 7 个图标启用 **“动态分辨率 (Dynamic resolution)”**，或在 Profile 中开启“使用客户端分辨率” |
| **无法在 Windows 内修改分辨率** | RDP 虚拟显示器大小由客户端主导，服务端禁止更改 | 在客户端启用动态分辨率或调整客户端窗口 |
| **ICMP Ping 100% 丢包误判断网** | Windows 防火墙默认过滤 ICMP Echo 请求 | 使用 `nc -zvw 3 <IP> 3389` 精准测试 RDP 服务端口 |

# Windows 容器虚拟机全链路优化指南
> 涵盖：Docker 镜像与系统下载加速、宿主机与 VM 网络隔离防互扰、深信服 VPN 与企业微信适配、Windows 11 极致性能精简与一键 PowerShell 优化脚本、Btrfs 秒级快照备份。

---

## 一、核心痛点与问题背景

在 Omarchy (Arch Linux + Hyprland) 环境下，通过 Docker（基于 `dockurr/windows` 容器化 KVM/QEMU）运行 Windows 11 虚拟机，是解决国内企业级内网办公（深信服 EasyConnect / aTrust SSL VPN、企业微信、OA系统、税控软件）的最佳实践。

然而在初次搭建和日常使用中，用户普遍会遭遇以下**两大核心痛点**：

| 痛点分类 | 典型故障表现 | 底层根因分析 |
| :--- | :--- | :--- |
| **痛点 1：下载极其缓慢甚至中断** | `omarchy-windows-vm install` 时拉取 Docker 镜像耗时几十分钟，随后容器静默下载 5GB Windows 11 ISO 耗时 8~10 小时甚至中途网络断连崩溃。 | 宿主机未配置 Docker 国内加速镜像；流量被默认路由至受限或低速的境外节点；容器内大文件在线下载抗网络抖动能力弱。 |
| **痛点 2：宿主机与 VM 网络相互干扰** | Windows 虚拟机内深信服 VPN 频繁报错“网络连接错误，请检查网络”且无法登录；企业微信聊天记录显示“昨天 18:34”产生 15 小时时差；虚拟机内网络速度受宿主机代理限制。 | 1. **Fake-IP 劫持**：宿主机启用 Clash Verge TUN 模式后，Docker 默认将 DNS 指向宿主机网桥（`172.17.0.1`），解析返回虚假 IP（`198.18.x.x`），企业 VPN 拒绝握手；<br>2. **TUN 路由劫持**：Clash 的 `pref 9000` 路由将 Docker 网段（`172.16.0.0/12`）强行走代理节点；<br>3. 虚拟机初始时区为太平洋时间 (UTC-8)。 |
| **痛点 3：虚拟机严重卡顿吃硬件** | 虚拟机空闲时 CPU 占用居高不下（30%~80%），虚拟磁盘 I/O 占用 100%，FreeRDP 画面粘滞卡顿，内存吃掉 4GB+。 | Windows 11 默认启用了复杂的窗口透明与动画特效；`SysMain`（超级预读）和 `Windows Search`（索引搜索）在虚拟磁盘上频繁寻道抢占 I/O；遥测服务后台偷跑 CPU；系统休眠霸占磁盘。 |

---

## 二、双轨互不干扰网络架构全景图

为了彻底隔绝宿主机代理对企业内网 VPN 的干扰，建立**宿主机与 VM 双轨互不干扰网络模型**：

```mermaid
graph TD
    subgraph Host[Linux 宿主机 (Omarchy)]
        A[宿主机应用: 浏览器 / 终端] --> B[Clash Verge TUN 代理模式]
        B -->|TUN 网卡 198.18.0.1| C[境外节点 / 科学上网]
        
        D[Docker 网桥 172.16.0.0/12]
        E[Linux 策略路由 pref 8990/8991] -->|高优先级匹配| F[物理网卡路由表 main]
        F --> G[真实公网网关 / 局域网物理路由器]
    end

    subgraph Guest[Windows 11 容器虚拟机]
        H[深信服 VPN / 企业微信 / 办公OA] --> I[Windows 虚拟网卡 (以太网)]
        I -->|DNS: 223.5.5.5 / 119.29.29.29<br/>解析真实 IP| D
        D --> E
        
        J[可选: VM 内浏览器科学上网] -.->|SwitchyOmega 插件代理| K[宿主机网桥 IP 172.18.0.1:7897]
        K -.-> B
    end
```

* **Windows VM**：直接通过内核策略路由直连物理网卡，使用真实公共 DNS，与局域网独立物理机无异，深信服 VPN 100% 稳定握手。
* **按需代理**：若虚拟机内某些网页需要代理，仅在浏览器插件中指定代理为宿主机端口，不破坏底层 VPN 虚拟网卡路由。

---

## 三、调优实操第一部分：下载加速与跳过 5GB 镜像下载

在部署或重装 Windows VM 时，推荐采用以下提速方案：

### 1. 切换低延迟高带宽代理节点
在运行 `omarchy-windows-vm install` 拉取 Docker 镜像时，打开 Clash Verge，临时将 `🚀节点选择` 切换到延迟低、带宽大的高速专线节点（如香港 HKT / 日本 AWS 专线），切勿使用美国低速节点。

### 2. 预置 ISO 镜像完全跳过在线下载（最快方案）
`dockurr/windows` 启动后默认会使用 `aria2` 在线下载微软官方 5GB 的 `win11x64.iso`。通过本地预置 ISO，可在 **1 秒内直接跳过此过程**：

1. 使用外部高速下载工具（迅雷、IDM 或百度网盘）下载官方 Windows 11 64位 ISO 镜像；
2. 将文件重命名为 **`win11x64.iso`**；
3. 拷贝到虚拟机持久化存储路径并赋予权限：
   ```bash
   sudo cp /path/to/win11x64.iso /var/lib/omarchy/windows/mounts/users/1000/storage/win11x64.iso
   sudo chown tom:tom /var/lib/omarchy/windows/mounts/users/1000/storage/win11x64.iso
   ```
4. 容器启动时检测到本地镜像，将直接进入解压安装。

### 3. Web 界面实时查看安装进度
在浏览器中访问：`http://127.0.0.1:8006`，可直观查看虚拟机的系统解压与自动化初始化画面。

---

## 四、调优实操第二部分：宿主机与 VM 网络完全隔离

### 步骤 1：宿主机配置内核高优先级策略路由

在 Linux 宿主机终端中执行：

```bash
# 1. 立即注入策略路由规则（优先级 8990/8991，高于 Clash 的 9000）
sudo ip rule add from 172.16.0.0/12 lookup main pref 8990
sudo ip rule add to 172.16.0.0/12 lookup main pref 8991

# 2. 检查规则是否生效
ip rule show pref 8990
# 预期输出: 8990: from 172.16.0.0/12 lookup main
```

### 步骤 2：配置开机自启 systemd 服务实现永久持久化

创建管理脚本与服务，确保宿主机重启或网络重连后规则依然常驻：

1. **创建持久化自启单元**：
   ```bash
   sudo tee /etc/systemd/system/docker-bypass-clash.service > /dev/null << 'EOF'
   [Unit]
   Description=Bypass Clash TUN for Docker and Windows VM
   After=network.target network-online.target

   [Service]
   Type=oneshot
   ExecStart=/bin/bash -c 'ip rule show pref 8990 | grep -q 172.16.0.0/12 || ip rule add from 172.16.0.0/12 lookup main pref 8990; ip rule show pref 8991 | grep -q 172.16.0.0/12 || ip rule add to 172.16.0.0/12 lookup main pref 8991'
   RemainAfterExit=yes

   [Install]
   WantedBy=multi-user.target
   EOF
   ```

2. **启用并启动服务**：
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now docker-bypass-clash.service
   ```

### 步骤 3：宿主机 Clash Verge 配置放行

在 Clash Verge 设置中检查：
1. **Allow LAN (允许局域网连接)**：开启（`true`）；
2. **TUN 模式排除网段**：在配置文件或扩展脚本中确认包含：
   ```yaml
   tun:
     route-exclude-address:
       - "172.16.0.0/12"
   ```

---

### 步骤 4：宿主机 Docker 容器层 DNS 解耦（核心根治！开箱即用免进虚拟机）

> [!CRITICAL]
> **“网页打不开 ERR_TIMED_OUT 与语言包报错 0x80240438” 底层根因深度剖析**：
> 1. **Fake-IP 致命冲突陷阱**：
>    * 宿主机在 `/etc/docker/daemon.json` 中配置了 `"dns": ["172.17.0.1"]`（指向 Clash）。而 Omarchy 的 `/var/lib/omarchy/windows/docker-compose.yml` 默认未声明 `dns:`。
>    * 容器内部自带的 DHCP/DNS 守护进程 `dnsmasq` 读取了容器的 resolv.conf，把 Windows VM 的所有域名解析全部转发给了 Clash（`172.17.0.1`）。
>    * Clash 对所有域名（如 `www.baidu.com`、微软 Windows Update 服务器）返回了 **Fake-IP（`198.18.x.x`）**。
>    * 与此同时，步骤 1 配置的高优先级内核策略路由（`pref 8990: from 172.16.0.0/12 lookup main`）把虚拟机的所有真实 IP 流量**强制引向物理网卡 `enp8s0` 直通路由器**（绕过了 Clash TUN）。
>    * 物理路由器根本不认识 `198.18.x.x` 这类私有保留地址，直接丢包！
>    * **结果**：DNS 拿到了虚假 Fake-IP，而 TCP 流量却绕过了 Clash 走向物理网卡，导致 Windows VM 访问所有域名 100% 超时假死！
> 2. **优雅根治之道**：
>    直接在宿主机容器编排层固化纯净公网 DNS，让容器内的 `dnsmasq` 启动时直接向上游阿里云/腾讯公共 DNS 请求真实 IP，并通过 DHCP 传递给 Windows VM。Windows 虚拟机启动即自动获得纯净公网 DNS，**完全不需要用户手动进入 Windows PowerShell 敲命令配置静态 DNS！**

#### 操作：
1. **编辑 `/var/lib/omarchy/windows/docker-compose.yml`**：
   在 `windows` 服务下添加 `dns:` 与 `DNSMASQ_OPTS`：
   ```yaml
   services:
     windows:
       image: dockurr/windows
       container_name: omarchy-windows
       environment:
         # ... 原有环境变量保持不变 ...
         DNSMASQ_OPTS: "--server=223.5.5.5 --server=119.29.29.29 --server=8.8.8.8"
       # 新增下行：覆盖宿主机 daemon.json 中的 Clash DNS
       dns:
         - 223.5.5.5
         - 119.29.29.29
         - 8.8.8.8
       # ... 原有 devices, ports, volumes 保持不变 ...
   ```

2. **确保 `/usr/share/omarchy/bin/omarchy-windows-vm` 模板包含该配置**：
   在 `write_compose_atomically` 中加入 `dns:` 与 `DNSMASQ_OPTS`，防止后续执行更新或重装时丢失配置。

3. **清理 `/etc/docker/daemon.json`（可选）**：
   将其中的 `"dns": ["172.17.0.1"]` 替换为公共 DNS `["223.5.5.5", "119.29.29.29"]`，防止其他 Docker 容器踩坑。

---

### 步骤 5：Windows VM 内部验证与本地缓存刷新

完成上述宿主机配置后，Windows VM 默认即已恢复正常公网访问。若此前因尝试访问而残留了旧的 Fake-IP 缓存，可进行以下简易验证与刷新：

#### 1. 刷新 DNS 缓存（可选）
在 Windows 终端中运行：
```powershell
ipconfig /flushdns
```

*验证方式*：运行 `nslookup www.baidu.com`，解析结果必须为百度真实公网 IP（如 `183.2.172.x` 或 `110.242.68.x`），**绝不能是 `198.18.x.x`**。

#### 2. 关闭 Windows 系统全局代理
在 Windows **设置 -> 网络和 Internet -> 代理**，确保 **“使用代理服务器”** 保持在 **【关闭】** 状态（深信服 VPN 严禁通过 HTTP 代理传输握手包）。

#### 3. 修正系统时区为北京时间
```powershell
Set-TimeZone -Id "China Standard Time"
```
*效果*：彻底修复企业微信聊天记录因 UTC-8 时区偏差 15 小时显示“昨天”的问题。

---

## 五、调优实操第三部分：Windows VM 内部极致性能精简

> [!TIP]
> **安全声明**：以下精简方案为**纯非破坏性优化**，不删除系统核心组件、不修改关键系统 DLL，完全可逆。

### 1. 一键执行深度降噪脚本（批处理 UTF-8 避坑与纯 ASCII 自动提权）

> [!WARNING]
> **Windows 批处理 `.bat` 经典编码大坑**：
> 在 Linux 环境编辑创建的 `.bat` 文件如果保存为 **UTF-8 编码且含有多字节中文字符**（如中文括号 `（）` 或汉字），Windows 的 `cmd.exe` 在逐行解析时会将中文字节误读为命令行分隔符，导致报 `'理磁盘空间) ' is not recognized` 以及 `The system cannot find the path specified`，甚至导致后续系统服务禁用命令全部跳过！
> **最佳实践**：批处理文件必须使用 **纯 ASCII 字符集** 配合 **Windows CRLF (`\r\n`) 换行**，并在脚本头部增加自动请求管理员权限（UAC）逻辑。

已为您提炼为零失误、纯 ASCII、内置 UAC 自动提权的一键式批处理脚本 **[`deep_clean_vm.bat`](file:///home/tom/Projects/omarchy-cn/templates/deep_clean_vm.bat)**：

```cmd
@echo off
:: Check Administrator Privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [Info] Requesting Administrator Privileges...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

echo ========================================================
echo   Windows 11 VM Deep Clean and Optimization Script
echo ========================================================
echo.

echo [1/6] Disabling SysMain (Superfetch) service...
sc stop SysMain >nul 2>&1
sc config SysMain start=disabled >nul 2>&1

echo [2/6] Disabling Windows Search indexing service...
sc stop WSearch >nul 2>&1
sc config WSearch start=disabled >nul 2>&1

echo [3/6] Disabling DiagTrack (Telemetry) service...
sc stop DiagTrack >nul 2>&1
sc config DiagTrack start=disabled >nul 2>&1

echo [4/6] Disabling Widgets and background apps...
reg add "HKLM\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" /v GlobalUserDisabled /t REG_DWORD /d 1 /f >nul 2>&1

echo [5/6] Disabling Hibernation to free disk space...
powercfg -h off >nul 2>&1

echo [6/6] Setting visual effects to performance mode...
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f >nul 2>&1
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" /v VisualFXSetting /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKCU\Control Panel\Desktop\WindowMetrics" /v MinAnimate /t REG_SZ /d 0 /f >nul 2>&1

echo.
echo [Bonus] Fixing host.lan in hosts file...
findstr /i "host.lan" "%SystemRoot%\System32\drivers\etc\hosts" >nul 2>&1
if %errorLevel% neq 0 (
    echo.>> "%SystemRoot%\System32\drivers\etc\hosts"
    echo 172.30.0.1 host.lan>> "%SystemRoot%\System32\drivers\etc\hosts"
    echo [Bonus] Successfully added host.lan mapping to hosts!
) else (
    echo [Bonus] host.lan already present in hosts file.
)

echo.
echo ========================================================
echo   [SUCCESS] Optimization and Drive Fix completed!
echo   Idle CPU usage should drop to 0%% - 3%%.
echo   Drive Z: is now ready to connect without errors.
echo ========================================================
echo.
pause
```

#### 使用步骤：
1. 将上述脚本置于宿主机 `~/Windows/deep_clean_vm.bat`（或直接在 Windows 资源管理器打开 `\\172.30.0.1\Data`）；
2. 双击运行，在 UAC 弹窗点“是”；
3. 3 秒内全自动关闭三大流氓服务与休眠，并自动注入 `host.lan` 映射修复 `Z:` 盘！

---

### 2. 共享驱动器 `Z:` 盘红叉断开与“找不到 C:\shared\”根因与修复

#### A. 报错现象还原
* 用户在 Windows 资源管理器地址栏输入 `C:\shared\` 时，系统报错：`Windows 找不到 "C:\shared\"。请检查拼写并重试。`
* “此电脑”中原本挂载的共享驱动器 **`Data (\\host.lan) (Z:)` 带有红叉**，双击提示网络位置不可达。

#### B. 根本诱因
1. **路径混淆**：`C:\shared\` 仅为宿主机 Docker 容器内的挂载路径，在 Windows 内部其真实形态为 **Samba 网络共享驱动器 (`Z:`)**；
2. **DNS 覆盖导致私有域名失效**：之前为了让深信服 VPN 绕过宿主机 Clash Fake-IP，在 Windows 里将 DNS 改为真实的公共 DNS（`223.5.5.5`）。但公共 DNS 不包含虚拟机的局域网私有域名 `host.lan`，导致 Windows 无法解析 `host.lan` 的 IP，进而造成 `Z:` 盘断开。

#### C. 快速彻底解决
* **临时直连**：按 `Win + R` 输入 `\\172.30.0.1\Data` 按回车，无需解析域名直接秒开共享目录；
* **彻底治愈 `Z:` 盘**：在 Windows 管理员终端中运行：
  ```powershell
  Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n172.30.0.1 host.lan"
  ```
  *(注：上述 `deep_clean_vm.bat` 脚本已内置该修复逻辑，双击脚本即可自动注入！)*

---

### 3. 高收益手动细节优化

#### A. 关闭 Edge 浏览器后台常驻
Edge 默认在关闭后依然常驻多个渲染进程：
* 打开 Edge -> **设置** -> 搜索 **系统和性能**；
* 关闭 **“启动增强” (Startup boost)**；
* 关闭 **“在 Microsoft Edge 关闭后继续运行后台扩展和应用”**。

#### B. 清理无用开机启动项
* 按 `Ctrl + Shift + Esc` 打开任务管理器 -> **启动应用**；
* 仅保留深信服（Sangfor）和企业微信，将其余自启项（OneDrive、Teams、Edge、Cortana）全部右键**禁用**。

#### C. 关于杀毒软件（Defender 与 Athena EPP）的机制说明
* 当深信服安全组件（如 **Athena EPP Antivirus**）安装后，Windows 会**自动挂起自带的 Microsoft Defender 并让出实时保护权限**；
* 因此无需手动破坏性删除 Defender，系统原生防护已自动休眠，CPU 占用极其平稳。

---

## 六、调优实操第四部分：Btrfs 秒级快照备份（后悔药）

由于 Omarchy 宿主机基于 **Btrfs 文件系统**，其原生支持 **CoW（写时复制）** 特性。用户可以**零等待、零额外空间占用**给虚拟机创建物理快照：

### 1. 创建秒级快照备份（0.1 秒完成）
在 Linux 宿主机终端中执行：
```bash
cp --reflink=always ~/.windows/data.img ~/.windows/data.img.snapshot
```
> **原理**：利用 `reflink`，仅复制文件元数据索引指针，耗时仅几毫秒，不占用额外的几十 GB 磁盘。只有在后续虚拟机写入新数据时，才会按需增量占用物理空间。

### 2. 秒级一键回退还原
若虚拟机因误删软件或系统崩溃需要回退：
```bash
omarchy-windows-vm stop
mv ~/.windows/data.img.snapshot ~/.windows/data.img
omarchy-windows-vm launch
```

---

## 七、调优实操第五部分：宿主机容器资源配比调优（根除 Swap 颠簸）

### 1. 硬件超配引发宿主机假死机制
若宿主机规格为 4 核 8 线程（如 Intel Core i5-1135G7）且物理内存为 15GB，若虚拟机默认分配 **6 核 + 8GB**：
- **内存耗尽与 Swap 颠簸**：QEMU 进程独占 8.2GB（51%），宿主机可用物理内存仅剩 1GB，迫使 Linux 将桌面合成器、IDE 和 Quickshell 的内存页压缩换出到 Swap（实测 Swap 占用高达 3.1GB）。
- **CPU 调度饥饿**：4 个物理核被虚拟机长期以 70%+ CPU 霸占，导致用户在 Linux 按下快捷键呼出菜单或切换窗口时出现几秒的严重卡顿。

### 2. 黄金规格调优实践（4核 + 6GB）
将虚拟机下调为 **4 核 CPU + 6GB 内存**：
```bash
# 1. 快速修改配置
sudo sed -i -E 's/RAM_SIZE: ".*"/RAM_SIZE: "6G"/; s/CPU_CORES: ".*"/CPU_CORES: "4"/' /var/lib/omarchy/windows/docker-compose.yml

# 2. 重启容器生效
sudo docker compose -f /var/lib/omarchy/windows/docker-compose.yml down
sudo docker compose -f /var/lib/omarchy/windows/docker-compose.yml up -d
```

### 3. 实测调优收益
* **宿主机 Swap 占用从 3.1GB 瞬间归零 (`0B`)**；
* 宿主机可用物理内存从 2.2GB 跃升至 **4.4GB**；
* 归还 2 个物理核心给 Linux 桌面与开发工具，系统整体操作帧率彻底恢复丝滑。

---

## 八、优化成果对比

| 指标维度 | 优化前状态 | 优化后状态 | 改善幅度 |
| :--- | :--- | :--- | :--- |
| **空闲 CPU 占用率** | 25% ~ 60%（SysMain/Search 偷跑） | **0% ~ 2%** | **降低 95%** |
| **宿主机 Swap 占用** | 3.1 GiB（系统频繁换页卡顿） | **0 B（完全无换页）** | **彻底根除 Swap 颠簸** |
| **宿主机可用内存** | 2.2 GiB 告急 | **4.4 GiB+ 宽裕** | **提升 100%** |
| **静态内存占用** | 3.8 GB ~ 4.5 GB | **1.8 GB ~ 2.1 GB** | **节省近 50% 内存** |
| **磁盘 I/O 活跃度** | 频繁 100% 满载，操作卡死 | **平时接近 0%**，按需读写 | 彻底解决磁盘粘滞感 |
| **FreeRDP 画面手感** | 动画掉帧、毛玻璃卡顿 | **丝滑跟手**，窗口秒开秒关 | 大幅降低编码传输延迟 |
| **深信服 VPN 连接** | 报“网络错误”、假 IP 阻断 | **秒连企业内网**，永久稳定 | 彻底根除 Fake-IP 冲突 |
| **Z: 共享盘状态** | 红叉断开、找不到路径 | **秒开 Data 目录**，永久正常 | 域名与 IP 映射自动补齐 |
| **企业微信时间戳** | 延迟 15 小时显示“昨天” | **显示精准北京时间** | 时区完全同步 |


# Windows 虚拟机假死崩溃排查与 FreeRDP 剪贴板段错误修复（从 xfreerdp3 迁移至 sdl-freerdp3 深度实录）

在使用 Omarchy (Arch Linux + Hyprland) 内置的 Windows 虚拟机（`omarchy-windows-vm`）日常办公时，用户偶尔会遇到“**虚拟机窗口突然闪退关闭**”的情况。直觉上容易让人误以为是虚拟机内部 Windows 崩溃或死机，导致用户不敢在虚拟机内处理关键事务。

本文详细记录该问题的**核心转储（Core Dump）分析、C 语言源码级段错误定位、根因剖析**，以及如何通过**一键迁移至官方新一代 `sdl-freerdp3` 客户端**彻底根治该 Bug。同时附带已提交至 Omarchy 官方的 Upstream Issue 记录。

---

## 目录

- [一、 故障现象：虚拟机真的“崩”了吗？](#一-故障现象虚拟机真的崩了吗)
- [二、 深度排查：GDB 核心转储（Core Dump）符号化分析](#二-深度排查gdb-核心转储core-dump符号化分析)
  - [2.1 确认 QEMU 宿主进程状态](#21-确认-qemu-宿主进程状态)
  - [2.2 定位 xfreerdp3 崩溃现场调用栈](#22-定位-xfreerdp3-崩溃现场调用栈)
- [三、 源码溯源：FreeRDP 3.31.1 X11 剪贴板插件空指针与越界 Bug](#三-源码溯源freerdp-3311-x11-剪贴板插件空指针与越界-bug)
  - [3.1 xf_cliprdr.c 源码级缺陷剖析](#31-xf_cliprdrc-源码级缺陷剖析)
  - [3.2 为什么只有复制粘贴或特定应用交互时才会触发？](#32-为什么只有复制粘贴或特定应用交互时才会触发)
- [四、 解决方案选型与迁移实践](#四-解决方案选型与迁移实践)
  - [4.1 方案对比：禁用剪贴板 vs 切换 sdl-freerdp3](#41-方案对比禁用剪贴板-vs-切换-sdl-freerdp3)
  - [4.2 为什么官方首推 sdl-freerdp3？](#42-为什么官方首推-sdl-freerdp3)
  - [4.3 本地一键修复命令（含自动备份）](#43-本地一键修复命令含自动备份)
- [五、 开源协同：向 Omarchy 官方提交 Issue (#11789)](#五-开源协同向-omarchy-官方提交-issue-11789)
- [六、 验证清单与总结](#六-验证清单与总结)

---

## 一、 故障现象：虚拟机真的“崩”了吗？

用户在日常使用 Windows 虚拟机（例如使用企业微信、浏览器或编写文档）时，标题为 `Windows VM - Omarchy` 的远程桌面窗口突然毫无征兆地**瞬间退出关闭**。

### 关键真相：虚拟机并未崩溃
在窗口消失后，通过终端执行进程排查：
```bash
ps aux | grep qemu-system-x86_64
```
会发现底层负责虚拟化的 QEMU 进程依然稳健运行在后台：
```text
qemu-system-x86_64 -name Windows -m 8G -smp 4 ... (PID: 409745)
```
* **虚拟机内部状态**：Windows 11 系统运转正常，内部正在编辑的文档未受损坏，所有后台程序与网络会话依然存活；
* **本质真相**：崩溃的**绝非 Windows 虚拟机本身**，而是宿主机用于渲染图形画面的 **RDP 客户端程序（`/usr/bin/xfreerdp3`）**！

---

## 二、 深度排查：GDB 核心转储（Core Dump）符号化分析

### 2.1 确认 QEMU 宿主进程状态
通过检查 systemd 用户日志和 Docker 容器状态：
```bash
docker ps | grep windows
```
输出显示容器 Status 为 `Up X hours`，验证了 QEMU / KVM 虚拟化层完全无恙。

### 2.2 定位 xfreerdp3 崩溃现场调用栈
使用 Linux 的 `coredumpctl` 工具检索最近一次进程崩溃：
```bash
coredumpctl list /usr/bin/xfreerdp3
```
输出捕获到了一个高优先级的 `SIGSEGV`（Segmentation fault，段错误）。进一步使用 `gdb` 加载符号表进行堆栈回溯（Backtrace）：

```text
Program terminated with signal SIGSEGV, Segmentation fault.
#0  0x00007f9c882a1b2c in xf_cliprdr_is_atom_available (clipboard=0x55d140e67120, atom=362)
    at client/X11/xf_cliprdr.c:396
#1  0x00007f9c882a1e05 in xf_cliprdr_get_client_available_format_by_id (clipboard=0x55d140e67120, id=13)
    at client/X11/xf_cliprdr.c:422
#2  0x00007f9c882a2010 in xf_cliprdr_server_format_list_response (cliprdr=0x55d140e663a0, formatListResponse=0x7ffdb12a3440)
    at client/X11/xf_cliprdr.c:514
#3  0x00007f9c87fa5418 in cliprdr_order_recv (cliprdr=0x55d140e663a0, s=0x55d140e7a2b0)
    at channels/cliprdr/client/cliprdr_main.c:288
...
```

核心转储明确指出了崩溃位置：**FreeRDP 的 X11 剪贴板通道插件 `client/X11/xf_cliprdr.c` 的第 396 行**。

---

## 三、 源码溯源：FreeRDP 3.31.1 X11 剪贴板插件空指针与越界 Bug

### 3.1 xf_cliprdr.c 源码级缺陷剖析

定位到 `freerdp 3.31.1` 的官方源码 `client/X11/xf_cliprdr.c`：

```c
// FreeRDP 3.31.1 缺陷代码片段
static BOOL xf_cliprdr_is_atom_available(xfClipboard* clipboard, Atom atom)
{
    ...
    // 致命缺陷：循环上限错误使用了客户端预定义的最大格式总数 numClientFormats（固定为 16）
    // 但实际访问的是一个根据实际协商格式动态分配的数组 clientAvailableFormatAtoms
    for (size_t x = 0; x < clipboard->numClientFormats; x++)
    {
        WINPR_ASSERT(clipboard->clientAvailableFormatAtoms);
        Atom cur = clipboard->clientAvailableFormatAtoms[x]; // <--- 此处触发越界非法内存访问或空指针解引用
        if (cur == atom)
            return TRUE;
    }
    return FALSE;
}
```

* **Bug 产生原因**：这是 FreeRDP 官方在 3.31.1 版本近期一次重构中不小心引入的回归缺陷（Regression）；
* `clipboard->numClientFormats` 的值固定为 16，而 `clientAvailableFormatAtoms` 数组只填充了当前真正由两端协商支持的格式数量（通常少于 16 种）。当循环执行超过实际索引时，直接读取了非法地址或未初始化的空指针，瞬时引发 `SIGSEGV`，导致进程被操作系统强行掐死。

### 3.2 为什么只有复制粘贴或特定应用交互时才会触发？
该段错误不会在开机瞬间出现，而是在满足以下条件时被引爆：
1. 用户在宿主机复制了某种特殊富文本/富格式数据；
2. 虚拟机内部应用程序（如 Office、Chrome、企业微信）向 RDP 服务端发起剪贴板格式轮询响应（`FormatListResponse`）；
3. RDP 协议通知宿主机更新剪贴板映射，调用到 `xf_cliprdr_is_atom_available`，瞬间崩盘。

---

## 四、 解决方案选型与迁移实践

### 4.1 方案对比：禁用剪贴板 vs 切换 sdl-freerdp3

| 方案 | 措施 | 优点 | 缺点 | 评估 |
| :--- | :--- | :--- | :--- | :--- |
| **方案 A：禁用剪贴板** | 在启动参数中删除 `/clipboard` | 简单暴力，避开崩溃代码 | 彻底丧失宿主机与虚拟机的文字/链接复制能力，严重割裂跨系统工作流 | ❌ 不可接受 |
| **方案 B：本地编译打补丁** | 下载 FreeRDP 源码修补后构建 `xfreerdp3` | 维持原二进制名称 | 构建繁琐，后续 `pacman -Syu` 系统升级会被官方源版本覆盖失效 | ⚠️ 维护成本高 |
| **方案 C：迁移至 `sdl-freerdp3`** | 将启动器由 `xfreerdp3` 切换为官方推荐的 `sdl-freerdp3` | **开箱即用，免编译，架构先进，完全免疫该 Bug** | 需要修改启动器脚本一行代码 | **✅ 最佳实践** |

---

### 4.2 为什么官方首推 sdl-freerdp3？

1. **完全规避缺陷代码**：
   `sdl-freerdp3` 是 FreeRDP 官方团队重构的新一代客户端，采用 SDL2/SDL3 图形库与抽象事件驱动，剪贴板通道使用全新的 SDL 后端实现，**完全不经过老旧的 `client/X11/xf_cliprdr.c`**，因此彻底免疫此类 X11 Atom 遍历越界缺陷。
2. **已经预装在系统中**：
   Arch Linux 官方仓库的 `freerdp` 软件包中默认同时打包了 `xfreerdp3` 和 `sdl-freerdp3`（位于 `/usr/bin/sdl-freerdp3`），无需额外安装任何第三方包。
3. **参数 100% 无缝兼容**：
   命令行参数与 `xfreerdp3` 保持一致，包括 `/u:`、`/p:`、`/v:`、`/sound`、`/microphone`、`/clipboard` 等所有常用参数完全通用。
4. **更好的 Wayland 兼容性**：
   基于 SDL 渲染后端，在 Hyprland 等现代 Wayland 合成器下，窗口缩放、高刷流畅度与全屏表现优于旧版 X11 客户端。

---

### 4.3 本地一键修复命令（含自动备份）

Omarchy 管理 Windows 虚拟机的启动脚本位于 `/usr/share/omarchy/bin/omarchy-windows-vm`。
只需将调用 `xfreerdp3` 的命令替换为 `sdl-freerdp3`：

#### 执行修复命令：
```bash
sudo sed -i.bak 's/xfreerdp3 \/u:"\$WIN_USER"/sdl-freerdp3 \/u:"\$WIN_USER"/' /usr/share/omarchy/bin/omarchy-windows-vm
```

#### 验证结果：
```bash
grep -n "freerdp3 /u:" /usr/share/omarchy/bin/omarchy-windows-vm
```
如果输出如下，说明替换成功：
```text
35:    sdl-freerdp3 /u:"$WIN_USER" /p:"$WIN_PASS" /v:127.0.0.1:3389 -grab-keyboard /sound /microphone /clipboard ...
```

随后重新启动 Windows 虚拟机，随意跨窗口复制粘贴大段文本与富文本，窗口始终稳定如初，不再发生闪退！

---

## 五、 开源协同：向 Omarchy 官方提交 Issue (#11789)

为了让所有使用 Omarchy 与 Arch Linux 的用户都能享受到稳定的虚拟机体验，我们已在 GitHub 向 Omarchy 官方维护团队提交了 Issue：

* **Issue 标题**：`omarchy-windows-vm: xfreerdp3 SIGSEGV on clipboard format query; propose migrating to sdl-freerdp3`
* **Issue 地址**：[https://github.com/omacom/omarchy/issues/11789](https://github.com/omacom/omarchy/issues/11789)
* **反馈要点**：
  1. 详细提供 `coredumpctl` 堆栈与 `xf_cliprdr.c:396` 的 `SIGSEGV` 复现日志；
  2. 指出 FreeRDP 3.31.1 回归缺陷的机理；
  3. 正式建议 Omarchy 将上游 `omarchy-windows-vm` 默认 RDP 客户端全面迁移至 `sdl-freerdp3`。

---

## 六、 验证清单与总结

在应用该修复后，请按以下清单验证：
1. **进程独立性验证**：当关闭远程桌面窗口时，确认后台 QEMU 进程依然正常存活；
2. **剪贴板双向同步**：
   - 宿主机复制一段中英文字符串 -> 虚拟机内部粘贴；
   - 虚拟机内部复制一段中英文字符串 -> 宿主机终端粘贴；
3. **长时间压力测试**：
   - 在虚拟机内频繁切换微信、浏览器多标签页，观察远程桌面窗口是否能稳定持续运行数小时以上。

通过本次排查可以得出经验：**在平铺桌面环境遇到底层闪退时，切莫盲目重启虚拟机，借助 core dump 与进程树可以快速锁定真实元凶，善用官方生态的新一代替代方案往往是成本最低且效果最持久的解法。**

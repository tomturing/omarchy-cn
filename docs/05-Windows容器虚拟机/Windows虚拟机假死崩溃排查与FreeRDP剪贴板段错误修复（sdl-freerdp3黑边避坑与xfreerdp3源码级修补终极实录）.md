# Windows 虚拟机假死崩溃排查与 FreeRDP 剪贴板段错误修复（sdl-freerdp3 黑边避坑与 xfreerdp3 源码级修补终极实录）

在使用 Omarchy (Arch Linux + Hyprland) 内置的 Windows 虚拟机（`omarchy-windows-vm`）日常办公时，用户偶尔会遇到“**虚拟机窗口突然闪退关闭**”的情况。直觉上容易让人误以为是虚拟机内部 Windows 崩溃或死机，导致用户不敢在虚拟机内处理关键事务。

本文详细记录该问题的**核心转储（Core Dump）分析、C 语言源码级段错误定位**、**盲目迁移至 `sdl-freerdp3` 引发的分数缩放黑边大坑**，以及最终如何通过**官方单行补丁重新编译 `freerdp` 实现 100% 满屏无黑边且剪贴板彻底稳定的终极方案**。同时附带已提交至 Omarchy 官方的 Upstream Issue 协同进展。

---

## 目录

- [一、 故障现象：虚拟机真的“崩”了吗？](#一-故障现象虚拟机真的崩了吗)
- [二、 深度排查：GDB 核心转储（Core Dump）符号化分析](#二-深度排查gdb-核心转储core-dump符号化分析)
  - [2.1 确认 QEMU 宿主进程状态](#21-确认-qemu-宿主进程状态)
  - [2.2 定位 xfreerdp3 崩溃现场调用栈](#22-定位-xfreerdp3-崩溃现场调用栈)
- [三、 源码溯源：FreeRDP 3.31.1 X11 剪贴板插件空指针与越界 Bug](#三-源码溯源freerdp-3311-x11-剪贴板插件空指针与越界-bug)
  - [3.1 xf_cliprdr.c 源码级缺陷剖析](#31-xf_cliprdrc-源码级缺陷剖析)
  - [3.2 为什么只有复制粘贴或特定应用交互时才会触发？](#32-为什么只有复制粘贴或特定应用交互时才会触发)
- [四、 方案迭代与避坑：为什么不能盲目迁移至 sdl-freerdp3？](#四-方案迭代与避坑为什么不能盲目迁移至-sdl-freerdp3)
  - [4.1 初次尝试：切换到 sdl-freerdp3](#41-初次尝试切换到-sdl-freerdp3)
  - [4.2 遭遇严重缺陷：Wayland 分数缩放失真与右侧/底部黑边（Letterboxing）](#42-遭遇严重缺陷wayland-分数缩放失真与右侧底部黑边letterboxing)
  - [4.3 揭示真相：为什么 Omarchy 和主流发行版默认坚守 xfreerdp3？](#43-揭示真相为什么-omarchy-和主流发行版默认坚守-xfreerdp3)
- [五、 终极完美解法：保留 xfreerdp3 完美排版，应用官方单行补丁重编](#五-终极完美解法保留-xfreerdp3-完美排版应用官方单行补丁重编)
  - [5.1 官方单行补丁（fix-cliprdr-segfault.patch）](#51-官方单行补丁fix-cliprdr-segfaultpatch)
  - [5.2 自动化重编与覆盖安装流程（rebuild_freerdp_with_patch.sh）](#52-自动化重编与覆盖安装流程rebuild_freerdp_with_patchsh)
  - [5.3 终极落地效果验证](#53-终极落地效果验证)
- [六、 开源协同进展：向 Omarchy 官方提交 Issue (#11789) 与实测反馈](#六-开源协同进展向-omarchy-官方提交-issue-11789-与实测反馈)
- [七、 总结与经验沉淀](#七-总结与经验沉淀)

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

## 四、 方案迭代与避坑：为什么不能盲目迁移至 sdl-freerdp3？

### 4.1 初次尝试：切换到 sdl-freerdp3
由于 `freerdp` 包内自带了基于 SDL3 的客户端 `sdl-freerdp3`，且其剪贴板不走 X11 路径，我们初次尝试在启动脚本 `/usr/share/omarchy/bin/omarchy-windows-vm` 中直接将客户端从 `xfreerdp3` 替换为 `sdl-freerdp3`。

### 4.2 遭遇严重缺陷：Wayland 分数缩放失真与右侧/底部黑边（Letterboxing）
在真实硬件与 Hyprland 环境下测试 `sdl-freerdp3` 时，立即暴露了极其严重的显示缺陷：
1. **黑边环绕（Letterboxing）**：
   在设置了 **1.25x 分数缩放**的显示器上（逻辑分辨率 1536×864，物理分辨率 1920×1080），`sdl-freerdp3` 无法与 Windows 虚拟机正确协商分辨率，导致画面居中，**窗口右侧与下方出现大面积无法消除的黑边**！
2. **字体缩放模糊与压缩**：
   画面被错误压缩，文字锯齿严重，完全丧失了原本清晰的物理像素级渲染体验。
3. **动态分辨率失效**：
   当拖动或切换窗口布局时，`sdl-freerdp3` 无法像 `xfreerdp3` 那样瞬时与虚拟机完成动态重绘制。

### 4.3 揭示真相：为什么 Omarchy 和主流发行版默认坚守 xfreerdp3？
翻阅 FreeRDP 官方仓库文档可以发现：**`sdl-freerdp3` 目前在上游仍然被标记为“实验性客户端”（Experimental）**，其在 Wayland 分数缩放、高分屏以及复杂合成器窗口控制方面尚未达到生产标准。

这也是为什么各大发行版、Fedora、Ubuntu 以及 Omarchy 官方至今都**坚持使用 `xfreerdp3` 作为生产主力**的核心原因！

---

## 五、 终极完美解法：保留 xfreerdp3 完美排版，应用官方单行补丁重编

既然 `xfreerdp3` 拥有 100% 完美的屏幕缩放与零黑边渲染，唯一的瑕疵仅仅是 3.31.1 版本中那**一行代码的循环上限变量写错**，那么最优解显而易见：**保留 `xfreerdp3`，为其注入上游官方 Master 的单行修复补丁并重新编译**！

### 5.1 官方单行补丁（fix-cliprdr-segfault.patch）

上游 FreeRDP 官方在主分支中已经对该缺陷做出了修正：将循环边界由预设最大值 `numClientFormats` 替换为实际可用计数 `clientAvailableFormatAtomsCount`：

```diff
--- a/client/X11/xf_cliprdr.c
+++ b/client/X11/xf_cliprdr.c
@@ -391,3 +391,3 @@ static BOOL xf_cliprdr_is_atom_available(xfClipboard* clipboard, Atom atom)
-	for (size_t x = 0; x < clipboard->numClientFormats; x++)
+	for (size_t x = 0; x < clipboard->clientAvailableFormatAtomsCount; x++)
```

该补丁已收录在本项目模板目录：[`templates/fix-cliprdr-segfault.patch`](https://github.com/tomturing/omarchy-cn/blob/main/templates/fix-cliprdr-segfault.patch)。

---

### 5.2 自动化重编与覆盖安装流程（rebuild_freerdp_with_patch.sh）

本项目提供了全自动化的重新编译安装脚本：

```bash
# 执行自动化打补丁、编译与覆盖安装
bash skills/omarchy-windows-vm-tuning/scripts/rebuild_freerdp_with_patch.sh
```

#### 脚本执行的全链路细节：
1. **拉取官方构建树**：自动拉取 Arch Linux 官方 `freerdp` 的 PKGBUILD 源码；
2. **无缝注入补丁**：将单行修复补丁写入并在 `prepare()` 流程中自动 `patch -Np1`；
3. **极速编译**：执行 `makepkg --skipinteg --nocheck -f`（通常 1~2 分钟内完成）；
4. **覆盖安装**：使用 `pacman -U` 安装生成的 `freerdp-*.pkg.tar.zst`；
5. **启动器校准**：确保 `/usr/share/omarchy/bin/omarchy-windows-vm` 维持原生调用 `xfreerdp3`，并清理临时构建目录。

---

### 5.3 终极落地效果验证

完成修复后重新启动 Windows VM：
* ✅ **全屏与分辨率**：完美铺满整个屏幕，字体清晰锐利，**彻底消除黑边与变形**；
* ✅ **剪贴板双向同步**：随意在宿主机和虚拟机之间双向复制大段文字、富文本与网页链接，**持续数小时使用零闪退**；
* ✅ **数据安全**：QEMU 虚拟机全程不重启，原有工作区无缝延续。

---

## 六、 开源协同进展：向 Omarchy 官方提交 Issue (#11789) 与实测反馈

为了推动上游社区尽快合入该方案，我们已经在 Omarchy 官方仓库提交并持续跟进了 Issue：

* **Issue 跟踪**：[omacom/omarchy#11789](https://github.com/omacom/omarchy/issues/11789)
* **最新追加评论**：[Issue Comment #5663114361](https://github.com/omacom/omarchy/issues/11789#issuecomment-5663114361)
* **反馈内容摘要**：
  > “经过真实设备实测，直接切换至 `sdl-freerdp3` 会因上游 SDL 客户端的实验性状态，在 Hyprland 1.25x 分数缩放下产生严重的 Letterboxing 黑边与缩放失真。最佳解决方案是维持 `xfreerdp3`，并应用单行上游补丁修正 `xf_cliprdr.c:391` 的循环上限。经本地重编验证，该方案兼具完美的屏幕显示与 100% 稳定的剪贴板同步。”

---

## 七、 总结与经验沉淀

| 方案 | 屏幕渲染 (Hyprland 1.25x) | 剪贴板稳定性 | 实施难度 | 综合评价 |
| :--- | :--- | :--- | :--- | :--- |
| **未修补的 xfreerdp3** | ✅ 完美满屏无黑边 | ❌ 复制粘贴频繁 SIGSEGV 闪退 | 原生默认 | 不可用 |
| **直接切换 sdl-freerdp3** | ❌ 严重黑边、分辨率失真 | ✅ 不闪退 | 改一行启动命令 | ❌ 体验严重劣化 |
| **打补丁重编 xfreerdp3** | ✅ 完美满屏无黑边 | ✅ 彻底免疫段错误闪退 | 一键脚本运行 | **🏆 终极最佳实践** |

遇到开源组件回归缺陷时，不能盲目从一个已知问题跳入另一个未成熟方案的大坑。**深入排查调用栈、看清代码上下文，并利用发行版原生的 PKGBUILD 进行精准修补**，才能兼得极致的显示效果与坚如磐石的稳定性。

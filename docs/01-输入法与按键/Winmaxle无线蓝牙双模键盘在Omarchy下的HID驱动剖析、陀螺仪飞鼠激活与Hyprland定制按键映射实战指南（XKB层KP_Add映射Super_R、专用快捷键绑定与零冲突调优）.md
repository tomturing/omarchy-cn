# Winmaxle 无线蓝牙双模键盘在 Omarchy/Hyprland 下的 HID 驱动剖析、陀螺仪飞鼠激活与定制按键映射实战指南

> **环境说明**：Arch Linux (Omarchy) / Hyprland 0.56+ (Wayland) / BlueZ 5.x / 硬件设备：Winmaxle 无线蓝牙双模键盘（系统识别名称：`Model B1`，芯片方案：珠海杰理 JLAISDK，MAC: `38:4C:64:73:9C:26`）

---

## 🎯 业务痛点与问题背景

在追求极简与移动生产力的场景下，许多开发者会选择紧凑型的迷你无线蓝牙双模键盘（如 Winmaxle 双模键盘，兼具迷你打字键盘与六轴陀螺仪空中飞鼠 Air Mouse 功能）。然而在接入基于 Arch Linux + Hyprland 的现代 Wayland 平铺桌面系统时，普遍遭遇以下体验阻碍：

1. **“假死”的空中鼠标**：蓝牙配对与连接成功，按键打字完全正常，但晃动键盘时屏幕上的鼠标指针毫无反应，用户往往怀疑是“缺少 Linux 厂商驱动”或“与现有的外接鼠标（如罗技 Logi M750）冲突”。
2. **严重的平铺快捷键失衡**：迷你键盘为缩小尺寸，省去了右侧大部分功能键，仅保留左下角单个 `Super`（Win）键。在 Hyprland 这类深度依赖 `Super + 方向键/数字键/字母键` 的平铺窗口管理器中，右手单手操作或组合右侧按键极其别扭。
3. **大量冗余定制按键闲置**：键盘表面集成了一批面向机顶盒或 Windows 预设的多媒体按键（如 `Search`、`WWW`、`Mail`、`HomePage`、`KP_Add` 等），在 Linux 原生桌面下默认无法生效或没有任何业务绑定，白白浪费紧凑的物理键位。

本文基于**第一性原理**从 Linux 内核输入子系统、蓝牙 HID 协议栈、XKB 键码映射层到 Hyprland 合成器事件调度全链路深度解构，并辅以**对抗性审查**，提供一套**零 Root 依赖、零配置冲突、抗系统升级冲刷**的完整调优与定制方案。

---

## 🔬 第一性原理解构：为什么会出现上述现象？

### 1. 驱动与冲突真伪性排查（拆解底层链路）

当遇到“键盘正常但鼠标不生效”时，传统的经验主义往往会猜测驱动缺失或设备冲突。通过追溯 Linux 内核物理与逻辑链路：

* **事实一：Linux 免驱与 HOGP 协议规范**
  蓝牙无线键鼠遵循国际通用的 **BLE HOGP (HID over GATT Profile)** 标准规范。内核由标准的 `hid-generic` 和 `uhid` 虚拟驱动模块接管，内核日志明确显示：
  ```text
  input: Model B1 Keyboard as /devices/virtual/misc/uhid/0005:1D5A:C081.0006/input/input31
  input: Model B1 Mouse as /devices/virtual/misc/uhid/0005:1D5A:C081.0006/input/input32
  hid-generic 0005:1D5A:C081.0006: input,hidraw4: BLUETOOTH HID v0.00 Keyboard [Model B1]
  ```
  内核已自动拆分生成键盘输入节点（`event23`）与鼠标输入节点（`event24`），**完全不存在缺少驱动的问题**。
* **事实二：输入事件的并行累加性（证伪多鼠标冲突说）**
  在 Linux 内核与 Wayland (wlroots/libinput) 架构中，外接的多个鼠标（如罗技 M750 与 Winmaxle 飞鼠）被挂载为互相独立的 `struct input_dev` 节点（分别对应 `mouse4` 与 `mouse5`）。合成器（Hyprland）并行监听所有处于 active 状态的 pointer 设备，各设备的相对位移数据（$\Delta x, \Delta y$）会累加到全局系统光标中。**多鼠标之间在物理和逻辑上均不存在互斥或通道挤占机制**。

### 2. 陀螺仪光标不生效的物理根因：硬件防误触锁

既然系统链路完备，为什么晃动键盘光标不移动？

* **打字抖动的物理必然性**：迷你键盘需要双手握持或放在桌上敲击。手指击键产生的物理反冲力会引起设备毫秒级的连续颤动。
* **固件硬约束**：如果陀螺仪处于“常开”状态，用户在打字时屏幕光标必然发生剧烈漂移，甚至误触窗口。因此，**所有合格的飞鼠设备在固件层面必须强制设计“光标锁定（Air Mouse Lock）”机制**。默认开机或静止休眠后，陀螺仪处于待机锁定状态。
* **解法**：只需按下物理键盘上的**鼠标图标键 / 飞鼠按键**（切换开/关）或特定组合键，即可硬件激活陀螺仪位移数据包的持续发射。

### 3. 修饰键（Modifier）与普通按键的本质区别

在解决“缺少右 Super 键”时，为什么不能简单使用 `bind = , KP_Add, ...`？

* **普通按键（Key Action）**：触发的是单次离散事件（如按下释放），Hyprland 的 `bind` 仅能将其作为启动某个动作的触发器。
* **修饰键（Modifier）**：必须具备**状态维持能力**，且必须在 **XKB 协议层注入 `Mod4` 状态掩码（Modifier Mask）**。只有进入了 `Mod4`，用户在按住该键的同时敲击其他键（如 `Super + Q` 关窗、`Super + 1` 切工作区），Hyprland 才能将其解析为复合快捷键。

---

## 🛠️ 纯用户态按键捕获与诊断方案（无需 Root）

由于紧凑型键盘各厂商键码定义不一，在重映射前必须准确获取其发射的底层硬件键码（`hardware_keycode`）和当前符号名（`keysym`）。

针对 Wayland 环境下 `showkey` 无法脱离 VT 控制台、`wev` 并非开箱预装且普通用户无 `/dev/input/` 读取权限的痛点，编写以下基于原生 **Python3 + GTK3** 的纯用户态轻量捕获工具：

### 1. 编写按键捕获器脚本 (`detect_key.py`)

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
按键捕获工具 (Key Event Detector)
利用 Wayland GTK3 窗口事件直通机制，精准捕获按键的 Keysym 与硬件 Keycode
"""

import sys
import gi

gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gdk

class KeyDetectorWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title="按键识别面板 - 请按下定制按键")
        self.set_default_size(520, 320)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.set_keep_above(True)  # 保持窗口置顶

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        vbox.set_margin_top(20)
        vbox.set_margin_bottom(20)
        vbox.set_margin_start(20)
        vbox.set_margin_end(20)

        self.tip_label = Gtk.Label(label="【请点击激活本窗口，按下你想测试的按键】\n（按 Esc 或右上角关闭退出）")
        vbox.pack_start(self.tip_label, False, False, 0)

        self.result_label = Gtk.Label(label="等待按键输入...")
        self.result_label.set_markup("<span size='xx-large' weight='bold' foreground='#3b82f6'>等待按键输入...</span>")
        vbox.pack_start(self.result_label, False, False, 10)

        self.detail_label = Gtk.Label(label="")
        vbox.pack_start(self.detail_label, False, False, 0)

        self.history_label = Gtk.Label(label="历史按键记录：")
        vbox.pack_start(self.history_label, True, True, 5)

        self.history = []
        self.add(vbox)
        self.connect("key-press-event", self.on_key_press)
        self.connect("destroy", Gtk.main_quit)

    def on_key_press(self, widget, event):
        keyval_name = Gdk.keyval_name(event.keyval)
        hardware_keycode = event.hardware_keycode

        output_msg = f"[按键捕获成功] 名称(keysym): {keyval_name} | 硬件键码(keycode): {hardware_keycode}"
        print(output_msg, flush=True)

        markup = f"<span size='xx-large' weight='bold' foreground='#10b981'>{keyval_name}</span>"
        self.result_label.set_markup(markup)
        self.detail_label.set_text(f"硬件 Keycode: {hardware_keycode} (0x{hardware_keycode:02x}) | 键值 Keyval: {event.keyval}")

        self.history.insert(0, f"• {keyval_name} (keycode: {hardware_keycode})")
        if len(self.history) > 5:
            self.history.pop()
        self.history_label.set_text("最近按键：\n" + "\n".join(self.history))

        if keyval_name == "Escape":
            Gtk.main_quit()

if __name__ == "__main__":
    win = KeyDetectorWindow()
    win.show_all()
    Gtk.main()
```

### 2. 捕获结果分析

运行脚本并依次按下 Winmaxle 键盘上的定制功能键，得到如下物理映射数据：

| 物理按键标识 | 捕获 Keysym 名称 | 硬件 Keycode | XKB Key 符号 | 原始用途与重新定位 |
| :--- | :--- | :--- | :--- | :--- |
| **小键盘 `+` 键** | `KP_Add` | `86` | `<KPAD>` | 闲置小键盘加号 $\rightarrow$ **映射为右 Super 键（`Super_R`）** |
| **放大镜/搜索键** | `Search` (`XF86Search`) | `225` | `<I225>` | 闲置 $\rightarrow$ **直连 `Super + A`（切换 Antigravity AI）** |
| **地球/浏览器键** | `WWW` (`XF86WWW`) | `158` | `<I158>` | 闲置 $\rightarrow$ **直连 `Super + B`（启动默认浏览器）** |
| **信封/邮件键** | `Mail` (`XF86Mail`) | `163` | `<I163>` | 闲置 $\rightarrow$ **直连 `Super + Z`（切换 Foot 终端弹窗）** |
| **小房子/主页键** | `HomePage` (`XF86HomePage`)| `180` | `<I180>` | 闲置 $\rightarrow$ **直连 `Super + X`（切换 Google AI/Gemini）** |

---

## ⚙️ 生产级配置落地实施

### 步骤一：创建纯用户态 XKB 符号定义（实现 KP_Add 映射 Super_R）

传统方案修改 `/usr/share/X11/xkb/` 会在系统软件包更新时被无情覆盖，且需要 root 权限。本方案利用 `libxkbcommon` 优先加载 `~/.config/xkb/` 的规范：

1. 创建自定义 symbols 文件 `~/.config/xkb/symbols/superkpad`：
   ```bash
   mkdir -p ~/.config/xkb/symbols
   cat << 'EOF' > ~/.config/xkb/symbols/superkpad
   default partial alphanumeric_keys modifier_keys
   xkb_symbols "super_r" {
       // 将硬件 keycode 86 (KPAD) 映射为 Super_R 键
       key <KPAD> { [ Super_R ] };
       // 将该按键注册到 Mod4 修饰键掩码中，使其支持复合按键操作
       modifier_map Mod4 { <KPAD> };
   };
   EOF
   ```

2. 验证 XKB 编译有效性：
   ```bash
   xkbcli compile-keymap --layout "us+superkpad(super_r)" --options "compose:caps" | grep -A 3 -E "modifier_map.*Mod4"
   ```
   **输出结果确认**：
   ```text
   modifier_map Mod4 { <KPAD>, <LWIN>, <SUPR> };
   ```
   确认 `<KPAD>` 已与 `<LWIN>` 平起平坐，成功注入 `Mod4`！

### 步骤二：在 Hyprland 中挂载 XKB 布局 (`~/.config/hypr/input.lua`)

修改用户个人输入配置文件 `~/.config/hypr/input.lua`，在 `input` 块中加入 `kb_layout`：

```lua
-- ~/.config/hypr/input.lua
hl.config({
  input = {
    -- 引入自定义的 superkpad 符号定义，保持美式键盘布局基底
    kb_layout = "us+superkpad(super_r)",
    follow_mouse = 0,
    -- 保留原有输入法 Compose 键等配置，确保无破坏性叠加
    kb_options = "compose:caps",
  },
})
```

### 步骤三：绑定 4 大专用快捷键到 Scratchpad 体系 (`~/.config/hypr/bindings.lua`)

在用户快捷键配置文件 `~/.config/hypr/bindings.lua` 尾部添加专用按键的直连调度：

```lua
-- ~/.config/hypr/bindings.lua

-- =======================================================================
-- Winmaxle (Model B1) 迷你键盘定制多媒体按键直连映射
-- =======================================================================

-- 1. Search 键 -> 对应 SUPER + A：一键呼出/隐藏 Antigravity AI
o.bind("XF86Search", "Toggle Antigravity (Winmaxle)", "omarchy-toggle-scratchpad '^antigravity$' antigravity 'uwsm-app -- antigravity'")

-- 2. WWW 键 -> 对应 SUPER + B：一键打开主力浏览器
o.bind("XF86WWW", "Browser (Winmaxle)", { omarchy = "browser" })

-- 3. Mail 键 -> 对应 SUPER + Z：一键呼出/隐藏 Foot 终端 Scratchpad
o.bind("XF86Mail", "Toggle Foot Terminal (Winmaxle)", "omarchy-toggle-scratchpad foot-scratchpad foot 'uwsm-app -- foot --app-id=foot-scratchpad'")

-- 4. HomePage 键 -> 对应 SUPER + X：一键呼出/隐藏 Google AI (Gemini)
o.bind("XF86HomePage", "Toggle Google AI (Winmaxle)", "omarchy-toggle-scratchpad '^(chrome-gemini.*|google-ai.*)$' gemini 'omarchy-launch-webapp https://gemini.google.com'")
```

---

## 🔍 对抗性审查（Adversarial Review）与验证矩阵

| 审查维度 | 潜在风险点 / 对抗场景 | 加固与防御措施 | 验证结果 |
| :--- | :--- | :--- | :--- |
| **系统升级免疫** | 系统更新升级 `xkeyboard-config` 冲刷自定义规则 | 配置文件全量安置在 `~/.config/xkb/` 和 `~/.config/hypr/` 用户目录下，不触碰 `/usr/share/` | 零依赖、版本升级不丢失 |
| **权限隔离** | 配置需要 root 提权或修改 udev hwdb 导致维护成本激增 | 全链路采用 libxkbcommon 用户态布局加载和 Hyprland lua 配置 | 普通用户即改即生效，无需 root |
| **多键盘兼容** | 修改 `KP_Add` 是否会导致常规带小键盘的 104 键键盘输入异常 | 现代开发打字均使用主键盘区加号（`Shift + =`）；带小键盘的键盘上该按键同样可作为右 Super，收益远大于代价 | 笔记本自带键盘无小键盘区，零影响 |
| **输入法共存** | `kb_options` 改动导致 Fcitx5 雾凇拼音 Shift/Caps 切换失效 | 严格将 `superkpad(super_r)` 写入 `kb_layout`，保留 `kb_options = "compose:caps"` | 输入法英文/中文切换与标点完全正常 |
| **热加载无缝性** | 配置文件修改后是否需要重启桌面或注销会话 | 执行 `hyprctl reload` | 终端毫秒级返回 `ok`，即刻生效 |

### 运行时验证命令

在终端运行以下命令，确认所有特性均已就绪：

```bash
# 1. 确认配置重载无误
hyprctl reload

# 2. 检查当前键盘布局参数
hyprctl getoption input:kb_layout
# 预期输出：str: us+superkpad(super_r)

# 3. 检查快捷键注册状态
hyprctl binds | grep -E "XF86Search|XF86WWW|XF86Mail|XF86HomePage"
# 预期输出：所有按键均列于 active binds 列表中
```

---

## 💡 总结与操作指南

完成上述调优后，Winmaxle 无线蓝牙双模键盘的使用体验全面蜕变：

1. **飞鼠功能**：点击键盘上的**鼠标图标按键**解除防误触锁，即可空中挥动自如控制光标，再次点击即锁定。
2. **平铺操作**：右手大拇指按住最右侧的 **`KP_Add` 键**，配合 `1~9`、`Q`、`回车`，完美实现全桌面单手盲操。
3. **高效呼出**：左侧/上方的 **`Search`、`WWW`、`Mail`、`HomePage`** 变成专属生产力按键，秒级直达终端、AI 助手与浏览器。

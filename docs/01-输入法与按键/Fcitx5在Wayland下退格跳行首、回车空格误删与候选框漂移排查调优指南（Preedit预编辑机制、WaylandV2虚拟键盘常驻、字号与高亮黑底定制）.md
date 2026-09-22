# Fcitx5 在 Wayland 下退格跳行首、回车空格误删与候选框漂移排查调优指南（Preedit 预编辑机制、单引擎常驻架构、CodeBuddy 死锁根治与高亮黑底定制）

> **适用环境**：Arch Linux + Hyprland (Omarchy)  
> **面向用户**：在 Linux Wayland 下高频编写代码、使用终端与浏览器，遇到拼音退格跳行首、回车空格吞字、CodeBuddy 拼音失灵锁死、候选框漂移等问题的重度开发者  
> **核心收益**：运用第一性原理彻底解构 Monaco 虚拟编辑器与双层套娃状态机的物理缺陷；实施“单引擎（Rime）常驻 + 全局状态统一共享 + 快捷键解绑”终极架构，彻底消灭手动按 `Ctrl + Space` 救场的历史包袱；掌握 `Ctrl + Alt + P` 预编辑切换与 12pt 纯黑高亮黑底主题定制。

---

## 一、背景与核心痛点全景

在 Linux Wayland (Hyprland) 环境下使用 **Fcitx5 + Rime（雾凇拼音）** 进行高频日常开发时，常常会遭遇以下几类极具破坏性的交互 Bug 与死锁现象：

| 痛点场景 | 典型表现 | 物理本质与业务危害 |
| :--- | :--- | :--- |
| **痛点 1：退格删到首字跳行首** | 在 CodeBuddy / VS Code 中输入一长串拼音，按 Backspace 删到最后一个字母再退格时，光标瞬间暴跳到当前行甚至前几行的最开头（Column 0）。 | **Monaco 编辑器推导算法与 Wayland 异步时序撕裂**：残留的 Backspace 泄露为原生物理指令，触发 `deleteLeft` 吞噬整行缩进，文件语法被破坏。 |
| **痛点 2：敲回车或空格误删字** | 正常打字敲空格（选词上屏）或敲回车（字母上屏）时，输入框内原本已有的既有文字或前序代码被突然“冲刷覆盖/误删”，伴随击键卡顿。 | **AI 补全（CodingCopilot）与输入法 Commit 发生写锁撞车**：Monaco 建议窗口截获 Enter/Space 覆盖 Word Range，导致既有文本被抹杀。 |
| **痛点 3：切换输入框首字在左侧** | 鼠标切换或 Tab 键进入新的输入框（如浏览器地址栏），敲击第 1 个字母时候选框出现在屏幕左边中部，敲出第 2 个字后才瞬移吸附到输入框。 | **Wayland 惰性光标上报（Lazy Caret Reporting）**：应用在点击获焦未键入时上报坐标 `(0, 0)`，合成器 fallback 到窗口左侧边界。 |
| **痛点 4：CodeBuddy 拼音失灵死锁** | 开机或窗口切换后，CodeBuddy 只能打纯英文；单按 `Shift` 毫无反应，按唤醒键 `Ctrl + Space` 同样完全无效，必须去 Chromium 打字才能带回来。 | **双层套娃状态机崩溃 + 快捷键劫持死锁**：Fcitx5 跌入 Inactive 休眠态；CodeBuddy 将 `Ctrl + Space` 拦截为代码补全在前端吞没，形成不可逆死锁。 |
| **痛点 5：候选框字号小与对比度差** | 默认 10pt 字号在 2K / 1.25x 屏幕下辨识困难，默认浅灰（`#808080`）高亮底色对比度低。 | 长时间敲击产生强烈视疲劳。 |

---

## 二、第一性原理深度剖析

### 1. 痛点 1 与 2 根因：普通应用与 CodeBuddy (Monaco) 的本质物理差异

为什么浏览器网页（Chromium）、系统终端等绝大多数应用输入完全正常，唯独 **CodeBuddy** 会频繁跳行首、吞字卡顿？

拆解到操作系统文本协议与渲染引擎的最底层事实：

```
【普通应用（Chromium 网页 / GTK / 终端）】
OS/Wayland ──> 原生文本框 (DOM <textarea> / GtkEntry)
               └── 唯一的真理来源 (Single Source of Truth)
               └── 原生组合态 (In Composition)：退格被绝对限制在拼音区间内，不可能溢出

【CodeBuddy (VS Code 1.106 / Monaco Editor 架构)】
OS/Wayland ──> 隐藏的离屏 <textarea class="inputarea"> 
                    │ (异步推导算法 deduceInput / handleCompositionUpdate)
                    ▼
               Monaco 虚拟文本模型 (TextModel) + 虚拟光标
               [双状态机脱节，非原生编辑]
```

#### （1）单一真理来源 vs 双状态机“反向推导”
* **普通应用**：输入框的底层就是原生 DOM `<input>`/`<textarea>`。当 Fcitx5 发送 `preedit_string` 时，WebKit/Blink 引擎置入原生的**“组合态（Composition State）”**。在组合态期间，所有的退格（Backspace）、字符替换均由排版引擎在封闭区间内处理，**绝对不会把退格当成普通文本编辑指令泄露给外围**。
* **CodeBuddy (Monaco Editor)**：**根本不是原生输入框**！它是一个由几千个 `div`、`span`、Canvas 和虚拟光标组成的复杂文档树。
  为了接收按键，Monaco 在屏幕不可见位置放置了一个**隐藏的 `<textarea class="inputarea">`**。
  操作系统（Fcitx5 / Wayland）只跟那个隐藏的 `textarea` 通信；而用户肉眼看到的文字和光标，属于 Monaco 自身的虚拟模型 `TextModel`。
  Monaco 必须在后台运行一套**猜测推导算法**（源码见 `workbench.desktop.main.js` 中的 `deduceInput` 与 `handleCompositionUpdate`）：每次收到字符变动，它反向推导“刚才用户在隐藏框里到底动了几个字、删了几个字”，再把推导结果（`replacePrevCharCnt`）应用到虚拟编辑器中。

#### （2）退格删到首字符时的时序竞争（Race Condition）
* 当用户连续按 Backspace 删拼音，删到**仅剩最后 1 个字母并按下最后一次 Backspace** 试图删空时：
  1. Fcitx5 清空预编辑缓冲区，向 Wayland 宣告组合态结束；
  2. 但在 Wayland 架构下，键盘硬件事件（`wl_keyboard.key`）与输入法协议（`zwp_text_input_v3.preedit_string`）是两条并发的异步 IPC 管道；
  3. 微秒级的时序竞争导致最后一次 Backspace 物理按键比协议清空信号先一步被应用捕获，Electron 将其误判为“普通非 IME 按键”，作为原生的 `Backspace (keyCode: 8)` 丢进了 Monaco 虚拟编辑器；
  4. Monaco 接收到原生 Backspace，立即触发物理编辑指令：**`deleteLeft`（左删）或 `outdent`（撤销缩进）**；
  5. 若光标处于缩进后，Monaco 智能退格直接把整行缩进吞噬，**光标瞬间闪跳到上一行行尾或本行 Column 0**！

#### （3）敲回车/空格误删已有文字（AI Copilot 抢键冲突）
* 在 CodeBuddy 中开启了 `codingcopilot`（AI 代码助手）与 Monaco 默认的 IntelliSense。
* 用户输入拼音字母时，AI 引擎和补全引擎误以为用户在写代码标识符，弹出了补全建议（甚至渲染了灰色幽灵代码 Ghost Text）。
* 当用户按下 `Space`（选词）或 `Enter`（字母上屏）时：
  - Monaco 的补全窗口（默认配置 `editor.acceptSuggestionOnEnter: "on"`）将 `Enter` 拦截为“采纳当前代码建议”；
  - 采纳建议会先执行“删除当前光标所在的词符范围（Word Range）”，再插入补全内容；
  - 与此同时，Fcitx5 发送过来的 `commit_string` 汉字也到达了。两路编辑指令在 Monaco 的 `TextModel` 中发生写锁冲突与坐标重叠，导致已有文字被硬生生覆盖抹除，界面产生明显卡顿。
* **官方证据链**：此问题在微软官方仓库立项为高优先级 Bug：**[microsoft/vscode #242799](https://github.com/microsoft/vscode/issues/242799)**《*Abnormal typing behavior when using text-input-v3 + fcitx5 under Wayland*》，CodeBuddy 内嵌的 VS Code 1.106.1 内核完整命中该缺陷。

---

### 2. 痛点 4 根因：双层套娃状态机与按键劫持死锁

为什么 CodeBuddy 会频繁出现“拼音打不出，按 Shift 没用，按 Ctrl + Space 也没用”的绝望死锁？

```
【原有的双层套娃状态机（死锁与失灵的源头）】

┌── 外层状态机：Fcitx5 框架层 ──────────────────────────────┐
│  • 激活态 (Active=2)   ──> 挂载 Rime 拼音引擎             │
│  • 休眠态 (Inactive=1) ──> 挂载 美式键盘 (keyboard-us)    │
│  • 切换物理热键：Ctrl + Space                             │
└───┬────────────────────────────────────────────────────────┘
    │ 当外层处于 Active 时，按键才送入内层
    ▼
┌── 内层状态机：Rime 引擎层 ────────────────────────────────┐
│  • 中文模式 (拼音候选)                                     │
│  • 英文模式 (ASCII 西文，直接上屏)                         │
│  • 切换物理热键：Shift                                     │
└────────────────────────────────────────────────────────────┘
```

#### 崩溃死锁链条四步曲：
1. **进程隔离记忆导致孤岛（`ShareInputState=Program`）**：
   旧配置下，每个程序独立记录状态。当从锁屏、浮动窗口（如 sshs-floating、文件选择框）切换回 CodeBuddy 时，Wayland 合成器触发了一次 `text_input.disable`。CodeBuddy 在 Fcitx5 内部直接跌入了 **`Inactive (1)` 休眠态**。
2. **列表残留 `keyboard-us` 导致 Shift 暴毙**：
   在 Fcitx5 的输入法列表中，若同时存在 `keyboard-us` 与 `rime`，一旦外层休眠，系统就自动切入纯美式键盘。**内层的 Rime 根本没有运行**！用户狂按 `Shift`，在纯美式键盘上按 Shift 只是上档键，根本无法翻转拼音。
3. **Monaco 吞没 `Ctrl + Space` 绞断救生索**：
   用户试图按唤醒热键 `Ctrl + Space`。但在 VS Code / CodeBuddy (Monaco) 默认快捷键中，`Ctrl + Space` 被硬编码绑定为核心功能：**`editor.action.triggerSuggest`（代码补全）**！
   Monaco 在前端 DOM 事件捕获阶段直接调用 `e.preventDefault()` 吞没了按键，**物理按键信号根本没有传给 Wayland 合成器与 Fcitx5**！
4. **不可逆死锁**：
   处于 Inactive -> 按 `Shift` 没用（Rime 没加载）-> 按 `Ctrl + Space` 没用（被 CodeBuddy 吞了）-> 用户被永久锁死在纯英文状态。

---

### 3. `Ctrl + Alt + P` 动态热键与 Capability 协议握手原理

为什么此前排查过程中，`Ctrl + Alt + P` 动态切换行内/浮窗预编辑有时会突然失效？

* **根因 A（能力标志位剥离）**：若在 `~/.config/fcitx5/config` 中配置了 `PreeditEnabledByDefault=False`，Fcitx5 在客户端创建输入上下文（InputContext）握手时，会直接从能力掩码中剥离预编辑位 `CapabilityFlag::Preedit = 0x2`（掩码从 `0x100000072` 降为 `0x80060`）。客户端据此判定输入法不支持任何应用内预编辑，后续无论怎么按 `TogglePreedit`，客户端都不会响应嵌入渲染。
* **根因 B（事件直通抢先）**：若在 `~/.config/fcitx5/conf/waylandim.conf` 中开启了 `PreferKeyEvent=True`，键盘事件优先以原始按键透传给应用，导致 `Ctrl + Alt + P` 被当作编辑器快捷键处理，Fcitx5 的全局热键过滤器根本无法截获。

---

## 三、彻底根治与全场景调优落地（共 6 步）

遵循第一性原理的重构推导：**既然 Rime 本身内部就拥有完善的英文（ASCII）模式与应用白名单策略，必须彻底消灭外层的 Inactive 休眠态与多余的 `keyboard-us`，重构为现代操作系统的“单引擎常驻模式”！**

```
【重构后的现代化单引擎架构】
系统所有文本输入 ──> 100% 永久由 Rime 引擎接管 (消除 Inactive 概念)
                        │
                        ├── 打拼音 ──> 输汉字
                        └── 按 Shift ──> 纯英文 (ASCII 模式，0 延迟直通，等同美式键盘)
```

---

### 步骤 1：物理根除休眠备选项，只保留唯一引擎 `rime`

编辑 `~/.config/fcitx5/profile`，清空 `keyboard-us`，仅保留 `rime` 作为第 0 项：

```ini
# ~/.config/fcitx5/profile
[Groups/0]
Name=Default
Default Layout=us
DefaultIM=rime

[Groups/0/Items/0]
Name=rime

[GroupOrder]
0=Default
```

* **收益**：Fcitx5 没有任何美式键盘备选项可以跌落，系统无论开机还是切窗口，100% 永久运行 Rime。

---

### 步骤 2：消灭程序状态孤岛，启用全局统一共享

编辑 `~/.config/fcitx5/config`：

```ini
# ~/.config/fcitx5/config
[Hotkey/TriggerKeys]
0=Control+space

[Hotkey/TogglePreedit]
0=Control+Alt+P

[Behavior]
# 全局统一共享输入状态，彻底消灭程序状态孤岛
ShareInputState=All
# 保持默认启用预编辑能力以支持动态热键切换
# PreeditEnabledByDefault=True
```

* **收益**：全系统桌面状态绝对一致。只要当前是中文输入状态，切到 CodeBuddy、Antigravity、Chromium 或终端均保持统一；按一次 `Shift` 切英文也是全局同步生效。

---

### 步骤 3：解除 CodeBuddy 对 `Ctrl + Space` 的抢键劫持

在 CodeBuddy 的用户按键配置文件 `~/.config/CodeBuddy CN/User/keybindings.json` 中注销该按键的内部绑定：

```json
// ~/.config/CodeBuddy CN/User/keybindings.json
[
    {
        "key": "ctrl+space",
        "command": "-editor.action.triggerSuggest"
    },
    {
        "key": "ctrl+space",
        "command": "-toggleSuggestionDetails"
    }
]
```

* **收益**：前缀 `-` 代表解绑。CodeBuddy 绝不再吞没 `Ctrl + Space`，物理按键直接穿透到 Fcitx5。（注：代码补全在敲代码时本就会自动弹出，亦可随时使用 `Ctrl + I` 主动呼出）。

---

### 步骤 4：移除干扰热键拦截的 `waylandim.conf`

确保删除或归档 `~/.config/fcitx5/conf/waylandim.conf`：

```bash
# 若存在则移走归档，防止 PreferKeyEvent=True 导致全局热键被应用抢先透传
[ -f ~/.config/fcitx5/conf/waylandim.conf ] && mv ~/.config/fcitx5/conf/waylandim.conf ~/.config/fcitx5/conf/waylandim.conf.bak
```

---

### 步骤 5：经典 UI 12pt 字号与纯黑高亮候选词定制

#### 1. 创建高对比度黑色高亮主题
在用户主题目录下创建 `~/.local/share/fcitx5/themes/black-highlight/theme.conf`：

```ini
# ~/.local/share/fcitx5/themes/black-highlight/theme.conf
[Metadata]
Name=Black Highlight
Version=1
Author=Omarchy
Description=Default theme with black highlight background
ScaleWithDPI=True

[InputPanel]
NormalColor=#000000
HighlightColor=#ffffff
PageButtonAlignment=Last Candidate

[InputPanel/TextMargin]
Left=5
Right=5
Top=5
Bottom=5

[InputPanel/ContentMargin]
Left=2
Right=2
Top=2
Bottom=2

[InputPanel/Background]
Color=#ffffff
BorderColor=#c0c0c0
BorderWidth=2

[InputPanel/Background/Margin]
Left=2
Right=2
Top=2
Bottom=2

# 关键：将候选词高亮背景调整为纯黑 #000000，文字保持纯白 #ffffff
[InputPanel/Highlight]
Color=#000000

[InputPanel/Highlight/Margin]
Left=5
Right=5
Top=5
Bottom=5

[Menu/Highlight]
Color=#000000

[Menu/Highlight/Margin]
Left=5
Right=5
Top=5
Bottom=5
```

并复制默认主题的 SVG 图标组件：
```bash
cp /usr/share/fcitx5/themes/default/*.svg ~/.local/share/fcitx5/themes/black-highlight/
```

#### 2. 配置 ClassicUI 样式与字号
编辑 `~/.config/fcitx5/conf/classicui.conf`：

```ini
# ~/.config/fcitx5/conf/classicui.conf
Vertical Candidate List=False
PerScreenDPI=True
# 输入与候选词字体（12pt）
Font="Sans 12"
MenuFont="Sans 12"
TrayFont="Sans Bold 10"
# 应用纯黑高亮主题
Theme=black-highlight
```

---

### 步骤 6：Rime 智能化全自动英文策略与服务热重载

#### 1. Shift 单击松开切换中英文
在 `~/.local/share/fcitx5/rime/default.custom.yaml` 中配置原生修饰键状态机：
```yaml
patch:
  # 单按松开才切换中英，长按组合键绝不误切
  "ascii_composer/switch_key/Shift_L": commit_code
  "ascii_composer/switch_key/Shift_R": commit_code
```

#### 2. 终端与密码框自动英文白名单
在 `~/.local/share/fcitx5/rime/fcitx5.yaml` 中维护专属规则：
```yaml
config_version: "0.22"

app_options:
  foot:
    ascii_mode: true
  footclient:
    ascii_mode: true
  sshs-floating:
    ascii_mode: true
  alacritty:
    ascii_mode: true
  kitty:
    ascii_mode: true
  quickshell:
    ascii_mode: true
  1Password:
    ascii_mode: true
  keepassxc:
    ascii_mode: true
```

#### 3. 平滑热重载 Fcitx5 守护进程
```bash
# 清理可能存在的瞬态 DBus 冲突单元并平滑重启服务
systemctl --user stop "dbus-*org.fcitx.Fcitx5*" 2>/dev/null
systemctl --user restart omarchy-fcitx5.service
```

---

## 四、针对 CodeBuddy 的最优工作流建议

对于日常在 CodeBuddy (Monaco) 中的高频编码：
* **首选工作流（物理免疫）**：在 CodeBuddy 窗口中，按下 **`Ctrl + Alt + P`** 切换为**浮窗预编辑模式**。拼音直接留在 Fcitx5 的黑底候选框内，Monaco 虚拟缓冲区保持 100% 静止，**退格跳行首、回车空格误删及 AI 抢键 100% 彻底绝迹**！而在 Chromium 等常规应用中，保持行内预编辑即可。
* **次选方案（IDE 内部防御）**：若仍希望在 CodeBuddy 中使用行内拼音，可将以下两项填入 CodeBuddy 的 `settings.json`：
  ```json
  {
    "editor.acceptSuggestionOnEnter": "off",
    "editor.quickSuggestions": {
      "other": "off",
      "comments": "off",
      "strings": "off"
    }
  }
  ```

---

## 五、全场景测试验证清单

| 测试项目 | 测试动作 | 预期标准结果 |
| :--- | :--- | :--- |
| **1. 连续退格压测** | 在 CodeBuddy / Chromium 中输入长拼音 `ceshishurufa`，长按 Backspace 删到最后一个字母 `c` 并彻底删空。 | **100% 停留在原位**，光标绝对不跳跃到前序代码或行首。 |
| **2. 回车与空格压测** | 正常输入词组，分别用 `空格`（选词）和 `回车`（英文编码直接上屏）。 | **绝对不误吞光标前后的已有文字**，击键丝滑无卡顿。 |
| **3. CodeBuddy 焦点切换免激活测试** | 系统开机或从终端/锁屏切回 CodeBuddy，直接敲拼音打字。 | **开箱即用，直接输出拼音候选**，无需按 `Ctrl + Space` 手动激活。 |
| **4. Shift 纯英文直通测试** | 在任意窗口按一下 `Shift`，敲击英文字符；再按一下 `Shift` 敲拼音。 | 英文输入 0 延迟原生直通；再次按下无缝恢复中文拼音。 |
| **5. 视觉与字号测试** | 敲击拼音呼出候选框。 | 字体为清晰舒适的 **12pt**，选中的第 1 候选词底色为醒目的**纯黑色**方块，文字为**纯白**，对比度极佳。 |
| **6. 预编辑动态热键验证** | 在输入框中按下 `Ctrl + Alt + P`。 | 即时在“行内嵌入预编辑（紧贴光标）”与“浮窗预编辑（无卡顿无跳行首）”之间无缝切换。 |

---

## 六、关键命令与调试速查

```bash
# 1. 查看当前 Fcitx5 激活状态 (输出 2 表示 Active 活跃, rime 表示引擎就绪)
fcitx5-remote && fcitx5-remote -n

# 2. 打印当前底层 Wayland 输入上下文 (检查 IC capability 掩码与 focus 状态)
dbus-send --session --dest=org.fcitx.Fcitx5 --type=method_call --print-reply /controller org.fcitx.Fcitx.Controller1.DebugInfo

# 3. 检查 Rime 是否处于纯英文 ASCII 模式 (false 表示拼音模式)
gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.IsAsciiMode

# 4. 重载 Fcitx5 配置文件
fcitx5-remote -r

# 5. 检查与重启用户级服务
systemctl --user status omarchy-fcitx5.service
systemctl --user restart omarchy-fcitx5.service
```

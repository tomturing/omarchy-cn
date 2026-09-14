# Omarchy 离线语音输入识别配置指南（Voxtype 与 Whisper 普通话模型、RTX 显卡 GPU 加速及剪贴板直通）

> **适用环境**：Omarchy (Arch Linux + Hyprland on Wayland)  
> **面向用户**：追求高频文字与代码极速输入、注重隐私与代码安全（禁止音频上云）的开发者及文字工作者  
> **核心收益**：掌握 100% 纯本地离线 Whisper 语音识别方案；彻底攻克蓝牙耳机“按赞订阅转发”幻觉陷阱；攻克 Wayland 下虚拟按键被输入法拦截导致不打字的痛点；借助 RTX 显卡实现从 6 秒延迟到 1 秒以内的闪电转写。

---

## 一、背景与核心痛点

语音打字是解放双手、成倍提升构思与代码书写效率的高效交互方式。然而，在 Linux (Wayland) 桌面环境下使用语音识别往往是一段充满挫折的“排坑血泪史”：

1. **隐私泄露风险**：市面上常见的语音输入法（如搜狗、讯飞、百度）依赖将实时麦克风音频上传至公网云端服务器，这在编写商业机密代码、处理敏感配置文件或企业日常办公时存在严重的合规隐患；
2. **“按赞、订阅、转发”离奇幻觉**：说话测试时，输入框总是莫名其妙蹦出“请按赞、订阅、转发、打赏”等视频片尾废话，或者反复提示识别失败；
3. **识别成功却打不进输入框**：查看后台日志明明已经将中文识别了出来，但在 Antigravity、IDE、终端或浏览器中，光标闪烁处却空空如也，一个汉字都没有敲出来；
4. **推理速度奇慢**：说完一段话要等 5~7 秒才能蹦出文字，严重破坏思考连贯性。

本文基于开源离线语音转文字套件 **Voxtype** 与 OpenAI **Whisper** 神经网络模型，深度解析三大技术陷阱，并针对现代 NVIDIA RTX 独立显卡进行全链路调优，打造毫秒级响应的纯离线普通话语音生产力工具。

---

## 二、架构设计与工作流

```mermaid
graph LR
    A["用户按住 F9 说话<br>(Push-to-Talk)"] --> B[PipeWire/PulseAudio 物理拾音]
    B --> C["Voxtype 守护进程<br>(voxtype-vulkan)"]
    C -->|加载 ggml-small.bin| D["RTX 2060 独立显卡<br>(Vulkan 并行计算 + Flash Attention)"]
    D -->|注入编程引导词| E[Whisper 神经网络声学/语言模型]
    E -->|生成简体中文文本| F["剪贴板直通引擎<br>(mode = 'paste' / wl-copy)"]
    F -->|触发 Ctrl+V 瞬间上屏| G[Antigravity / 终端 / 浏览器 / 微信]
```

### 核心特性
* **100% 纯本地离线**：断开网络依然完全可用，音频与文字从始至终保存在本地，绝无第三方服务器收集；
* **极简 Push-to-Talk 交互**：
  * **日常首选**：按住键盘 <kbd>F9</kbd> 说话，松开按键瞬间文字自动粘贴上屏；
  * **长篇听写**：按一次 <kbd>Ctrl + Super + X</kbd> 开启连续录音，说完再按一次结束。

---

## 三、三大隐蔽底层深坑与终极排坑实录（极其宝贵经验）

### 深坑一：蓝牙耳机延迟导致录入 0.6 秒静音与 Whisper 幻觉（“请按赞、订阅、转发”）

#### 1. 现象复现
用户戴着蓝牙耳机，按住 F9 说出：“*测试一下中文普通话语音输入，编写一个冒泡排序函数。*”  
屏幕上却赫然输出：“*请按赞 订阅 转发 打赏 打赏*”。

#### 2. 底层根因深度剖析
1. **Linux 蓝牙耳机的双模式切换冲突**：
   * **A2DP 模式（高级音频分发）**：用于高质量听歌，**此时耳机的物理麦克风处于断电待机状态**；
   * **HFP/HSP 模式（通话模式）**：麦克风通电收音，但音质降为通话级。
2. 系统的音频调度器（PipeWire/WirePlumber）默认策略是：*“平时听歌保持 A2DP，检测到录音请求时临时切换到 HFP 通话，录音结束切回”*。
3. **致命的 2 秒蓝牙射频握手延迟**：
   * 当用户按下 F9 说话时，耳机蓝牙芯片才刚刚开始发起从 A2DP 切换到 HFP 的射频重协商；
   * 整个重连过程需要 **1.5 ~ 2.5 秒**！
   * 当耳机真正连接通电时，用户其实已经把话说完了；系统实际捕获到的是一段 **0.6 秒的绝对静音空白音频**；
   * **Whisper 解码器的先天幻觉缺陷**：Whisper 在受到 YouTube 视频海量无声/静音片段训练时，将很多片尾背景静音强行关联到了“*请按赞、订阅、转发*”的字幕文本。只要录入的是空白音频，解码器概率最高的输出就是这句废话！

#### 3. 终极根治方案
1. **锁定通话/拾音模式，杜绝频繁断电握手**：
   使用 `pactl` 将蓝牙耳机锁定在常驻在线模式（`headset-head-unit`），麦克风时刻保持通电就绪，按下按键 **0 毫秒瞬间收音**；
2. **拉高麦克风拾音增益**：
   将录音输入增益提升至 **150%**，确保即使日常轻声细语也能被清晰捕获：
   ```bash
   pactl set-source-volume @DEFAULT_SOURCE@ 150%
   ```

---

### 深坑二：Wayland 键盘模拟输入在 Electron / Fcitx5 窗口全面丢字

#### 1. 现象复现
后台日志明确记录：`Whisper finished transcribing: "测试中文输入"`，但 Antigravity 或浏览器输入框就是没有任何文字输入。

#### 2. 底层根因剖析
* Voxtype 默认使用的是 `mode = "type"`（通过 `wtype` 或 `ydotool` 模拟物理逐字敲击键盘）。
* 但在 **Wayland + Hyprland** 体系下，Antigravity（基于 Electron）、Chromium 以及开启了 Fcitx5 输入法框架的窗口，其文本输入协议（`zwp_text_input_v3`）会判定模拟按键为非法未授权输入，或者将其直接作为按键事件吃掉，导致字符被全部丢弃。

#### 3. 终极根治方案：剪贴板瞬时直通模式（`mode = "paste"`）
在 `~/.config/voxtype/config.toml` 中将输出模式修改为：
```toml
[output]
mode = "paste"
fallback_to_clipboard = true
type_delay_ms = 1
```
* **原理**：Voxtype 转写出中文后，瞬间将文字写入系统剪贴板（`wl-copy`），并立刻发送一个合成的 <kbd>Ctrl + V</kbd>（或在终端发送 <kbd>Ctrl + Shift + V</kbd>）。
* **收益**：绕过所有 Wayland 输入法协议与按键拦截，**在任何复杂的应用窗口中实现 100% 成功打字上屏**。

---

### 深坑三：CPU 单核推理卡顿（6 秒）与 6GB 显存冲突平衡（RTX 2060 实战）

#### 1. 痛点：CPU 单核计算延迟过高
默认编译的 `voxtype` 纯跑在 CPU 上，推理 10 秒的音频需要消耗近 **6 秒**，无法满足实时打字要求。

#### 2. 核心突破：启用 Vulkan 硬件 GPU 加速
将后台服务切换为专为 GPU 并行计算编译的 **`voxtype-vulkan`** 核心。

#### 3. 6GB 显存设备的模型黄金平衡点（为什么选 `small`？）
很多用户盲目追求最大的 `large-v3`（需 2.5GB 显存）或 `large-v3-turbo`（需 1.8GB 显存）。然而在一台配备 **NVIDIA RTX 2060（6GB 显存）** 的现代开发机上：
* 开发者常常在后台跑本地大语言模型（如 `llama-server` 承载 Qwen2.5-Coder，常驻占用约 3.4GB 显存）；
* 若此时语音输入法硬塞入一个 2GB 模型，瞬间引发 CUDA Out of Memory (OOM) 导致系统界面假死或大模型崩溃；
* **实测最佳黄金平衡点：`ggml-small.bin`（约 487 MB）**：
  * 显存占用仅仅 **~487MB**，与本地大模型和谐共存；
  * 普通话识别准确率与 `base` 相比呈断崖式提升，同音字与编程词汇辨识度极高；
  * 配合 RTX 2060 Vulkan 核心与 **`flash_attention = true`**，10 秒音频推理时间被压缩至 **0.8 ~ 1.2 秒**，真正做到“松开按键，文字秒出”！

---

## 四、完整配置落地指南

### 1. 配置文件：`~/.config/voxtype/config.toml`

创建并写入以下调优参数：

```toml
# Voxtype Configuration
# 路径：~/.config/voxtype/config.toml

state_file = "auto"
engine = "whisper"

[hotkey]
# 快捷键交由 Hyprland 全局托管，此处禁用内置监听
enabled = false

[audio]
device = "pulse"
sample_rate = 16000
max_duration_secs = 60
pause_media = true

[whisper]
# 使用 small 模型 (487MB)，显存安全、准确度高
model = "small"
language = "zh"
translate = false
mode = "local"
flash_attention = true
on_demand_loading = false
gpu_isolation = false
# 注入普通话与开发提示词，避免同音字与英文缩写误判
initial_prompt = "这是一段中文普通话日常对话与编程开发指令，请正确使用简体中文和标点符号。"

[output]
# 必须使用剪贴板瞬时直通模式
mode = "paste"
fallback_to_clipboard = true
type_delay_ms = 1

[output.notification]
on_recording_start = false
on_recording_stop = false
on_transcription = false
```

---

### 2. 下载 Whisper Small 普通话离线模型

创建模型目录并拉取官方预编译权重文件（约 487MB）：

```bash
mkdir -p ~/.local/share/voxtype/models

# 从官方或高速镜像下载 ggml-small.bin
curl -L -o ~/.local/share/voxtype/models/ggml-small.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
```

---

### 3. 配置 systemd 用户级守护进程（自动启用 Vulkan GPU 核心）

创建 `~/.config/systemd/user/voxtype.service`：

```ini
[Unit]
Description=Voxtype push-to-talk voice-to-text daemon
Documentation=https://voxtype.io
After=pipewire.service sound.target

[Service]
Type=simple
# 核心：使用 voxtype-vulkan 启用 NVIDIA GPU 硬件加速
ExecStart=/usr/lib/voxtype/voxtype-vulkan daemon
Restart=on-failure
RestartSec=2
Environment=XDG_CURRENT_DESKTOP=Hyprland

[Install]
WantedBy=default.target
```

重载并启动服务：
```bash
systemctl --user daemon-reload
systemctl --user enable --now voxtype.service
```

---

### 4. 在 Hyprland 中声明系统级快捷键

Omarchy 在 `/usr/share/omarchy/default/hypr/bindings/voxtype.lua` 中已内建规范声明：

```lua
if o.cmd_present("voxtype") then
  -- 免按住模式：单击开始，再次单击结束
  o.bind("SUPER + CTRL + X", "Toggle dictation", "voxtype record toggle")
  -- Push-to-Talk 模式：按住 F9 说话，松手结束
  o.bind("F9", "Start dictation (push-to-talk)", "voxtype record start")
  o.bind("F9", "Stop dictation (push-to-talk)", "voxtype record stop", { release = true })
end
```

如未生效，确保 `hyprctl reload` 重载了配置。

---

## 五、端到端实测验证步骤

1. **服务与 GPU 载入验证**：
   ```bash
   systemctl --user status voxtype.service
   ```
   检查日志输出，必须包含类似字段：
   ```text
   voxtype-vulkan: whisper_model_load: Vulkan0 total size = 487.01 MB
   voxtype-vulkan: Model loaded in 0.60s, ready for voice input
   ```
2. **日常打字实测**：
   * 将光标定位在 Antigravity 聊天窗口、终端命令行或浏览器搜索框；
   * **按住键盘 <kbd>F9</kbd> 不放**，清楚说出一句中文：*“测试一下中文普通话语音输入，编写一个冒泡排序函数。”*；
   * **松开 <kbd>F9</kbd>**；
   * 观察转写文字是否在 **1 秒内**瞬间完整打入输入框，且标点符号和汉字均正确无误。

---

## 六、关键命令与状态排查速查表

| 操作目的 | 命令 / 方法 | 预期结果 |
| :--- | :--- | :--- |
| **检查语音服务运行状态** | `systemctl --user status voxtype` | 显示 `active (running)` 且进程为 `voxtype-vulkan` |
| **实时查看转录日志** | `journalctl --user -u voxtype -f` | 实时输出音频长度、识别耗时及生成的文本 |
| **检查 GPU 显存占用** | `nvidia-smi` | `voxtype-vulkan` 占用约 480MB~500MB 显存 |
| **测试麦克风硬件录音** | `arecord -d 3 -f S16_LE -r 16000 test.wav && aplay test.wav` | 能清晰回放自己刚才说的话，无静音或杂音 |
| **手动测试单次转写** | `voxtype record toggle` | 手动触发录音与转录全流程 |

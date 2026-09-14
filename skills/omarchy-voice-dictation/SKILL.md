---
name: omarchy-voice-dictation
description: Configure, diagnose, and optimize offline speech-to-text voice dictation (Voxtype + Whisper Mandarin model), RTX GPU Vulkan hardware acceleration, Bluetooth headset latency/hallucination fixes, and Wayland synthetic paste injection on Omarchy (Arch Linux + Hyprland). Use when the user asks about voice input recognition, Whisper models, audio silence hallucination ("请按赞、订阅、转发"), dropped characters during dictation, or setting up Super+Ctrl+X / F9 push-to-talk dictation.
---

# Omarchy Offline Voice Dictation (Voxtype + Whisper GPU) Skill

This skill provides an automated, standardized procedure for configuring, optimizing, and troubleshooting **100% offline speech-to-text dictation** using **Voxtype** and **Whisper** on **Omarchy (Arch Linux + Hyprland on Wayland)** with NVIDIA RTX GPU hardware acceleration.

---

## 1. When to Use This Skill

Activate this skill whenever a user on Omarchy / Arch Linux:
* **Wants offline voice-to-text dictation**: Configuring a completely private, zero-latency, offline voice input tool that works in all Wayland windows (terminals, browsers, editors).
* **Experiences silence hallucination ("请按赞、订阅、转发")**: Voxtype repeatedly outputs YouTube subtitle training artifacts like "请按赞、订阅、转发" or "欢迎收看" when silence or low volume is recorded.
* **Experiences dropped characters or garbled input**: Characters getting dropped, eaten, or blocked when dictating into Antigravity, VSCode, Chromium, or terminal windows.
* **Suffers high latency (>5s) on CPU**: Transcribing speech on CPU is slow; requires activating `voxtype-vulkan` on NVIDIA RTX GPUs for sub-second recognition.
* **Needs VRAM balancing with local LLMs**: Balancing Whisper VRAM footprint (~466MB `small` model) with local LLMs (`llama-server`, Ollama) on a 6GB/8GB GPU without OOM crashes.
* **Wants to setup global push-to-talk hotkeys**: Binding `Super + Ctrl + X` (toggle dictation) or `F9` (push-to-talk) in Hyprland.

---

## 2. Quick Environment Diagnostic

Always run the bundled diagnostic script to check the current system state:

```bash
bash <skill_dir>/scripts/check_voxtype.sh
```

### Diagnostic Checklist:
| Check Item | Target Expected State | Failure Root Cause |
| :--- | :--- | :--- |
| **`voxtype-vulkan`** | Installed (`/usr/lib/voxtype/voxtype-vulkan`) | `voxtype-bin` not installed from AUR. |
| **Whisper Model** | `~/.local/share/voxtype/models/ggml-small.bin` | Model file missing or corrupted. |
| **Config Parameters** | `model="small"`, `language="zh"`, `mode="paste"` | Missing Mandarin prompt, wrong output mode. |
| **systemd Unit** | Uses `/usr/lib/voxtype/voxtype-vulkan daemon` | Default system unit points to CPU binary. |
| **Daemon Active** | `voxtype.service` running | Service stopped or failed to launch. |
| **GPU Acceleration** | Log contains `Vulkan ... MB` | Falling back to AVX2/CPU compute. |
| **Global Bindings** | `SUPER + CTRL + X` and `F9` in Hyprland | Hotkeys unbound or overridden. |

---

## 3. Core Tuning Recipes

### Recipe 1: One-Click Automated Deployment

Run the automated setup script to deploy `voxtype-vulkan`, download `ggml-small.bin`, set `mode = "paste"`, and configure the user systemd service:

```bash
bash <skill_dir>/scripts/setup_voxtype.sh
```

---

### Recipe 2: Fix Bluetooth Headset Silence Hallucination

#### Root Cause:
When using Bluetooth headphones (Sony WH-1000XM4, AirPods, etc.), the device defaults to the high-quality **A2DP Sink** profile. Switching to **HFP/HSP** (hands-free mic) takes **1.5s to 2.5s**. When the user presses the hotkey and speaks immediately, the microphone records pure silence. Whisper models, when fed with silence, hallucinate frequent training set subtitles:
> "请按赞、订阅、转发" / "Thank you for watching" / "欢迎收看"

#### Fixes:
1. **Lock Bluetooth Profile to `headset-head-unit`** during dictation sessions:
   ```bash
   # Query card name
   pactl list cards short
   # Set to HFP/HSP headset profile
   pactl set-card-profile bluez_card.XX_XX_XX_XX_XX_XX headset-head-unit
   ```
2. **Increase Input Volume to 150%**:
   Ensure input level exceeds Whisper's silence threshold:
   ```bash
   pactl set-source-volume @DEFAULT_SOURCE@ 150%
   ```
3. **Inject Contextual Initial Prompt**:
   In `~/.config/voxtype/config.toml`, configure:
   ```toml
   [whisper]
   initial_prompt = "这是一段中文普通话日常对话与编程开发指令，请正确使用简体中文和标点符号。"
   ```

---

### Recipe 3: Fix Dropped Characters via Clipboard Injection (`mode = "paste"`)

#### Root Cause:
By default, `mode = "type"` relies on `ydotool` to inject synthetic virtual key events character-by-character. Under Wayland:
* Fcitx5 intercepts virtual keys and tries to interpret them as Pinyin input, causing garbled characters.
* Electron (Antigravity/VS Code) and Chromium drop keystrokes if typing rate exceeds event loop thresholds.

#### Solution:
Change output mode to `paste` in `~/.config/voxtype/config.toml`:
```toml
[output]
mode = "paste"
fallback_to_clipboard = true
type_delay_ms = 1
```
In `paste` mode, Voxtype puts the recognized Chinese text directly into the Wayland clipboard via `wl-copy` and triggers a single synthetic `Ctrl + V`. Zero dropped characters, instant insertion.

---

### Recipe 4: RTX 2060 6GB VRAM Balancing with Local LLMs

#### Model Selection Matrix:
| Model | VRAM Usage | Latency (RTX 2060 Vulkan) | Recognition Quality | Coexistence with LLM (3.4GB VRAM) |
| :--- | :--- | :--- | :--- | :--- |
| **base** | ~142 MB | ~250 ms | High error rate on homophones | Seamless |
| **small (Recommended)** | **~466 MB** | **~850 ms** | **Superior Mandarin accuracy** | **Safe (<1GB VRAM, No OOM)** |
| **medium** | ~1.5 GB | ~2.5 s | Marginal improvement over small | Risk of VRAM contention |
| **large-v3** | ~3.1 GB | ~4.5 s | Heavyweight | Will trigger CUDA OOM with LLM |

#### Vulkan Acceleration Configuration:
In `~/.config/systemd/user/voxtype.service`:
```ini
[Unit]
Description=Voxtype push-to-talk voice-to-text daemon
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/lib/voxtype/voxtype-vulkan daemon
Restart=on-failure
RestartSec=5
Environment=XDG_RUNTIME_DIR=%t

[Install]
WantedBy=graphical-session.target
```

---

## 4. Global Hotkeys Usage Guide

In Omarchy, the following global hotkeys are enabled by default:
* **`Super + Ctrl + X`**: **Toggle Dictation**. Press once to start listening, speak naturally, press again to stop and automatically transcribe & paste.
* **`F9`**: **Push-to-Talk (对讲机模式)**. Hold down `F9` while speaking, release `F9` when done to transcribe and paste.

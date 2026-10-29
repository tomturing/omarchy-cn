---
name: omarchy-electron-wayland-ime
description: Diagnose, harden, and optimize Chinese IME (Fcitx5) on Electron-based IDEs and AI desktop clients (Qoder, CodeBuddy, WorkBuddy, VS Code, Trae, Cursor) under Omarchy (Arch Linux + Hyprland on Wayland). Use when users report Chinese pinyin inline preedit issues such as backspace deletion jumping to line start, unresponsiveness on first backspace, candidate box drift, blurry XWayland scaling, or Vulkan GPU crashes in Electron apps.
---

# Omarchy Electron Wayland IME Hardening & Backspace Jump Remediation Skill

This skill provides an automated and standardized procedure for diagnosing, configuring, and permanently curing Chinese IME (Fcitx5 / Rime) anomalies—especially the notorious **"Backspace jumping to line start when deleting pinyin to empty preedit"** bug—across all Electron-based AI clients and IDEs on **Omarchy (Arch Linux running Hyprland on Wayland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following issues inside an Electron application (e.g. **Qoder**, **CodeBuddy**, **WorkBuddy**, **VS Code**, **Trae**, **Cursor**) on Omarchy:
* **Backspace jumping to the beginning of the line**: Typing Chinese pinyin inline, pressing Backspace until the first letter, and pressing Backspace once more causes the cursor to instantly teleport to the very start of the line or code block (Column 0).
* **First backspace unresponsive**: Deleting the final pinyin character feels stuck on the first press, followed by an abrupt cursor jump on the second press.
* **Electron app falling back to XWayland**: The application runs under XWayland with blurry display scaling, missing crisp font rendering, or floating candidate box offset.
* **Vulkan crashes on startup**: Electron exits immediately with `'--ozone-platform=wayland' is not compatible with Vulkan`.
* **OS Keyring dialog popups**: Application nags for "Enter password to unlock default keyring" on every launch under Hyprland.

---

## 2. First Principles & Root Cause Breakdown

### The Physical Failure Chain (Chromium 138 text-input-v3 Bug)

```
[User presses Backspace on last pinyin letter]
                   │
                   ▼
       [Fcitx5 engine clears preedit]
                   │
                   ▼
  Wayland compositor sends: preedit_string("")
                   │
                   ▼
[Chromium 138 C++ Engine (ui/ozone/platform/wayland/host/wayland_input_method_context.cc)]
  ❌ Internal State Bug: Composition state is destroyed prematurely!
  ❌ Keydown is NOT consumed: C++ layer leaks raw physical KeyDown: Backspace
                   │
                   ▼
[Renderer DOM / Monaco Editor / RichText Area]
  ⚠️ Receives empty preedit AND unexpected hardware Backspace in the same tick.
  💥 Cursor selection calculation desyncs -> Triggers collapseToStart -> Jumps to Line Start!
```

### Why Native Electron 42 Grafting Fails on Proprietary Clients (Adversarial Review)
* **Qoder IDE**: Cleanly runs on system `/usr/lib/electron42/electron` (Chromium 140+) because it contains no private closed-source native C++ bindings; Chromium 140 upstream naturally fixed text-input-v3.
* **Tencent WorkBuddy / CodeBuddy**: Bundles proprietary native modules:
  * `better-sqlite3.node`
  * `@tencent/qimei-node` (closed-source device fingerprint / security auth)
  * These binaries are hard-locked to **Node ABI 136 (Electron 37)**. Launching them under Electron 42 (Node ABI 146) throws `NODE_MODULE_VERSION` fatal exceptions and crashes immediately.

### The True Resolution: Protocol Downgrade to `text-input-v1`
The hardware backspace leakage bug is **strictly isolated within Chromium's `text-input-v3` state machine implementation**. By supplying:
```ini
--wayland-text-input-version=1
```
Chromium switches to the `ZwpTextInputV1` protocol interface, completely bypassing the faulty v3 state machine while preserving 100% native Wayland inline preedit without any key leakage.

---

## 3. Quick Diagnostic Workflow

Run the diagnostic script to inspect installed Electron AI apps and their flag configurations:

```bash
bash <skill_dir>/scripts/diagnose_electron_ime.sh
```

### Diagnostic Checklist:
| Inspection Target | Target Expected Value | Defect if Misconfigured |
| :--- | :--- | :--- |
| `ozone-platform` | `wayland` | App falls back to blurry XWayland |
| `enable-wayland-ime` | Enabled | Fcitx5 fails to track cursor or type inline |
| `wayland-text-input-version` | `1` | **Triggers backspace jump to line start in Chromium 138** |
| `disable-features` | `Vulkan` | Prevents Wayland/Vulkan surface initialization crash |
| `use-gl` | `angle` | Ensures stable GPU compositing |
| `password-store` | `basic` | Prevents blocking keyring popups under Hyprland |

---

## 4. Automated Remediation Playbook

Execute the bundled remediation script to apply the complete configuration stack across all detected AI apps:

```bash
# Harden all detected Electron apps (WorkBuddy, CodeBuddy, Qoder)
bash <skill_dir>/scripts/fix_electron_ime.sh all

# Or target a specific client
bash <skill_dir>/scripts/fix_electron_ime.sh workbuddy
bash <skill_dir>/scripts/fix_electron_ime.sh codebuddy
bash <skill_dir>/scripts/fix_electron_ime.sh qoder
```

### Standard Configuration Specifications

#### 1. Flags Configuration (`~/.config/<app>-flags.conf`)
```ini
# Omarchy Wayland & 中文输入法 (Fcitx5) 调优参数
--ozone-platform=wayland
--ozone-platform-hint=wayland
--enable-wayland-ime
# 核心防御: 强制使用 text-input-v1 协议，规避 Chromium 138 text-input-v3 下空预编辑退格穿透跳行首漏洞
--wayland-text-input-version=1
--enable-features=WaylandWindowDecorations
--use-gl=angle
--disable-features=Vulkan
--password-store=basic
```

#### 2. User-space Wrapper Script (`~/.local/bin/<app>`)
Ensure `~/.local/bin` takes precedence in `$PATH` and exports essential Fcitx5 environment variables:
```bash
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS="@im=fcitx"
export SDL_IM_MODULE=fcitx
```

#### 3. Permanent Runtime Arguments (`argv.json` for VS Code Family)
Sync to `~/.codebuddycn/argv.json` and `~/.config/CodeBuddy CN/argv.json`:
```json
{
	"password-store": "basic",
	"locale": "zh-cn",
	"enable-crash-reporter": false,
	"ozone-platform": "wayland",
	"enable-wayland-ime": true,
	"wayland-text-input-version": "1",
	"enable-features": "WaylandWindowDecorations",
	"disable-features": "Vulkan",
	"use-gl": "angle"
}
```

#### 4. Hyprland Window Rules (`~/.config/hypr/windowrules.lua`)
Ensure opaque rendering and correct class matching:
```lua
-- CodeBuddy CN / WorkBuddy / Qoder 窗口规则：移除默认透明度，保持完全不透明
o.window("(CodeBuddy CN|buddycn|codebuddy-ide-cn|[Ww]ork[Bb]uddy.*|qoder-cn-ide)", {
  tag = "-default-opacity",
  opacity = "1 1",
})
```

---

## 5. Verification Checklist

After applying fixes, verify client compliance:
1. **Wayland Native Check**:
   ```bash
   hyprctl clients | grep -E "class: (WorkBuddy|buddycn|qoder)" -A 10
   # Confirm "xwayland: 0"
   ```
2. **Backspace Inline Preedit Test**:
   * Type a Chinese pinyin sequence (e.g. `ceshi`).
   * Press `Backspace` until only the initial letter `c` remains.
   * Press `Backspace` once more to completely clear the preedit.
   * **Pass Criteria**: Cursor remains firmly at its current position; no unresponsive delay; cursor does NOT jump to column 0.

---
name: omarchy-desktop-tweaks
description: Configure, diagnose, and optimize desktop workflow shortcuts, F1 screenshot annotation (Tensaku integration), and Quickshell center real-time network speed display on Omarchy (Arch Linux + Hyprland). Use when the user asks about Hyprland shortcuts topology, unbinding conflicts, F1 screenshot with in-place annotation, or adding/fixing center widgets like network speed in the Omarchy Quickshell topbar.
---

# Omarchy Desktop Tweaks & System Display Skill

This skill provides an automated, standardized procedure for diagnosing, configuring, and optimizing desktop workflow shortcuts, **F1 screenshot annotation (Tensaku)**, and **Quickshell topbar center real-time network speed display** on **Omarchy (Arch Linux + Hyprland on Wayland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user on Omarchy / Arch Linux:
* **Asks for shortcut recommendations & Hyprland key configuration**: Inquiring about common, high-frequency productivity shortcuts (app launcher, scratchpad, lock screen, workspace navigation).
* **Encounters shortcut conflicts or double triggers**: New shortcuts triggering both default actions and user commands (due to missing `hl.unbind`).
* **Wants F1 one-key screenshot with modern annotation**: Replacing primitive grim/slurp/satty with WeChat/Snipaste-grade workflow (Space window snapping, rectangular/arrow/text annotation, mosaic/blur, S scroll capture, Enter auto-copy).
* **Wants topbar center real-time network speed display**: Adding upload/download speed indicators to Omarchy's Quickshell top bar without high CPU usage or UI stutter.
* **Experiences Quickshell layout breaks**: Disappearing widgets, duplicate widgets, or topbar layout parse errors after editing `~/.config/omarchy/shell.json`.

---

## 2. Quick Environment Diagnostic

Always run the bundled diagnostic script to check the current system state:

```bash
bash <skill_dir>/scripts/check_desktop_tweaks.sh
```

### Diagnostic Checklist:
| Check Item | Target Expected State | Failure Root Cause |
| :--- | :--- | :--- |
| **`tensaku` Binary** | Installed (`extra/tensaku`) | Not installed via pacman. |
| **Capture Wrapper** | `~/.local/bin/tensaku-capture` executable | Wrapper script missing or missing execution permissions. |
| **F1 Keybinding** | `hl.unbind("F1")` + `o.bind("F1", ...)` in `~/.config/hypr/local.lua` | Missing unbind causing default help/guide conflict or unassigned. |
| **App Shortcuts** | `SUPER + A` (IDE), `SUPER + B` (Browser) in `bindings.lua` | Application shortcut mappings not configured. |
| **Netspeed Plugin** | `~/.config/omarchy/plugins/local.netspeed/` complete | Missing `manifest.json`, `netspeed.sh`, or `NetSpeed.qml`. |
| **Lossless Streamer** | Output valid JSON with `up_str`/`down_str` | `/proc/net/dev` delta calculation failed or awk error. |
| **Quickshell Center** | `"local.netspeed"` in `shell.json` `sections.center` | Missing in topbar center configuration array. |

---

## 3. Core Tuning Recipes

### Recipe 1: Configure Common Shortcuts & F1 Tensaku Screenshot

Run the automated setup script to deploy the Tensaku wrapper and Hyprland bindings:

```bash
bash <skill_dir>/scripts/setup_shortcuts_and_f1.sh
```

#### Manual Verification & Key Rules:
1. **The Hyprland Lua Unbind Rule**:
   Always call `hl.unbind` before binding any key already used by system defaults:
   ```lua
   -- ~/.config/hypr/local.lua
   hl.unbind("F1")
   o.bind("F1", "exec", "~/.local/bin/tensaku-capture")

   hl.unbind("SUPER + SHIFT + Return")
   o.bind("SUPER + SHIFT + Return", "exec", "foot --app-id=sshs-floating sshs")
   ```

2. **Tensaku Capture Wrapper (`~/.local/bin/tensaku-capture`)**:
   Ensures auto-copying to clipboard and saving to `~/Pictures/Screenshots/` while playing shutter sound:
   ```bash
   #!/usr/bin/env bash
   set -euo pipefail
   SAVE_DIR="$HOME/Pictures/Screenshots"
   mkdir -p "$SAVE_DIR"
   FILENAME="Screenshot_$(date +'%Y%m%d_%H%M%S').png"
   TARGET_FILE="$SAVE_DIR/$FILENAME"

   tensaku --output "$TARGET_FILE" --clipboard
   ```

3. **Reload Hyprland Config**:
   ```bash
   hyprctl reload
   ```

---

### Recipe 2: Deploy Topbar Center Real-Time Network Speed Display

Run the automated setup script:

```bash
bash <skill_dir>/scripts/setup_topbar_netspeed.sh
```

#### Under the Hood Architecture:
1. **Non-blocking Streamer (`netspeed.sh`)**:
   Reads `/proc/net/dev` once per second, filters out docker/veth/lo/br bridges, and outputs continuous JSON stream (`{"up_str":"12.4 KB/s","down_str":"156.8 KB/s"}`).
2. **Quickshell QML Component (`NetSpeed.qml`)**:
   Uses `Process` to consume the stdout stream asynchronously. Zero CPU spikes, non-blocking UI thread.
   - Left click toggles between compact mode (`12K 156K`) and detailed mode (`↑ 12.4 KB/s ↓ 156.8 KB/s`).
   - Hovering displays full tooltip with network interface and transfer details.
3. **Quickshell Configuration Integration (`~/.config/omarchy/shell.json`)**:
   Adds `"local.netspeed"` into the `sections.center` array:
   ```json
   "sections": {
     "left": [ "system.launcher", "hyprland.workspaces" ],
     "center": [ "hyprland.windowtitle", "local.netspeed" ],
     "right": [ ... ]
   }
   ```
4. **Restart Quickshell**:
   ```bash
   omarchy-restart-shell
   ```

---

## 4. Troubleshooting & Edge Cases

* **F1 does not trigger screenshot**:
  Check if another process locked F1 or if `hl.unbind` was called. Test manually by running `~/.local/bin/tensaku-capture` in a terminal.
* **Tensaku window doesn't appear on screen**:
  Ensure Wayland compositing permissions are healthy and `grim`/`slurp` dependencies are present.
* **Topbar net speed shows `0.0 B/s` while downloading**:
  Check if physical network interface was excluded in `netspeed.sh`. Run `bash ~/.config/omarchy/plugins/local.netspeed/netspeed.sh` in terminal to inspect raw JSON output.
* **Quickshell topbar crashes or restarts continuously**:
  Inspect logs via `journalctl --user -u quickshell -b -n 50` or launch `quickshell` in terminal to see syntax errors in `NetSpeed.qml`.

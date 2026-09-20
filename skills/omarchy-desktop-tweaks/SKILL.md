---
name: omarchy-desktop-tweaks
description: Configure, diagnose, and optimize desktop workflow shortcuts, dedicated scratchpads (named special workspaces), F1 screenshot annotation (Tensaku integration), and Quickshell center real-time network speed display on Omarchy (Arch Linux + Hyprland). Use when the user asks about Hyprland shortcuts topology, dedicated app scratchpads, unbinding conflicts, F1 screenshot with in-place annotation, or adding/fixing center widgets like network speed in the Omarchy Quickshell topbar.
---

# Omarchy Desktop Tweaks & System Display Skill

This skill provides an automated, standardized procedure for diagnosing, configuring, and optimizing desktop workflow shortcuts, **F1 screenshot annotation (Tensaku)**, and **Quickshell topbar center real-time network speed display** on **Omarchy (Arch Linux + Hyprland on Wayland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user on Omarchy / Arch Linux:
* **Asks for shortcut recommendations & Hyprland key configuration**: Inquiring about common, high-frequency productivity shortcuts (app launcher, scratchpad, lock screen, workspace navigation).
* **Encounters shortcut conflicts or double triggers**: New shortcuts triggering both default actions and user commands (due to missing `hl.unbind`).
* **Wants F1 one-key screenshot with modern annotation**: Replacing primitive grim/slurp/satty with WeChat/Snipaste-grade workflow (Space window snapping, rectangular/arrow/text annotation, mosaic/blur, S scroll capture, Enter/copy auto-exit window without manual close).
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
| **Capture Wrapper** | `~/.local/bin/tensaku-capture` executable with `--early-exit` | Wrapper script missing, non-executable, or missing auto-exit flag. |
| **Tensaku Config** | `~/.config/tensaku/config.toml` contains `early-exit = true` | Tensaku window stays open after copy action. |
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
   Enables interactive capture, auto-saving to picture directory, copying to clipboard via `wl-copy`, and auto-closing the window immediately on copy/save (`--early-exit`):
   ```bash
   #!/bin/bash
   user_dirs="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
   [[ -f $user_dirs ]] && source "$user_dirs"
   dir="${OMARCHY_SCREENSHOT_DIR:-${XDG_PICTURES_DIR:-$HOME/Pictures}}"
   mkdir -p "$dir"

   exec tensaku --capture \
     --output-filename "$dir/tensaku-$(date +%Y-%m-%d_%H-%M-%S).png" \
     --actions-on-enter save-to-clipboard \
     --save-after-copy \
     --copy-command wl-copy \
     --early-exit \
     "$@"
   ```

3. **Tensaku Global Configuration (`~/.config/tensaku/config.toml`)**:
   Ensures auto-exit on copy across all entry points:
   ```toml
   [general]
   annotation-size-factor = 2.0
   early-exit = true
   ```

4. **Reload Hyprland Config**:
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

### Recipe 3: Deploy Standardized `restart-<target>` Recovery Commands

When the user encounters desktop freezes, `Super+Space` menu hangs, or clipboard pipe issues, deploy the standardized recovery commands into `~/.bashrc`:

```bash
cat << 'EOF' >> ~/.bashrc

# ==============================================================================
# 快捷恢复与重启命令规范: restart-<component>
# 规范说明: 统一采用 kebab-case (中划线)，输入 "restart-" + Tab 即可自动补全所有可用恢复命令
# ==============================================================================

# 1. 桌面 Shell / 菜单恢复 (针对 Omarchy 菜单、顶栏、Quickshell 死锁卡顿)
restart-shell() {
    echo "Restarting Quickshell / Omarchy shell..."
    killall -9 quickshell 2>/dev/null
    omarchy-restart-shell
}
alias restart-quickshell='restart-shell'
alias restartquickshell='restart-shell'
alias rshell='restart-shell'

# 2. 剪贴板管道重置 (针对跨机剪贴板假死/挂起)
restart-clip() {
    pkill -9 -f "capture.sh text" 2>/dev/null
    echo "Clipboard pipeline reset successfully."
}
alias restart-clipboard='restart-clip'
alias fix-clip='restart-clip'
EOF
```

---

### Recipe 4: Harden Multi-Monitor Custom Plugins Against Deadlocks & Orphan Leaks

In a dual-monitor setup (e.g. `eDP-1` and `HDMI-A-1`), Quickshell instantiates bar widgets once per screen. Custom plugins must follow these 3 strict rules:
1. **Singleton Daemon Locking**: Use `exec 200>"$LOCK_FILE"` and `flock -n 200 || exit 0` in background scripts so only 1 sampler runs globally;
2. **Orphan Prevention**: Start daemons with `setpriv --pdeathsig TERM` and check `kill -0 "$PPID"` in loops so scripts die when Quickshell exits;
3. **Decouple Via Memory File**: Write sampled JSON atomically to `$XDG_RUNTIME_DIR/xxx.json` (`tmpfs`), and let QML consume via `Quickshell.Io.FileView` instead of streaming high-frequency stdout into the Qt GUI main thread.

---

### Recipe 5: Dedicated App Scratchpads & Dual-Track Topology

To prevent multiple scratchpad apps from toggling together ("all-in-one bundle"), use Hyprland Named Special Workspaces:
1. **Install Helper**: Deploy `omarchy-toggle-scratchpad` to `~/.local/bin/` (`chmod +x`);
2. **Define Window Rules (`~/.config/hypr/windowrules.lua`)**:
   ```lua
   o.window("^antigravity$", { workspace = "special:antigravity silent", float = true, center = true, size = { 1400, 900 } })
   o.window("^(chrome-gemini.*|google-ai)$", { workspace = "special:gemini silent", float = true, center = true, size = { 1200, 850 } })
   o.window("^foot-scratchpad$", { workspace = "special:foot silent", float = true, center = true, size = { 1100, 700 } })
   ```
3. **Bind Dedicated Shortcuts (`~/.config/hypr/bindings.lua`)**:
   ```lua
   hl.unbind("SUPER + A")
   o.bind("SUPER + A", "Toggle Antigravity", "omarchy-toggle-scratchpad '^antigravity$' antigravity 'uwsm-app -- antigravity'")

   hl.unbind("SUPER + X")
   o.bind("SUPER + X", "Toggle Google AI", "omarchy-toggle-scratchpad '(chrome-gemini|google-ai)' gemini 'omarchy-launch-webapp https://gemini.google.com'")

   o.bind("SUPER + Z", "Toggle Foot Terminal", "omarchy-toggle-scratchpad foot-scratchpad foot 'uwsm-app -- foot --app-id=foot-scratchpad'")
   ```
4. **Preserve Defaults**: Leave default `SUPER + ALT + S` (Move to scratchpad) and `SUPER + S` (Toggle scratchpad) untouched to retain the universal scratchpad for arbitrary temporary windows.

---

## 4. Troubleshooting & Edge Cases

* **`Super + Space` Omarchy Menu Does Not Open / Hangs**:
  Run `omarchy menu ping`. If it returns `omarchy-shell is not responding`, Quickshell is locked in `futex_do_wait`. Run `restart-shell` in terminal to kill and cleanly respawn the shell in 1-2 seconds.
* **F1 does not trigger screenshot**:
  Check if another process locked F1 or if `hl.unbind` was called. Test manually by running `~/.local/bin/tensaku-capture` in a terminal.
* **Tensaku window doesn't appear on screen**:
  Ensure Wayland compositing permissions are healthy and `grim`/`slurp` dependencies are present.
* **Topbar net speed shows `0.0 B/s` while downloading**:
  Check if physical network interface was excluded in `netspeed.sh`. Run `cat $XDG_RUNTIME_DIR/omarchy-netspeed.json` to inspect live data.
* **Quickshell topbar crashes or restarts continuously**:
  Inspect logs via `journalctl --user -b -n 50 | grep -i quickshell` or launch `quickshell` in terminal to see syntax errors in QML components.


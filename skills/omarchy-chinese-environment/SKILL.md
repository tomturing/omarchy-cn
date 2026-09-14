---
name: omarchy-chinese-environment
description: Diagnose, configure, and optimize Chinese localization, Fcitx5, Rime input method, terminal defaults, and password input fields on Omarchy (Arch Linux + Hyprland). Use when user reports issues with Chinese input method switching, Shift key misfires, terminal defaulting to Chinese, password prompt candidate popups, CJK font fallback, or Chinese app compatibility on Omarchy.
---

# Omarchy Chinese Environment Tuning & Troubleshooting Skill

This skill provides an automated and standardized procedure for diagnosing, tuning, and troubleshooting Chinese localization, CJK fonts, and the Fcitx5 + Rime input method on **Omarchy (Arch Linux running Hyprland on Wayland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following symptoms on Omarchy / Arch Linux:
* **Shift key switching feels wrong**: Pressing `Shift + 1` (exclamation mark) or typing uppercase letters unexpectedly flips the input method to English/Chinese, producing mixed punctuation like `!！！！`.
* **Physical keyboard Shift fails**: Software key injection works, but physically single-tapping the Left Shift key does not toggle Chinese/English.
* **Terminal defaults to Chinese**: Opening a new terminal window inherits Chinese mode from the browser, requiring manual Shift switching before running commands.
* **Password inputs show Chinese candidates**: Typing passwords in `sudo`, the desktop lock screen, Polkit authentication dialogs, or web password fields unexpectedly triggers pinyin candidate boxes.
* **Chinese fonts render as Japanese variants**: Chinese characters like “门”, “复”, “骨” display with Japanese Kanji glyphs.
* **Domestic Linux apps (WeChat / WeCom)**: Window scaling is blurry, system tray icon disappears, or input method candidates fail to follow the cursor.

---

## 2. Quick Diagnostic Workflow

Always run the bundled diagnostic script first to identify which configuration layer is failing:

```bash
# Execute environment diagnostic
bash <skill_dir>/scripts/check_ime_env.sh
```

### Diagnostic Checklist:
| Check Item | Target Expected State | Failure Root Cause |
| :--- | :--- | :--- |
| **XKB `kb_options`** | `compose:caps` (No `both_capslock_cancel`) | XKB driver rule intercepts and drops lone Shift KeyUp (release) events. |
| **Fcitx5 Global Config** | `ActiveByDefault=True`<br>`ShareInputState=Program`<br>`AllowInputMethodForPassword=False`<br>`[Hotkey/TriggerKeys] 0=Control+space` | Missing `ActiveByDefault` starts apps in Inactive mode; missing `TriggerKeys` locks user in English when `keyboard-us` is present. |
| **Rime Session Isolation** | `~/.config/fcitx5/conf/rime.conf` with `InputState="Follow Global Configuration"` | Rime engine C++ defaults to `SharedStatePolicy::All`, sharing 1 session across all apps and ignoring `app_options` (quickshell/pinentry). |
| **Fcitx5 Profile** | Contains both `rime` and `keyboard-us` | Without `keyboard-us`, Fcitx5 fails to find an English layout to downgrade to when focusing password fields, falling back to Rime. |
| **Polkit QML Hints** | `/usr/share/omarchy/shell/plugins/polkit/PolkitAgent.qml` contains `inputMethodHints` | QtQuick `echoMode: TextInput.Password` only masks display; without `inputMethodHints`, Qt does not declare `CapabilityFlag::Password` to Wayland. |
| **Rime Custom Patches** | `ascii_composer/switch_key/Shift_L: commit_code`<br>(No `app_options` in schema patch) | `key_binder` triggers on KeyDown rather than KeyUp; rogue `app_options` in schema locks apps into ASCII permanently. |
| **Punctuation Mapping** | User-level `punctuation.yaml` with `{ commit: ... }` | Default upstream defines symbols as lists `[ ... ]` causing candidate popups (`\`, `>`, `$`); Enter triggers `commit_raw_input` (ASCII commit). |
| **Shell Hooks (`~/.bashrc`)** | DBus `SetAsciiMode true` hook + `sudo` wrapper | Terminal emulators lack password context flags; interactive sessions require lightweight 0ms async DBus initialization. |
| **Daemon Reload** | Full process restart (Not just `fcitx5-remote -r`) | `fcitx5-remote -r` only reloads configs; it DOES NOT reload `profile` or running Rime schemas in memory. |

---

## 3. Core Tuning Recipes

### Recipe 1: Fix Shift Key Toggle & Key Combination Misfires
1. Edit `~/.config/hypr/input.lua`:
   ```lua
   hl.config({
     input = {
       follow_mouse = 0,
       kb_options = "compose:caps", -- CRITICAL: Remove shift:both_capslock_cancel
     },
   })
   ```
2. Reload Hyprland config:
   ```bash
   hyprctl reload config-only
   ```
3. Add Rime modifier state machine patch in `~/.local/share/fcitx5/rime/default.custom.yaml` and `rime_ice.custom.yaml`:
   ```yaml
   patch:
     "ascii_composer/switch_key/Shift_L": commit_code
     "ascii_composer/switch_key/Shift_R": commit_code
     "punctuator/half_shape/!": "!"
     "punctuator/full_shape/!": "!"
   ```
   *(Note: NEVER put `app_options` here; keep them in `fcitx5.yaml` to avoid permanent ASCII lock).*

### Recipe 2: Isolate App State, Prevent Lockout & Enable Password Downgrade
1. Edit `~/.config/fcitx5/config`:
   ```ini
   [Hotkey/TriggerKeys]
   0=Control+space

   [Behavior]
   ActiveByDefault=True
   ShareInputState=Program
   AllowInputMethodForPassword=False
   ShowPreeditForPassword=False
   ```
2. Edit `~/.config/fcitx5/profile` (CRITICAL for password fields):
   ```ini
   [Groups/0]
   Name=Default
   Default Layout=us
   DefaultIM=rime

   [Groups/0/Items/0]
   Name=rime

   [Groups/0/Items/1]
   Name=keyboard-us   # MUST be present for password fallback
   ```
3. Edit `~/.config/fcitx5/conf/rime.conf` (CRITICAL: Rime internal session isolation):
   ```ini
   InputState="Follow Global Configuration"
   ```
4. Deploy schemas and **fully restart Fcitx5** (do NOT use `fcitx5-remote -r` alone):
   ```bash
   rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data ~/.local/share/fcitx5/rime/build
   systemctl --user restart omarchy-fcitx5.service 2>/dev/null || (pkill -x fcitx5 && sleep 0.5 && fcitx5 -d)
   ```

### Recipe 3: Shell Hook for Terminal English Default & CLI Passwords
Append to `~/.bashrc`:
```bash
# 1. Terminal interactive sessions default to English (Shift toggles freely)
if [[ $- == *i* ]] && [ -t 0 ] && [ -n "$WAYLAND_DISPLAY$DISPLAY" ]; then
    (gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1 &)
fi

# 2. CLI password commands automatically switch to English before prompting
for __pwd_cmd in sudo su pkexec passwd ssh doas; do
    eval "
    $__pwd_cmd() {
        (gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1 &)
        command $__pwd_cmd \"\$@\"
    }
    "
done
unset __pwd_cmd
```

### Recipe 4: Desktop Lock Screen English Switch
In `~/.config/hypr/bindings.lua`:
```lua
hl.unbind("SUPER + CTRL + L")
o.bind("SUPER + CTRL + L", "Lock system", "bash -c 'gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1; omarchy-system-lock'")
```

### Recipe 5: Windows-Aligned Punctuation Direct Commit (Zero Candidate Menus)
Copy `templates/punctuation.yaml` to `~/.local/share/fcitx5/rime/punctuation.yaml`.
This directly maps all Chinese punctuation (`\`, `>`, `$`, `[`, `]`, `{`, `}`, `^`, `_`, `~`) as scalar `{ commit: ... }`, completely eliminating the multi-candidate popup and raw Enter commit issue. Recompile and restart:
```bash
rime_deployer --build ~/.local/share/fcitx5/rime /usr/share/rime-data ~/.local/share/fcitx5/rime/build
systemctl --user restart omarchy-fcitx5.service 2>/dev/null || (pkill -x fcitx5 && sleep 0.5 && fcitx5 -d)
```

### Recipe 6: Fix Polkit GUI Password Dialog Automatic English (QtQuick Patch)
In `/usr/share/omarchy/shell/plugins/polkit/PolkitAgent.qml`, add `inputMethodHints` to `passwordInput`:
```qml
TextInput {
    id: passwordInput
    echoMode: TextInput.Password
    inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText
}
```
Restart Quickshell shell to apply:
```bash
/usr/share/omarchy/bin/omarchy-restart-shell
```

---

## 4. One-Click Automation Script

To apply all tested configurations cleanly:
```bash
bash <skill_dir>/scripts/apply_input_optimizations.sh
```

---

## 5. Verification Checklist

1. **Terminal Default English**: Focus a Chinese input in browser, open a new terminal with `Super + Return`, type `ls` -> pure English, no candidates.
2. **Terminal Shift Toggle**: In terminal, press Left Shift once -> type `ceshi` -> Chinese candidates appear (`测试`).
3. **Combination Misfire Test**: While in Chinese mode, hold Shift and press `1` -> outputs `!` without flipping IME state.
4. **sudo Password Test**: While in Chinese mode, run `sudo ls` -> on password prompt, type password -> pure English, no candidates.
5. **Polkit Dialog Test**: Trigger privileged action (e.g. `pkexec ls`) -> on GUI password dialog, type characters -> pure English dots, no candidate popup.
6. **Windows Punctuation Direct Commit**: In Chinese mode, press `\` -> immediately outputs `、` (no popup); press `>` -> `》`; press `$` -> `￥`; press `[` / `]` -> `【` / `】`.

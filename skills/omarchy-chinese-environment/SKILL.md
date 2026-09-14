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
| **Fcitx5 Global Config** | `ShareInputState=Program`<br>`AllowInputMethodForPassword=False` | Windows inherit each other's IME state; password fields fail to trigger passthrough. |
| **Fcitx5 Profile** | Contains both `rime` and `keyboard-us` | Without `keyboard-us`, Fcitx5 fails to find an English layout to downgrade to when focusing password fields, falling back to Rime. |
| **Rime Custom Patches** | `ascii_composer/switch_key/Shift_L: commit_code` | `key_binder` was incorrectly used instead of the native `ascii_composer` modifier state machine. |
| **Shell Hooks (`~/.bashrc`)** | DBus `SetAsciiMode true` hook + `sudo` wrapper | Terminal emulators lack password context flags; interactive sessions require lightweight 0ms async DBus initialization. |

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

### Recipe 2: Isolate App State & Enable Password Downgrade
1. Edit `~/.config/fcitx5/config`:
   ```ini
   [Behavior]
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

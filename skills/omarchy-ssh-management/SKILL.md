---
name: omarchy-ssh-management
description: Configure, diagnose, and optimize SSH session management and terminal remote tools on Omarchy (Arch Linux + Hyprland). Use when the user asks about SSH tools, session manager selection, tiling TUI workflows (sshs + Foot floating Spotlight), keybinding conflicts (hl.unbind Super+Shift+Enter), WindTerm setup, WindTerm prompt corruption (systemd OSC 3008 escape sequences), or WindTerm popup menu pointer grab issues (cannot click icon dropdowns in XWayland).
---

# Omarchy SSH Management & Terminal Tuning Skill

This skill provides an automated and standardized procedure for diagnosing, installing, and troubleshooting SSH session management and remote terminal workflows on **Omarchy (Arch Linux + Hyprland on Wayland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user on Omarchy / Arch Linux:
* **Asks for SSH client/session management recommendations**: Inquiring whether to use GUI tools (WindTerm, Termius) or native tiling TUI workflows.
* **Wants to setup the "Tiling Ceiling Suite"**: Deploying the ultra-fast `sshs` + `foot` floating window + `Super + Shift + Enter` workflow.
* **Encounters keybinding conflicts**: Pressing `Super + Shift + Enter` launches the browser simultaneously with the SSH manager (due to missing `hl.unbind`).
* **Runs into WindTerm prompt corruption**: Shell prompt prints garbage characters like `133;A`, `3008;...` upon pressing Enter or executing commands in WindTerm.
* **Suffers from WindTerm tiling squishing**: WindTerm's internal multi-dock panes getting squished into illegible strips by Hyprland tiling rules.
* **WindTerm popup / dropdown pointer grab failure**: In XWayland, clicking session icon dropdowns or popups loses focus or passes clicks through to the background, making it impossible to select an icon with the mouse.

---

## 2. Quick Environment Diagnostic

Always run the bundled diagnostic script to check the current system state:

```bash
bash <skill_dir>/scripts/check_ssh_env.sh
```

### Diagnostic Checklist:
| Check Item | Target Expected State | Failure Root Cause |
| :--- | :--- | :--- |
| **`sshs` Binary** | Installed (`extra/sshs`) | Not installed via pacman. |
| **Runner Script** | `~/.local/bin/ssh-manager` executable | Foot not configured with `--app-id=sshs-floating`. |
| **Hyprland Rules** | `sshs-floating` centered float | Window tiles into the grid instead of opening as a Spotlight popup. |
| **Hyprland Bindings** | `hl.unbind` called before `o.bind` | Omarchy defaults `SUPER + SHIFT + RETURN` to browser, causing dual launch. |
| **WindTerm OSC 3008** | Interception logic in `~/.bashrc` | systemd OSC 3008 escape sequences leak as raw ASCII text into WindTerm. |
| **WindTerm Popup Grab** | Direct JSON config editing | Qt5 XWayland popup windows lack pointer grabs in Wayland; direct editing of `user.sessions` and `session.config` bypasses the GUI. |

---

## 3. Core Tuning Recipes

### Recipe 1: Deploy TUI "Ceiling" Suite (`sshs` + Foot Spotlight)

1. **Install `sshs`**:
   ```bash
   sudo pacman -S --needed --noconfirm sshs
   ```
2. **Create Runner Script (`~/.local/bin/ssh-manager`)**:
   ```bash
   #!/bin/bash
   foot --app-id=sshs-floating --title="SSH Sessions" bash -c 'gdbus call --session --dest org.fcitx.Fcitx5 --object-path /rime --method org.fcitx.Fcitx.Rime1.SetAsciiMode true >/dev/null 2>&1; exec sshs'
   ```
   ```bash
   chmod +x ~/.local/bin/ssh-manager
   ```
3. **Configure Hyprland Floating Window Rule** in `~/.config/hypr/windowrules.lua`:
   ```lua
   o.window("sshs-floating", {
     tag = "+terminal",
     float = true,
     center = true,
     size = { 960, 600 },
   })
   ```
4. **Configure Keybinding with `hl.unbind`** in `~/.config/hypr/bindings.lua`:
   ```lua
   -- CRITICAL: Unbind default browser shortcut first
   hl.unbind("SUPER + SHIFT + RETURN")
   o.bind("SUPER + SHIFT + RETURN", "SSH Sessions", { launch = "ssh-manager" })
   ```
5. **Reload Hyprland**:
   ```bash
   hyprctl reload config-only
   ```

---

### Recipe 2: Fix WindTerm systemd OSC 3008 Prompt Garbage

When connecting to modern Linux hosts or running local bash in WindTerm, systemd shell integration emits OSC 3008 sequences that WindTerm cannot parse.

Append the following targeted patch to `~/.bashrc`:
```bash
# Suppress systemd shell integration OSC sequences specifically inside WindTerm
if [ "$TERM_PROGRAM" = "WindTerm" ] || [ -n "$WINDTERM_SESSION" ]; then
    __systemd_osc_context_precmdline() { :; }
    __systemd_osc_context_ps0() { :; }
    unset systemd_osc_context_cmd_id systemd_osc_context_shell_id
    PS0=""
fi
```

---

### Recipe 3: Prevent WindTerm Tiling Conflicts in Hyprland

In `~/.config/hypr/windowrules.lua`, either float WindTerm or assign it to a dedicated workspace:

```lua
-- Option A: Large floating window
o.window("WindTerm", {
  float = true,
  center = true,
  size = { 1400, 900 },
})

-- Option B: Dedicated workspace
o.window("WindTerm", {
  workspace = "8",
})
```

---

### Recipe 4: Fix WindTerm Session Icon & Bypass XWayland Popup Grab Failure

In Hyprland/XWayland, Qt5 popups (such as the session icon dropdown) fail to maintain pointer grab, causing the mouse cursor to lose focus or pass clicks through when hovering over the icon grid.

**Solution**:
1. Click **Cancel** in the WindTerm edit dialog (to avoid in-memory state overwriting the files).
2. Completely quit WindTerm.
3. Edit `~/.wind/profiles/default.v10/terminal/session.config` (for new sessions template) and `~/.wind/profiles/default.v10/terminal/user.sessions` (for existing sessions):
   Set `"session.icon": "session::cmd"` (black terminal console), `"session::linux"` (Tux penguin), or `"session::tmux"`.
4. Relaunch WindTerm.

Or use the automated script:
```bash
bash <skill_dir>/scripts/set_windterm_icon.sh "session::cmd"
```

---

## 4. Automation Scripts

* **Install Ceiling Suite**:
  ```bash
  bash <skill_dir>/scripts/install_ssh_manager.sh
  ```
* **Patch WindTerm Prompt (OSC 3008)**:
  ```bash
  bash <skill_dir>/scripts/fix_windterm_prompt.sh
  ```
* **Change WindTerm Session Icon (Bypass Popup Bug)**:
  ```bash
  bash <skill_dir>/scripts/set_windterm_icon.sh "session::cmd"
  ```

---

## 5. Verification Checklist

1. **Spotlight Popup**: Press `Super + Shift + Enter` -> Foot opens as a centered 960x600 floating window running `sshs`.
2. **No Browser Collision**: Confirm browser does NOT launch when pressing `Super + Shift + Enter`.
3. **Session Filter**: In `sshs`, type `/` to fuzzy-filter hosts defined in `~/.ssh/config`. Press Enter -> connects seamlessly.
4. **WindTerm Prompt**: Open WindTerm, execute commands -> confirm no `3008;...` or `133;A` characters appear.
5. **WindTerm Icon**: Verify `bash` and new SSH sessions display the classic console terminal icon without needing to click the broken popup window.

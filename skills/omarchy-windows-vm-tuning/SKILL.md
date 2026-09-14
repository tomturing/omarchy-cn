---
name: omarchy-windows-vm-tuning
description: Diagnose, isolate network, optimize performance, and resolve crash issues on Windows 11 VM (omarchy-windows-vm / dockurr/windows) under Omarchy (Arch Linux + Hyprland). Use when user reports issues with Windows VM network interference (Clash Fake-IP conflicts, VPN connection failure, Sangfor SSL VPN errors), slow Docker download of Windows images, Windows VM high CPU/RAM/disk usage, requests Btrfs CoW snapshots, or encounters VM window disappearing / FreeRDP clipboard SIGSEGV crashes.
---

# Omarchy Windows 容器虚拟机网络隔离、性能调优与故障排查 Skill

This skill provides comprehensive diagnostics, policy routing network isolation recipes, non-destructive Windows 11 performance slimming tools, and client crash recovery for running containerized Windows VMs (`omarchy-windows-vm` based on `dockurr/windows`) on **Omarchy (Arch Linux + Hyprland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following symptoms:
* **VM Window Disappears / False Crash**: The `Windows VM - Omarchy` window suddenly vanishes during copy-paste or web browsing, while the backend QEMU process is still healthy (FreeRDP 3.31.1 `xf_cliprdr.c` SIGSEGV crash).
* **VPN Connection Failure in VM**: Sangfor EasyConnect / aTrust or corporate SSL VPN reports "网络连接错误，请检查网络" (Network connection error).
* **Fake-IP / Proxy Pollution**: Domain name resolution inside the VM returns Fake-IP (`198.18.x.x`) due to host Clash TUN mode interception.
* **WeCom Timestamp Mismatch**: Enterprise WeChat messages show "昨天" (Yesterday) due to UTC-8 Pacific time zone deviation.
* **VM Sluggishness & High Resource Usage**: Windows 11 VM consumes high CPU (30%~80%), virtual disk I/O is 100% active, FreeRDP frame rate is laggy.
* **Docker / Windows ISO Download Slow**: Pulling `dockurr/windows` or downloading the 5GB `win11x64.iso` stalls or takes hours.
* **Snapshot & Backup Requests**: User wants an instant, zero-cost physical snapshot backup of the virtual machine disk.

---

## 2. Quick Diagnostic Workflow

Run the bundled diagnostic script to check host routing, container status, and RDP client stability:

```bash
bash <skill_dir>/scripts/check_vm_network.sh
```

### Diagnostic Checklist:
| Check Item | Target State | Failure Root Cause |
| :--- | :--- | :--- |
| **Linux Policy Route `pref 8990`** | `from 172.16.0.0/12 lookup main` | Docker VM traffic is being intercepted by Clash TUN (`pref 9000`). |
| **systemd Persistence Service** | `docker-bypass-clash.service` active | Policy routes will be wiped upon host reboot. |
| **VM DNS Resolution** | Resolves to real public IP (e.g. `223.5.5.5`) | VM inherits host Docker bridge DNS (`172.17.0.1`), returning Clash Fake-IPs (`198.18.x.x`). |
| **RDP Client Selection** | `sdl-freerdp3` | Legacy `xfreerdp3` triggers SIGSEGV on clipboard format synchronization (`xf_cliprdr.c:396`). |
| **VM Background Services** | `SysMain`, `WSearch`, `DiagTrack` disabled | Windows indexing and superfetch constantly thrash virtual disk I/O. |

---

## 3. Network Isolation Recipe (Dual-Track Model)

### Step 1: Apply Host Policy Routing Bypass
Run the bundled script to inject `pref 8990/8991` routes and enable the persistent systemd service:
```bash
bash <skill_dir>/scripts/enable_docker_bypass_clash.sh
```

### Step 2: Configure Clash Verge
In Clash Verge, verify:
1. `allow-lan: true`
2. TUN setting includes:
   ```yaml
   tun:
     route-exclude-address:
       - "172.16.0.0/12"
   ```

### Step 3: Decouple DNS Inside Windows VM
In Windows PowerShell (Run as Administrator):
```powershell
# Set real public DNS on active adapters
Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Set-DnsClientServerAddress -ServerAddresses ("223.5.5.5", "119.29.29.29")

# Fix Beijing time zone (+8)
Set-TimeZone -Id "China Standard Time"
```

---

## 4. Fix FreeRDP Clipboard Crash (Migrate to `sdl-freerdp3`)

When the remote desktop window crashes unexpectedly during copy/paste, `xfreerdp3` hit an upstream NULL pointer dereference in `xf_cliprdr_is_atom_available`.

### Automated One-Click Fix:
```bash
bash <skill_dir>/scripts/fix_vm_freerdp_crash.sh
```

### Manual Command:
```bash
sudo sed -i.bak 's/xfreerdp3 \/u:"\$WIN_USER"/sdl-freerdp3 \/u:"\$WIN_USER"/' /usr/share/omarchy/bin/omarchy-windows-vm
```
* **Why it works**: `sdl-freerdp3` uses the modern SDL clipboard architecture, completely bypassing the flawed X11 `xf_cliprdr.c` code path while maintaining 100% parameter compatibility.
* **Upstream Status**: Tracked in Omarchy Issue [#11789](https://github.com/omacom/omarchy/issues/11789).

---

## 5. Windows 11 Extreme Performance Slimming Recipe

Run the bundled PowerShell script inside the Windows VM (Administrator terminal):

```powershell
# Directly run script or execute commands from:
# <skill_dir>/scripts/optimize_windows_vm.ps1
```

### What this script does (100% Reversible & Safe):
1. **Visual Effects to Performance Mode**: Disables window zoom animations, smooth scrolling, and transparency (`MinAnimate=0`), dramatically improving FreeRDP encoding efficiency.
2. **Disables High I/O Hogging Services**:
   * `SysMain`: Superfetch causes virtual disk thrashing.
   * `WSearch`: Windows Search indexing creates constant 100% disk usage.
   * `DiagTrack`: Telemetry upload service.
3. **Disables Widgets & Background Apps**: Turns off News/Interests and background app access.
4. **Disables Hibernation (`powercfg -h off`)**: Frees 4GB~8GB of physical virtual disk space.

---

## 6. Btrfs Instant Zero-Cost Snapshot Backup

Take advantage of Omarchy's native Btrfs filesystem CoW (Copy-on-Write):

```bash
# Create instant snapshot (takes 0.1s, uses 0 extra disk space)
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh backup

# Restore from snapshot in 1 second if needed
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh restore

# Check snapshot status
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh status
```

---

## 7. Pre-seeding Windows 11 ISO (Download Bypass)

To skip the 5GB online download during container deployment:
1. Pre-download `win11x64.iso` using IDM / aria2 externally.
2. Copy into `/var/lib/omarchy/windows/mounts/users/1000/storage/win11x64.iso`.
3. Set ownership `sudo chown tom:tom ...`.
4. Launch container: `omarchy-windows-vm launch`.

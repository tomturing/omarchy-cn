---
name: omarchy-windows-vm-tuning
description: Diagnose, isolate network, optimize performance, and resolve crash/scaling issues on Windows 11 VM (omarchy-windows-vm / dockurr/windows) under Omarchy (Arch Linux + Hyprland). Use when user reports issues with Windows VM network interference (Clash Fake-IP conflicts, VPN connection failure, Sangfor SSL VPN errors), slow Docker download of Windows images, Windows VM high CPU/RAM/disk usage, requests Btrfs CoW snapshots, or encounters VM window disappearing / FreeRDP clipboard SIGSEGV crashes / sdl-freerdp3 black borders.
---

# Omarchy Windows 容器虚拟机网络隔离、性能调优与故障排查 Skill

This skill provides comprehensive diagnostics, policy routing network isolation recipes, non-destructive Windows 11 performance slimming tools, and client crash/scaling recovery for running containerized Windows VMs (`omarchy-windows-vm` based on `dockurr/windows`) on **Omarchy (Arch Linux + Hyprland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following symptoms:
* **VM Window Disappears / False Crash**: The `Windows VM - Omarchy` window suddenly vanishes during copy-paste or web browsing, while the backend QEMU process is still healthy (FreeRDP 3.31.1 `xf_cliprdr.c` SIGSEGV crash).
* **Black Borders with sdl-freerdp3 (Letterboxing)**: Attempted switching to `sdl-freerdp3` but suffered from black bars on the right/bottom and blurry resolution under Hyprland fractional scaling (1.25x).
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
| **Docker Compose DNS** | `docker-compose.yml` contains `dns: [223.5.5.5, ...]` | VM container inherits host `daemon.json` (`172.17.0.1`), causing `dnsmasq` to return Clash Fake-IP (`198.18.x.x`), which drops at physical gateway (`ERR_TIMED_OUT` / `0x80240438`). |
| **VM Container Live DNS** | Resolves real public IP (e.g. `183.2.172.x`) | Live resolver in container still pointing to `172.17.0.1`. |
| **RDP Client & Patch** | `xfreerdp3` with upstream patch | Unpatched `xfreerdp3` segfaults on clipboard formats; unpatched `sdl-freerdp3` causes black borders under 1.25x scaling. |
| **VM Background Services** | `SysMain`, `WSearch`, `DiagTrack` disabled | Windows indexing and superfetch constantly thrash virtual disk I/O. |

---

## 3. Network Isolation Recipe (Dual-Track Model)

### Step 1: Apply Host Policy Routing & Docker DNS Decoupling
Run the bundled script to inject `pref 8990/8991` routes, configure container public DNS (`223.5.5.5`, `119.29.29.29`), and enable the persistent systemd service:
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

### Step 3: Decouple DNS at Docker Compose Layer (Zero In-VM Actions Needed)
Ensure `/var/lib/omarchy/windows/docker-compose.yml` has:
```yaml
services:
  windows:
    environment:
      DNSMASQ_OPTS: "--server=223.5.5.5 --server=119.29.29.29 --server=8.8.8.8"
    dns:
      - 223.5.5.5
      - 119.29.29.29
      - 8.8.8.8
```
`dnsmasq` inside the container will automatically serve clean public DNS via standard DHCP to the Windows guest.

### Step 4: Optional Verification / In-VM Flush
If Windows previously cached old Fake-IP records, run in Windows terminal:
```powershell
ipconfig /flushdns
nslookup www.baidu.com  # Must return real public IP, NOT 198.18.x.x
```

---

## 4. Fix FreeRDP Clipboard Crash (Ultimate Solution: Recompile xfreerdp3 with Upstream Patch)

### Why NOT switch to `sdl-freerdp3`?
In Hyprland with fractional scaling (`1.25x`), `sdl-freerdp3` (still marked as experimental upstream) causes massive black borders (Letterboxing) on the right and bottom, along with blurred display resolution.

### The Ultimate Fix:
Keep `xfreerdp3` for flawless native scaling and fullscreen, while applying the upstream 1-line patch to fix the NULL pointer loop boundary in `client/X11/xf_cliprdr.c`:

```diff
--- a/client/X11/xf_cliprdr.c
+++ b/client/X11/xf_cliprdr.c
@@ -391,3 +391,3 @@ static BOOL xf_cliprdr_is_atom_available(xfClipboard* clipboard, Atom atom)
-	for (size_t x = 0; x < clipboard->numClientFormats; x++)
+	for (size_t x = 0; x < clipboard->clientAvailableFormatAtomsCount; x++)
```

### Automated One-Click Recompile & Install:
```bash
bash <skill_dir>/scripts/rebuild_freerdp_with_patch.sh
```
* **Upstream Tracking**: Tracked in Omarchy Issue [#11789](https://github.com/omacom/omarchy/issues/11789) with practical scaling verification feedback.

---

## 5. Windows 11 Extreme Performance Slimming Recipe

Run the bundled ASCII batch script with auto-elevation inside the Windows VM (`deep_clean_vm.bat`):

```cmd
# Double click or run as Administrator:
# ~/Windows/deep_clean_vm.bat (mapped to Z: or \\172.30.0.1\Data)
```

> [!WARNING]
> **Windows Batch UTF-8 Pitfall**:
> Avoid saving `.bat` files with UTF-8 multi-byte Chinese characters. Windows `cmd.exe` misinterprets multi-byte bytes as syntax delimiters, skipping services or failing with syntax errors. Always use **Pure ASCII + CRLF line terminators**.

### What this script does (100% Reversible & Safe):
1. **Visual Effects to Performance Mode**: Disables window zoom animations, smooth scrolling, and transparency (`MinAnimate=0`), dramatically improving FreeRDP encoding efficiency.
2. **Disables High I/O Hogging Services**:
   * `SysMain`: Superfetch causes virtual disk thrashing.
   * `WSearch`: Windows Search indexing creates constant 100% disk usage.
   * `DiagTrack`: Telemetry upload service.
3. **Disables Widgets & Background Apps**: Turns off News/Interests and background app access.
4. **Disables Hibernation (`powercfg -h off`)**: Frees 4GB~8GB of physical virtual disk space.
5. **Auto-fixes `Z:` Drive `host.lan`**: Appends `172.30.0.1 host.lan` to `%SystemRoot%\System32\drivers\etc\hosts`.

---

## 6. Fix `Z:` Drive Disconnected (Red X) & "Cannot find C:\shared\"

* **Symptom**: In Windows VM, user types `C:\shared\` and gets "Windows cannot find C:\shared\". `Data (\\host.lan) (Z:)` shows a red X.
* **Root Cause**: `C:\shared\` is only a Linux container path; the Windows path is Samba share `Z:`. When Windows DNS is changed to public `223.5.5.5` to bypass Clash Fake-IP, public DNS cannot resolve the internal `host.lan` domain.
* **Instant Fix**:
  Run in Windows Administrator PowerShell:
  ```powershell
  Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n172.30.0.1 host.lan"
  ```
  Or directly browse `\\172.30.0.1\Data`.

---

## 7. Host Hardware Resource Sizing (Avoid Swap Thrashing)

On a 4-core / 16GB host (e.g. Intel i5-1135G7):
* **Default Pitfall**: Over-allocating 6 cores and 8GB RAM starves the Linux host, leaving ~1GB free RAM and forcing 3GB+ into compressed Swap (`/dev/zram0`). This causes Hyprland/Quickshell window and menu freezes.
* **Golden Sizing (4 Cores + 6GB RAM)**:
  ```bash
  sudo sed -i -E 's/RAM_SIZE: ".*"/RAM_SIZE: "6G"/; s/CPU_CORES: ".*"/CPU_CORES: "4"/' /var/lib/omarchy/windows/docker-compose.yml
  sudo docker compose -f /var/lib/omarchy/windows/docker-compose.yml down
  sudo docker compose -f /var/lib/omarchy/windows/docker-compose.yml up -d
  ```
* **Result**: Host Swap usage drops to **0 B**, available RAM doubles (2.2GB -> 4.4GB+), and desktop stutters disappear.

---

## 8. Btrfs Instant Zero-Cost Snapshot Backup

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

## 9. Pre-seeding Windows 11 ISO (Download Bypass)

To skip the 5GB online download during container deployment:
1. Pre-download `win11x64.iso` using IDM / aria2 externally.
2. Copy into `/var/lib/omarchy/windows/mounts/users/1000/storage/win11x64.iso`.
3. Set ownership `sudo chown tom:tom ...`.
4. Launch container: `omarchy-windows-vm launch`.


---
name: omarchy-windows-vm-tuning
description: Diagnose, isolate network, optimize performance, and resolve crash/scaling/memory issues on Windows 11 VM (omarchy-windows-vm / dockurr/windows) under Omarchy (Arch Linux + Hyprland). Use when user reports issues with Windows VM network interference (Clash Fake-IP conflicts, VPN connection failure, Sangfor SSL VPN errors), slow Docker download of Windows images, Windows VM high CPU/RAM/disk usage, host memory exhaustion / Chromium renderer watchdog SIGKILL (code 9) crashes, slow cold boot latency (~20s wait), requests Btrfs defragmentation/CoW snapshots, or encounters VM window disappearing / FreeRDP clipboard SIGSEGV crashes / sdl-freerdp3 black borders.
---

# Omarchy Windows 容器虚拟机网络隔离、性能调优与故障排查 Skill

This skill provides comprehensive diagnostics, policy routing network isolation recipes, tiered host memory/Swap architecture, non-destructive Windows 11 performance slimming tools, vCPU scaling, and client crash/scaling recovery for running containerized Windows VMs (`omarchy-windows-vm` based on `dockurr/windows`) on **Omarchy (Arch Linux + Hyprland)**.

---

## 1. When to Use This Skill

Activate this skill whenever a user encounters any of the following symptoms:
* **Host Memory Thrashing / Chromium Renderer Watchdog Crash (Code 9)**: Host runs a 6GB Windows VM alongside heavy modern Electron IDEs (CodeBuddy, Qoder) or browsers, causing host free RAM to drop below 500MB, `/dev/zram0` to bloat up to 8.8GB (consuming ~2GB of host physical RAM), and Chromium renderers being killed with `SIGKILL` (code 9).
* **Slow Windows VM Cold Boot (~20s Latency)**: Cold boot after system startup takes ~20 seconds before the Windows RDP window appears.
* **Btrfs Virtual Disk Fragmentation**: Virtual disk image (`data.img`) on Btrfs develops hundreds of thousands of extents (fragmentation), leading to severe disk I/O latency.
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
| **Host Memory & Swap Tiering** | zram capped at 4GB (`pri=100`), NVMe swap active | Uncapped zram expands to 8GB+, starving host physical RAM and triggering Chromium renderer kills. |
| **QEMU Disk Cache & Balloon** | `cache=writeback,aio=threads` + `virtio-balloon-pci` | `cache=none` causes synchronous I/O bottlenecks; lack of ballooning blocks host-guest memory reclamation. |
| **Btrfs Extent Count** | `< 100,000` extents on `data.img` | Heavy fragmentation (>800k extents) throttles sequential and random virtual disk reads. |
| **VM vCPU Allocation** | `CPU_CORES: "6"` on 8-thread CPU | 4 single-threaded vCPUs cause boot-time service and driver contention. |
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

Run the bundled PowerShell script with auto-elevation inside the Windows VM (`optimize_windows_vm.ps1`):

```powershell
# In Windows Administrator PowerShell:
# Execute optimize_windows_vm.ps1 from Z:\ (or \\172.30.0.1\Data)
```

### What this script does (100% Reversible & Safe):
1. **Visual Effects to Performance Mode**: Disables window zoom animations, smooth scrolling, and transparency (`MinAnimate=0`), dramatically improving FreeRDP encoding efficiency.
2. **Disables High I/O Hogging Services**:
   * `SysMain`: Superfetch causes virtual disk thrashing.
   * `WSearch`: Windows Search indexing creates constant 100% disk usage.
   * `DiagTrack`: Telemetry upload service.
3. **Enables Windows Memory Compression**: Executes `Enable-MMAgent -MemoryCompression -PageCombining` to compress idle guest memory.
4. **Limits Windows Defender CPU Overhead**: `Set-MpPreference -ScanAvgCPULoadFactor 25` prevents background scans from consuming >25% of virtual CPU.
5. **Ultra-Fast Boot Configuration**:
   * `bcdedit /timeout 0`: Eliminates OS boot selection timeout.
   * `bcdedit /set bootux disabled`: Disables boot graphics rendering.
   * `bcdedit /set quietboot on`: Enables silent, clean boot.
6. **Disables Widgets & Background Apps**: Turns off News/Interests and background app access.
7. **Auto-fixes `Z:` Drive `host.lan`**: Appends `172.30.0.1 host.lan` to `%SystemRoot%\System32\drivers\etc\hosts`.

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

## 7. Host Hardware Resource Sizing & Tiered Memory Architecture

On a 16GB host (e.g. Intel i5-1135G7) running a 6GB Windows VM alongside heavy AI IDEs:

### 1. The Core Hazard: zram Inflation & Physical RAM Starvation
* **Hazard**: By default, `zram-generator` may allocate 50%~100% of RAM to `/dev/zram0` without a cap. When committed memory spikes, zram fills up to 8.8GB, consuming ~2GB of physical host RAM. At the same time, NVMe swapfile priority is lower or equal, leaving 0B usage. The kernel and applications suffer severe memory thrashing, triggering Chromium renderer watchdog kills (`SIGKILL` 9).

### 2. Tiered Swap & Memory Architecture
Run the automated host tuning script:
```bash
bash <skill_dir>/scripts/tune_host_memory_and_vm.sh
```

This enforces:
1. **zram Cap (4GB, Priority 100)**: `/etc/systemd/zram-generator.conf.d/99-cap-zram.conf`:
   ```ini
   [zram0]
   zram-size = 4096
   compression-algorithm = zstd
   swap-priority = 100
   ```
2. **NVMe Swap Tiered Overflow (Priority 10)**: `/etc/sysctl.d/99-swap-tuning.conf`:
   ```ini
   vm.swappiness = 100
   vm.vfs_cache_pressure = 100
   vm.watermark_scale_factor = 200
   ```
3. **Transparent Huge Pages (THP) to `madvise`**: `/etc/tmpfiles.d/thp.conf` sets THP to `madvise` and defrag to `defer+madvise` to eliminate memory fragmentation bloat.
4. **Kernel Samepage Merging (KSM)**: `/etc/tmpfiles.d/ksm.conf` enables page deduplication across virtual machine memory.
5. **Desktop Session Protection**: `~/.config/systemd/user/session.slice.d/10-memory-protection.conf` sets `MemoryLow=1G` to prevent desktop compositor stutter.

---

## 8. Storage Layer Optimization (Btrfs Defrag & Writeback Caching)

### 1. Btrfs Defragmentation
Virtual disk raw images on Btrfs undergo heavy fragmentation due to Copy-on-Write and random guest writes.
Defragment the disk image directly:
```bash
sudo btrfs filesystem defragment -f -c /var/lib/omarchy/windows/mounts/users/1000/storage/data.img
```
* **Impact**: Reduces disk extents by >90% (e.g., from 868k extents down to ~69k), cutting virtual disk seek overhead dramatically.

### 2. QEMU Writeback Caching & VirtIO Ballooning
In `/var/lib/omarchy/windows/docker-compose.yml`:
```yaml
services:
  windows:
    environment:
      DISK_CACHE: "writeback"
      ARGUMENTS: "-rtc base=localtime,clock=host,driftfix=slew -device virtio-balloon-pci,id=balloon0"
```
* **`DISK_CACHE: "writeback"`**: Switches QEMU I/O from blocking direct/threads to buffered writeback with background thread flushing.
* **`virtio-balloon-pci`**: Allows the Linux host and Windows guest to dynamically balance memory pages.

---

## 9. vCPU Expansion & Boot Latency Breakdown

### 1. First Principles: The ~20-Second Cold Boot Anatomy
When booting from cold, the ~20s latency is composed of:
1. **Container & UEFI Init (~4-5s)**: Docker daemon launch, QEMU process spawn, OVMF UEFI firmware load, Windows Boot Manager.
2. **Windows 11 Kernel & Driver Cold Boot (~14-15s)**: `ntoskrnl.exe` initialization, VirtIO drivers, subsystem bringup, and Terminal Services (`TermService` on port 3389). (Verified via Event ID 100 `BootDuration`: ~15.4s).
3. **FreeRDP Handshake & Rendering (~1-2s)**: NLA credentials exchange, DWM desktop painting.
* **Conclusion**: 15~20 seconds is the physical floor for a complete cold boot of Windows 11 on an i5-1135G7 mobile CPU with 4 vCPUs.

### 2. Expanding to 6 vCPUs
Because the host CPU has 4 cores and 8 threads, allocate `CPU_CORES: "6"` in `docker-compose.yml`:
```yaml
services:
  windows:
    environment:
      CPU_CORES: "6"
```
During driver initialization and boot, Windows bursts up to 360%+ CPU usage across 6 concurrent virtual threads, reducing boot bottlenecks.

---

## 10. Suspend-to-RAM vs. Cold Boot Workflow Paradigm

To achieve **instant 0-second startup**:
* **Physical Fact**: Cold Boot requires traversing full UEFI, kernel, and driver initialization every time.
* **Solution**: Use **Suspend / Sleep (挂起)** instead of shutting down the host.
  1. Closing the laptop lid or running `systemctl suspend` suspends the host to RAM (S3/s2idle).
  2. The Linux host, Docker daemon, QEMU process, and the 6GB Windows memory are completely preserved in warm RAM.
  3. Upon wake-up (1s), opening the Windows VM connects via RDP in **< 0.5s**, achieving true instant access.
* **Clock Drift Safety**: Configured `-rtc base=localtime,clock=host,driftfix=slew` and `invtsc` (Invariant TSC) guarantees the Windows guest clock syncs seamlessly without time jumps or SSL handshake errors upon resume.

---

## 11. Quick Recovery Helper (`restart-windows`)

Included in `templates/bashrc_restart_helpers.sh`, this shell function provides a one-command cold restart for frozen RDP sessions:
```bash
restart-windows        # Stop gracefully (or kill after 15s), cold restart, and poll port 3389
restart-windows -l     # Cold restart and immediately launch RDP connection window
```

---

## 12. Btrfs Instant Zero-Cost Snapshot Backup

Take advantage of Omarchy's native Btrfs filesystem CoW (Copy-on-Write):

```bash
# Create instant snapshot (takes 0.1s, uses 0 extra disk space)
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh backup

# Restore from snapshot in 1 second if needed
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh restore

# Check snapshot status
bash <skill_dir>/scripts/snapshot_vm_btrfs.sh status
```

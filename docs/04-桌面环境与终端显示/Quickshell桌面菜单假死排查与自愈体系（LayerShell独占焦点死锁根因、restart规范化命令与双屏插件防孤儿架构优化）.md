# Quickshell 桌面菜单假死排查与自愈体系
> 涵盖：Omarchy 主菜单（Super+Space）假死根因定位、QtWayland 与 LayerShell 独占焦点死锁机制剖析、`restart-<target>` 标准化自愈命令库、双屏环境自定义插件单例互斥与防孤儿生命周期重构。

---

## 一、故障现象与排查背景

在基于 **Omarchy (Arch Linux + Hyprland + Quickshell)** 的桌面系统中，用户频繁遭遇如下桌面假死现象：

1. **主菜单无响应**：按下快捷键 `Super + 空格`（`Super + Space`）准备呼出系统主菜单或启动应用时，桌面完全没有任何弹出反馈；
2. **IPC 探活超时**：在终端执行 `omarchy menu ping`，命令行在 2 秒后报出：
   ```text
   omarchy-shell is not responding
   ```
3. **系统级无响应告警**：查看用户系统日志 `journalctl --user`，发现系统无障碍总线早在几分钟前就已将 Quickshell 判定为挂死状态：
   ```text
   at-spi2-registryd[1513]: Disabling unresponsive app with pid 1406
   ```
4. **常规自愈手段失效**：执行官方提供的 `omarchy restart shell`，命令陷入长时间卡顿，最终打印：
   ```text
   Omarchy shell did not become ready after restart.
   ```

---

## 二、深层技术根因剖析

通过对进程内核通道状态（`/proc/<pid>/wchan`）、Qt 运行时日志（`log.qslog`）以及 Hyprland 桌面事件流的综合跟踪，我们还原了导致死锁的完整链条：

### 1. 进程死锁状态：`futex_do_wait`
检查挂死的 Quickshell 主进程发现：
```bash
$ ps -p 1406 -o pid,stat,time,%cpu,%mem,comm && cat /proc/1406/wchan
  PID STAT     TIME %CPU %MEM COMMAND
 1406 Sl   00:11:38  0.9  2.8 quickshell
futex_do_wait
```
进程既未崩溃退出（所以外部守护脚本没有捕获到死亡退出码予以拉起），也未飙满 CPU，而是永久挂死在 Linux 内核的 **互斥锁等待队列（Futex Wait）** 中。

### 2. 根本诱因：LayerShell 独占键盘焦点销毁与合成器重载竞态
查看 `log.qslog` 中进程挂死前最后几毫秒的事件记录：
```text
Received event: "openlayer>>omarchy-menu"
Received event: "closelayer>>omarchy-menu"
Received event: "openlayer>>omarchy-image-selector"
Received event: "closelayer>>omarchy-image-selector"
Received event: "configreloaded>>" parsed as "configreloaded" ""
Making request: "j/monitors"
Making request: "j/clients"
New IPC connection qs::ipc::IpcServerConnection(...)
```

**死锁发生的微观机制**：
1. **独占焦点争夺**：当用户在菜单中切换壁纸或主题时，壁纸选择器（`ImagePicker.qml`）作为 Overlay 层请求了 **`WlrKeyboardFocus.Exclusive`（独占键盘焦点）**。
2. **图层注销与事件交汇**：当选择器关闭时触发 `closelayer`；与此同时，主题切换动作修改了 Hyprland 相关参数并触发了 `hyprctl reload`，Hyprland 向所有客户端广播 `configreloaded>>`。
3. **线程互斥死锁**：
   - Quickshell 基于 **Qt6 (QtWayland)**。QtWayland 的主事件循环在注销 LayerShell 表面并等待 Wayland 合成器的 Frame Callback 确认时，与 Quickshell 内部处理 Hyprland Socket 通信的 IPC 工作线程在 Qt 内部事件队列的锁上产生了**循环互斥死锁**。
   - Qt 主线程事件循环彻底停摆，后续所有通过 Unix Socket 进来的 `omarchy.menu` 打开请求全部超时挂死。

---

## 三、快速自愈与标准化命令库（restart-<target>）

为了避免每次卡死都需要繁琐切换 TTY 或输入冗长命令，遵循 Linux / POSIX 命令行最佳实践，在 `~/.bashrc` 中建立统一以 **`restart-<target>`** 开头的快捷自愈命令体系（利用 Kebab-Case 命名，享受 Tab 键一键补全）。

### 1. 标准配置（~/.bashrc）

在 `~/.bashrc` 末尾添加如下规范化函数与别名：

```bash
# ==============================================================================
# 快捷恢复与重启命令规范: restart-<component>
# 规范说明: 统一采用 kebab-case (中划线)，输入 "restart-" + Tab 即可自动补全所有可用恢复命令
# ==============================================================================

# 1. 桌面 Shell / 菜单恢复 (针对 Omarchy 菜单、顶栏、Quickshell 死锁卡顿)
restart-shell() {
    echo "Restarting Quickshell / Omarchy shell..."
    # 必须强制 killall -9，因为处于 futex 死锁的进程无法响应普通 IPC 退出信号
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
```

### 2. 标准命令清单与使用场景

| 标准命令 | 兼容别名 | 解决的典型故障 | 恢复耗时 |
| :--- | :--- | :--- | :--- |
| **`restart-shell`** | `restart-quickshell`<br>`rshell` | `Super+Space` 菜单卡死、顶栏时钟/组件冻结、`omarchy menu ping` 超时。 | **1 ~ 2 秒** |
| **`restart-clip`** | `restart-clipboard`<br>`fix-clip` | 虚拟机与宿主机之间复制文本无响应、`wl-paste` 管道挂死。 | **0.1 秒** |

> [!TIP]
> **Tab 键极简补全**：在任何终端中输入 `restart-` 并按两下 `Tab`，即可直观列出所有可用的急救工具，无需死记硬背。

---

## 四、双显示器环境下顶栏插件防死锁调优

很多时候 Quickshell 的事件循环变卡，是由于第三方或本地自定义插件编写不规范导致的。在双显示器（例如笔记本屏幕 `eDP-1` + 外接显示器 `HDMI-A-1`）环境下尤为严峻。

### 1. `local.netspeed`（实时网速插件）架构重构

#### 原架构缺陷（致命隐患）：
- **多屏重复采样**：每个显示器的顶栏独立实例化了 `NetSpeed.qml`，导致后台同时启动了 2 个独立的 `netspeed.sh` 死循环进程，每秒同时扫描 `/proc/net/dev` 并向主线程管道推流。
- **孤儿进程泄漏**：脚本未加锁、未捕获父进程退出，屏幕插拔、休眠或 Shell 重启时，旧进程变成孤儿进程在后台永久无限循环。
- **主线程解析压力**：使用 `SplitParser` 挂在 Qt 主线程的管道上，高频数据推送加剧了事件队列死锁风险。

#### 现代加固重构方案：

##### ① 采样脚本：单例文件锁 + 内核生命周期绑定 (`netspeed.sh`)
```bash
#!/bin/bash
set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
LOCK_FILE="$RUNTIME_DIR/omarchy-netspeed.lock"
DATA_FILE="$RUNTIME_DIR/omarchy-netspeed.json"
TMP_FILE="$RUNTIME_DIR/omarchy-netspeed.json.tmp"

# 1. 单例文件锁：保证全局仅允许 1 个采样实例运行，多余屏幕启动直接秒退
exec 200>"$LOCK_FILE"
flock -n 200 || exit 0

cleanup() {
  rm -f "$TMP_FILE" "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

prev_rx=0
prev_tx=0
first=1

get_stats() {
  local rx=0 tx=0 ifaces=""
  local found_phys=0

  while read -r line; do
    [[ "$line" != *:* ]] && continue
    line="${line//:/ }"
    read -r dev r_bytes r_pkt r_err r_drop r_fifo r_frame r_comp r_mcast t_bytes rest <<< "$line"
    [[ "$dev" == "lo" ]] && continue
    [[ "$dev" =~ ^(docker|br-|veth) ]] && continue

    if [[ -e "/sys/class/net/$dev/device" ]]; then
      local st=""
      [[ -r "/sys/class/net/$dev/operstate" ]] && st=$(< "/sys/class/net/$dev/operstate")
      if [[ "$st" != "down" ]]; then
        (( rx += r_bytes ))
        (( tx += t_bytes ))
        ifaces+="${ifaces:+, }$dev"
        found_phys=1
      fi
    fi
  done < /proc/net/dev

  echo "$rx $tx ${ifaces:-none}"
}

while true; do
  # 2. 防孤儿自毁机制：父进程挂死或被 init 接管时主动退出
  if [[ $PPID -le 1 ]] || ! kill -0 "$PPID" 2>/dev/null; then
    exit 0
  fi

  read -r rx tx ifaces < <(get_stats)

  if (( first )); then
    first=0
    prev_rx=$rx
    prev_tx=$tx
    sleep 1
    continue
  fi

  rx_rate=$(( rx - prev_rx ))
  tx_rate=$(( tx - prev_tx ))
  (( rx_rate < 0 )) && rx_rate=0
  (( tx_rate < 0 )) && tx_rate=0
  prev_rx=$rx
  prev_tx=$tx

  # 3. 原子写入内存文件系统 (/dev/shm 或 /run/user/1000/)，零磁盘开销
  printf '{"down":%d,"up":%d,"total_down":%d,"total_up":%d,"iface":"%s"}\n' \
    "$rx_rate" "$tx_rate" "$rx" "$tx" "$ifaces" > "$TMP_FILE"
  mv -f "$TMP_FILE" "$DATA_FILE"

  sleep 1
done
```

##### ② 前端组件：改用 Quickshell 原生 `FileView` 监听 (`NetSpeed.qml`)
- 移除了进程管道与 `SplitParser`，改由 `FileView` 监听内存文件；
- 启动进程使用 `setpriv --pdeathsig TERM`，确保 Quickshell 退出时内核自动向子进程下发 TERM 信号；
- 无论系统插接了多少个显示器，各屏幕顶栏均**共享同一份内存网速数据**，CPU 消耗归零。

---

### 2. `local.fcitx-input`（输入法状态指示）防并发优化

检查原组件发现，每个屏幕顶栏每 800ms 触发一次 `fcitx5-remote -n`，双屏下相当于每秒无谓执行 2.5 次进程创建，且缺乏并发保护。

**加固优化要点**：
1. **增加重入锁保护**：
   ```qml
   function refresh() {
     if (!queryProc.running) queryProc.running = true
   }
   ```
2. **微调合理轮询频率**：将周期调整为 **1500ms**（平衡状态实时性与系统开销）；
3. **注销钩子清理**：
   ```qml
   Component.onDestruction: {
     queryProc.running = false
     toggleProc.running = false
   }
   ```

---

## 五、验证与长效保障

1. **进程数验证**：
   ```bash
   ps aux | grep netspeed | grep -v grep | wc -l
   # 预期输出：严格为 1
   ```
2. **IPC 响应与健康度验证**：
   ```bash
   omarchy menu ping
   # 预期输出：ok
   ```
3. **故障发生时一秒恢复**：
   在任何终端中输入 `restart-shell` 并回车，顶栏和菜单在 1 秒内无缝拉起。

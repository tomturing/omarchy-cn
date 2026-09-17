#!/bin/bash

# Real-time network throughput streamer for Omarchy bar widget
# Single-instance background sampler: writes to $XDG_RUNTIME_DIR/omarchy-netspeed.json

set -euo pipefail

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID}"
LOCK_FILE="$RUNTIME_DIR/omarchy-netspeed.lock"
DATA_FILE="$RUNTIME_DIR/omarchy-netspeed.json"
TMP_FILE="$RUNTIME_DIR/omarchy-netspeed.json.tmp"

# 保证整个系统全局单例，其它屏幕启动的实例获取锁失败直接退出
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

  if (( !found_phys )); then
    while read -r line; do
      [[ "$line" != *:* ]] && continue
      line="${line//:/ }"
      read -r dev r_bytes r_pkt r_err r_drop r_fifo r_frame r_comp r_mcast t_bytes rest <<< "$line"
      [[ "$dev" == "lo" ]] && continue
      [[ "$dev" =~ ^(docker|br-|veth) ]] && continue
      (( rx += r_bytes ))
      (( tx += t_bytes ))
      ifaces+="${ifaces:+, }$dev"
    done < /proc/net/dev
  fi

  echo "$rx $tx ${ifaces:-none}"
}

while true; do
  # 防孤儿安全保障：若父进程挂掉被 init 接管，立即安全退出
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

  printf '{"down":%d,"up":%d,"total_down":%d,"total_up":%d,"iface":"%s"}\n' \
    "$rx_rate" "$tx_rate" "$rx" "$tx" "$ifaces" > "$TMP_FILE"
  mv -f "$TMP_FILE" "$DATA_FILE"

  sleep 1
done

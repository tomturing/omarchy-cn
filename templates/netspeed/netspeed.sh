#!/bin/bash
# Real-time network throughput streamer for Omarchy bar widget
# Emits a JSON line every second with current RX/TX rates and totals.

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
    "$rx_rate" "$tx_rate" "$rx" "$tx" "$ifaces"

  sleep 1
done

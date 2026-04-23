#!/bin/bash
# ~/.config/sway/statusbar.sh — minimal swaybar status script
# Outputs one line per second: net | mem | cpu | time

_cpu() {
    # Δ idle across 200ms sample
    read -r _ u n s id _ < /proc/stat
    total1=$(( u+n+s+id ))
    idle1=$id
    sleep 0.2
    read -r _ u n s id _ < /proc/stat
    total2=$(( u+n+s+id ))
    idle2=$id
    dt=$(( total2 - total1 ))
    di=$(( idle2  - idle1  ))
    [ $dt -eq 0 ] && echo "CPU: 0%" && return
    echo "CPU: $(( 100 - di * 100 / dt ))%"
}

_mem() {
    local total avail
    total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
    avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
    local used=$(( (total - avail) / 1024 ))
    local pct=$(( (total - avail) * 100 / total ))
    echo "MEM: ${used}M (${pct}%)"
}

_net() {
    local iface rx1 tx1 rx2 tx2
    iface=$(ip route | awk '/default/{print $5; exit}')
    [ -z "$iface" ] && echo "NET: offline" && return
    rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    sleep 1
    rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null || echo 0)
    tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null || echo 0)
    local rx_kb=$(( (rx2 - rx1) / 1024 ))
    local tx_kb=$(( (tx2 - tx1) / 1024 ))
    echo "↓${rx_kb}K ↑${tx_kb}K"
}

_ip() {
    ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}'
}

while true; do
    cpu=$(_cpu)
    mem=$(_mem)
    net_iface=$(ip route | awk '/default/{print $5; exit}' 2>/dev/null)
    ip_addr=$(_ip)
    printf " %s  |  %s  |  NET: %s [%s]  |  %s \n" \
        "$cpu" "$mem" "${net_iface:-none}" "${ip_addr:----}" \
        "$(date +'%a %d %b  %H:%M:%S')"
    sleep 0.8
done

#!/bin/bash
#######################################################################
# packet_probe.sh — ThatThingOS fast network recon & packet probe
# Tools used: nmap, tshark, netcat, curl
# Must be run as root for raw socket capture
#######################################################################
set -euo pipefail

C='\033[36m'; Y='\033[33m'; G='\033[32m'; R='\033[31m'; W='\033[0m'; B='\033[1m'

banner() {
    echo -e "${C}${B}"
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║   ThatThingOS // PACKET_PROBE v1.0        ║"
    echo "  ╚═══════════════════════════════════════════╝"
    echo -e "${W}"
}

die() { echo -e "${R}[!] $*${W}" >&2; exit 1; }
log() { echo -e "${C}[*] $*${W}"; }
ok()  { echo -e "${G}[+] $*${W}"; }
warn(){ echo -e "${Y}[~] $*${W}"; }

# ── Dependency check ──────────────────────────────────────────────────
need() { command -v "$1" &>/dev/null || die "$1 not found. apt/apk install $1"; }

banner

# ── Mode selection ────────────────────────────────────────────────────
echo -e "${B}Select mode:${W}"
echo "  1) Quick host discovery (local subnet)"
echo "  2) Port scan target"
echo "  3) Live tshark capture (30s)"
echo "  4) HTTP banner grab"
echo "  5) ARP sweep"
echo ""
read -rp "Mode [1-5]: " MODE

case "$MODE" in

# ── 1: Host discovery ─────────────────────────────────────────────────
1)
    need nmap
    iface=$(ip route | awk '/default/{print $5; exit}')
    subnet=$(ip -o -f inet addr show "$iface" | awk '{print $4}')
    log "Discovering hosts on $subnet via $iface..."
    sudo nmap -sn -T4 --open "$subnet" -oG - \
        | awk '/Up$/{print $2}' \
        | while read -r host; do
            hostname=$(nmap -sn "$host" 2>/dev/null | grep "report for" | awk '{print $NF}')
            ok "$host  $hostname"
        done
    ;;

# ── 2: Port scan ──────────────────────────────────────────────────────
2)
    need nmap
    read -rp "Target IP/hostname: " TARGET
    read -rp "Port range [default: 1-1024]: " PORTS
    PORTS=${PORTS:-1-1024}
    log "Scanning $TARGET ports $PORTS..."
    sudo nmap -sV -T4 --open -p "$PORTS" "$TARGET" \
        | grep -E "^[0-9]+|Nmap scan|PORT|Service"
    ;;

# ── 3: Live tshark capture ────────────────────────────────────────────
3)
    need tshark
    iface=$(ip route | awk '/default/{print $5; exit}')
    OUTFILE="/tmp/thatthing_cap_$(date +%s).pcap"
    log "Capturing on $iface for 30s → $OUTFILE"
    sudo tshark -i "$iface" -a duration:30 -w "$OUTFILE" \
        -T fields \
        -e frame.time_relative \
        -e ip.src \
        -e ip.dst \
        -e _ws.col.Protocol \
        -e _ws.col.Info \
        -E separator='|' 2>/dev/null \
    || sudo tshark -i "$iface" -a duration:30 -w "$OUTFILE"
    ok "Saved: $OUTFILE  ($(du -h "$OUTFILE" | cut -f1))"
    ;;

# ── 4: HTTP banner grab ───────────────────────────────────────────────
4)
    read -rp "Target [host:port]: " TARGET
    HOST=${TARGET%%:*}; PORT=${TARGET##*:}; PORT=${PORT:-80}
    log "Grabbing HTTP banner from $HOST:$PORT..."
    echo -e "HEAD / HTTP/1.0\r\nHost: $HOST\r\n\r\n" \
        | timeout 5 nc "$HOST" "$PORT" 2>/dev/null \
        | head -20 \
        || warn "No response or timeout"
    ;;

# ── 5: ARP sweep ──────────────────────────────────────────────────────
5)
    need nmap
    iface=$(ip route | awk '/default/{print $5; exit}')
    subnet=$(ip -o -f inet addr show "$iface" | awk '{print $4}')
    log "ARP sweep on $subnet..."
    sudo nmap -PR -sn -T5 "$subnet" \
        | grep -E "report|MAC" \
        | paste - -
    ;;

*)
    die "Invalid mode."
    ;;
esac

echo ""
ok "Done. // ThatThingOS"

#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 00: Shared Environment & Tooling
# Source this file from all other build modules.
########################################################################

# ── Paths ─────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
OUT_DIR="$ROOT_DIR/out"
SCRIPTS_DIR="$ROOT_DIR/scripts"
INITRAMFS_DIR="$ROOT_DIR/initramfs"
ISO_NAME="thatthing-os-$(date +%Y%m%d).iso"

# ── Target Hardware Constants ─────────────────────────────────────────
# Dell Latitude Sandy Bridge — i5-2430M/2520M, Intel HD 3000
# 4GB DDR3 RAM, 320GB HDD, broken eDP-1
TARGET_ARCH="x86_64"
SQFS_ZSTD_LEVEL=15        # Level 15: sweet spot for i5-2430M decompression speed
SQFS_BLOCK_SIZE="262144"  # 256K blocks — faster random reads vs 1M

# ── FIX #1: OOM Guard — Auto-detect GitHub Actions ───────────────────
# GitHub Actions runners: ~7GB RAM total (~6GB usable after OS overhead).
# mksquashfs with -mem 12G on a 7GB machine → guaranteed OOM kill.
# Local MSI host (16GB): keep full 12G budget for faster compression.
if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
    HOST_MEM_SQFS="4G"    # CI: conservative — leaves ~2G headroom for Docker
    warn() { echo -e "\033[33m[ WARN]\033[0m $*"; }  # pre-declare for early use
    echo "[ENV] GitHub Actions detected — HOST_MEM_SQFS capped to 4G (OOM prevention)"
else
    HOST_MEM_SQFS="12G"   # Local 16GB host: exploit full build machine memory
fi

# Kernel cmdline display fix: disable broken eDP-1 and LVDS-1 panels
DISPLAY_FIX="video=eDP-1:d video=LVDS-1:d"

# Persistence HDD label (ext4 partition on /dev/sda)
PERSIST_LABEL="THATHING_DATA"

# ── Colors ────────────────────────────────────────────────────────────
C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'
W='\033[0m';  B='\033[1m';  M='\033[35m'

# ── Logging ───────────────────────────────────────────────────────────
log()  { echo -e "${C}${B}[BUILD]${W} $*"; }
ok()   { echo -e "${G}[  OK ]${W} $*"; }
warn() { echo -e "${Y}[ WARN]${W} $*"; }
die()  { echo -e "${R}[FATAL]${W} $*" >&2; exit 1; }
step() { echo -e "\n${M}${B}━━━ $* ━━━${W}"; }

# ── Dependency checker ────────────────────────────────────────────────
check_deps() {
    log "Checking host build tools..."
    mkdir -p "$OUT_DIR" "$BUILD_DIR"

    local required=(docker cpio find xorriso mksquashfs unsquashfs \
                    busybox grub-mkstandalone mcopy mmd mkfs.fat rsync \
                    blkid gzip xz)
    local missing=()
    for cmd in "${required[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if [ ${#missing[@]} -gt 0 ]; then
        die "Missing host tools: ${missing[*]}
  Install: sudo pacman -S squashfs-tools mtools dosfstools grub syslinux rsync"
    fi

    ok "All host tools present."
}

# ── Banner ─────────────────────────────────────────────────────────────
print_header() {
    clear
    echo -e "${C}${B}"
    cat <<'ASCII'
  ████████╗██╗  ██╗ █████╗ ████████╗████████╗██╗  ██╗██╗███╗   ██╗ ██████╗
  ╚══██╔══╝██║  ██║██╔══██╗╚══██╔══╝╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝
     ██║   ███████║███████║   ██║      ██║   ███████║██║██╔██╗ ██║██║  ███╗
     ██║   ██╔══██║██╔══██║   ██║      ██║   ██╔══██║██║██║╚██╗██║██║   ██║
     ██║   ██║  ██║██║  ██║   ██║      ██║   ██║  ██║██║██║ ╚████║╚██████╔╝
     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝
         >> v3.0 "RAM SOVEREIGN" — Target: Dell Latitude / 4GB DDR3 <<
ASCII
    echo -e "${W}"
}

#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Build Orchestrator
# Target: Dell Latitude (i5-2430M/2520M, 4GB DDR3, 320GB HDD)
# Strategy: Boot-to-RAM + Hybrid Overlay + Lazy HDD Sync
#
# Usage:
#   ./build.sh              # full build (all stages)
#   ./build.sh kernel       # kernel only
#   ./build.sh initramfs    # initramfs only
#   ./build.sh squashfs     # squashfs only
#   ./build.sh overlays     # overlay injection only
#   ./build.sh iso          # ISO assembly only
#   ./build.sh from=N       # run stages N..5 (e.g. from=3 = squashfs onward)
########################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_MODULES="$SCRIPT_DIR/build"

# Source shared env (for print_header, die, etc.)
# shellcheck source=build/00-env.sh
source "$BUILD_MODULES/00-env.sh"

# ── Argument parsing ─────────────────────────────────────────────────
STAGE_START=1
STAGE_END=5
SINGLE_STAGE=""

case "${1:-all}" in
    all)          ;;
    kernel)       SINGLE_STAGE=1 ;;
    initramfs)    SINGLE_STAGE=2 ;;
    squashfs)     SINGLE_STAGE=3 ;;
    overlays)     SINGLE_STAGE=4 ;;
    iso)          SINGLE_STAGE=5 ;;
    from=*)       STAGE_START="${1#from=}" ;;
    -h|--help)
        echo "Usage: $0 [all|kernel|initramfs|squashfs|overlays|iso|from=N]"
        exit 0 ;;
    *)
        die "Unknown argument: $1. Use: $0 --help" ;;
esac

[ -n "$SINGLE_STAGE" ] && STAGE_START="$SINGLE_STAGE" && STAGE_END="$SINGLE_STAGE"

# ── Validate build module files ──────────────────────────────────────
for mod in 00-env 01-kernel 02-initramfs 03-squashfs 04-overlays 05-iso; do
    [ -f "$BUILD_MODULES/${mod}.sh" ] || die "Missing build module: $BUILD_MODULES/${mod}.sh"
done

# ── Header ───────────────────────────────────────────────────────────
print_header
echo -e "${Y}  Build stages: $STAGE_START → $STAGE_END${W}"
echo -e "${Y}  ISO: $ISO_NAME${W}"
echo ""

check_deps

# ── Stage runner ─────────────────────────────────────────────────────
run_stage() {
    local num="$1"
    local name="$2"
    local script="$3"

    if [ "$num" -lt "$STAGE_START" ] || [ "$num" -gt "$STAGE_END" ]; then
        return
    fi

    log "Starting stage $num/$STAGE_END: $name"
    bash "$script"
    ok "Stage $num complete: $name"
    echo ""
}

# ── Execute stages ───────────────────────────────────────────────────
run_stage 1 "Kernel Build (CachyOS BORE, Sandy Bridge)"  "$BUILD_MODULES/01-kernel.sh"
run_stage 2 "Initramfs (copytoram + hybrid overlay init)"  "$BUILD_MODULES/02-initramfs.sh"
run_stage 3 "SquashFS RootFS (Alpine stripped, ZSTD-15)"   "$BUILD_MODULES/03-squashfs.sh"
run_stage 4 "Overlay Injection (lazy-sync, TUI, services)" "$BUILD_MODULES/04-overlays.sh"
run_stage 5 "ISO Assembly (Hybrid BIOS+UEFI)"              "$BUILD_MODULES/05-iso.sh"

# ── Cleanup ──────────────────────────────────────────────────────────
log "Pruning dangling Docker images..."
docker image prune -f > /dev/null 2>&1 || true

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo -e "${G}${B}╔══════════════════════════════════════════════════════════╗${W}"
echo -e "${G}${B}║         ThatThingOS v3.0 BUILD COMPLETE                  ║${W}"
echo -e "${G}${B}╠══════════════════════════════════════════════════════════╣${W}"
echo -e "${G}${B}║  ISO: out/$ISO_NAME${W}"
if [ -f "$OUT_DIR/$ISO_NAME" ]; then
    SZ=$(du -sh "$OUT_DIR/$ISO_NAME" | cut -f1)
    SHA=$(sha256sum "$OUT_DIR/$ISO_NAME" | cut -d' ' -f1)
    echo -e "${G}${B}║  Size: $SZ${W}"
    echo -e "${G}${B}║  SHA256: ${SHA:0:32}...${W}"
fi
echo -e "${G}${B}╠══════════════════════════════════════════════════════════╣${W}"
echo -e "${G}${B}║  Runtime Architecture:                                   ║${W}"
echo -e "${G}${B}║  [SquashFS→RAM] → [RAM overlay] → [HDD lazy sync]        ║${W}"
echo -e "${G}${B}║  Display fix: video=eDP-1:d video=LVDS-1:d active        ║${W}"
echo -e "${G}${B}║  First-boot TUI: runs on tty1 (external monitor)         ║${W}"
echo -e "${G}${B}╚══════════════════════════════════════════════════════════╝${W}"
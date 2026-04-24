#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 04: Overlay & Service Injection
#
# Takes the raw SquashFS, unsquashes it, injects:
#   - lazy-sync OpenRC service
#   - 99-shutdown-sync.stop (local.d shutdown hook)
#   - first-boot-tui.sh + its OpenRC trigger
#   - 10-first-boot.start (OpenRC local.d trigger)
#   - Any scripts from $SCRIPTS_DIR
# Then re-squashes with the same ZSTD-15 / 256K settings.
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

apply_overlays() {
    step "Applying Overlays & Injecting Services"

    local SQFS_FILE
    SQFS_FILE=$(cat "$BUILD_DIR/sqfs_path.txt")
    [ -f "$SQFS_FILE" ] || die "SquashFS not found: $SQFS_FILE"

    local UNSQUASH_DIR="$BUILD_DIR/squash_rw"
    local FINAL_SQF="$BUILD_DIR/rootfs_final.img"

    log "Unsquashing rootfs..."
    sudo rm -rf "$UNSQUASH_DIR"
    sudo unsquashfs -d "$UNSQUASH_DIR" "$SQFS_FILE" > /dev/null

    # ── Kernel modules ─────────────────────────────────────────────────
    if [ -f "$BUILD_DIR/kernel_ready.txt" ] && [ -d "$BUILD_DIR/out_kernel/lib/modules" ]; then
        log "Injecting kernel modules..."
        sudo mkdir -p "$UNSQUASH_DIR/lib/modules"
        sudo cp -a "$BUILD_DIR/out_kernel/lib/modules/"* "$UNSQUASH_DIR/lib/modules/"
    fi

    # ── Kernel image placeholder (for mkinitrd in userspace, optional) ─
    if [ -f "$BUILD_DIR/out_kernel/boot/vmlinuz-thatthing" ]; then
        sudo cp "$BUILD_DIR/out_kernel/boot/vmlinuz-thatthing" \
            "$UNSQUASH_DIR/boot/vmlinuz-thatthing" 2>/dev/null || true
    fi

    # ── lazy-sync OpenRC service ───────────────────────────────────────
    log "Installing lazy-sync service..."
    sudo install -Dm 755 \
        "$SCRIPTS_DIR/lazy-sync" \
        "$UNSQUASH_DIR/etc/init.d/lazy-sync"
    # Enable at default runlevel
    sudo mkdir -p "$UNSQUASH_DIR/etc/runlevels/default"
    sudo ln -sf /etc/init.d/lazy-sync \
        "$UNSQUASH_DIR/etc/runlevels/default/lazy-sync" 2>/dev/null || true

    # ── Shutdown sync (OpenRC local.d) ────────────────────────────────
    log "Installing shutdown sync hook..."
    sudo mkdir -p "$UNSQUASH_DIR/etc/local.d"
    sudo install -Dm 755 \
        "$SCRIPTS_DIR/99-shutdown-sync.stop" \
        "$UNSQUASH_DIR/etc/local.d/99-shutdown-sync.stop"
    # Ensure local service is enabled
    sudo ln -sf /etc/init.d/local \
        "$UNSQUASH_DIR/etc/runlevels/default/local" 2>/dev/null || true

    # ── First-boot TUI ────────────────────────────────────────────────
    log "Installing first-boot TUI..."
    sudo install -Dm 755 \
        "$SCRIPTS_DIR/first-boot-tui.sh" \
        "$UNSQUASH_DIR/usr/local/bin/first-boot-tui.sh"

    # OpenRC local.d trigger for first-boot TUI
    # FIX #3: Check if /media/persist is mounted before reading flag.
    # Without this, if the HDD is slow/absent, the flag file is never found
    # and the TUI runs on EVERY boot (infinite loop).
    sudo tee "$UNSQUASH_DIR/etc/local.d/10-first-boot.start" > /dev/null <<'FBEOF'
#!/bin/sh
# ThatThingOS: First boot wizard trigger
PERSIST_MNT="/media/persist"
FLAG="$PERSIST_MNT/.first-boot-done"

# ── Step 1: Mount persistence partition ──────────────────────────────────────
if ! mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
    mkdir -p "$PERSIST_MNT"
    # Try label-based mount first (robust against /dev node reordering)
    if ! mount -L THATHING_DATA "$PERSIST_MNT" -o rw,relatime 2>/dev/null; then
        PERSIST_DEV=$(cat /run/thatthing-persist-dev 2>/dev/null || true)
        if [ -n "$PERSIST_DEV" ]; then
            mount -o rw,relatime "$PERSIST_DEV" "$PERSIST_MNT" 2>/dev/null || true
        fi
    fi
fi

# ── Step 2: Wait-loop for slow/spinning HDDs ─────────────────────────────────
# Race condition fix: on 5400 RPM drives the partition may not be accessible
# immediately after boot. Wait up to 8 seconds before giving up.
_waited=0
while [ "$_waited" -lt 8 ]; do
    if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
        break
    fi
    # Retry mount every second while waiting
    mount -L THATHING_DATA "$PERSIST_MNT" -o rw,relatime 2>/dev/null || true
    sleep 1
    _waited=$(( _waited + 1 ))
done

# ── Step 3: Check flag — only skip TUI when BOTH conditions are true ──────────
if mountpoint -q "$PERSIST_MNT" 2>/dev/null && [ -f "$FLAG" ]; then
    exit 0
fi

# Run on tty1 — visible on external monitor
openvt -c 1 -w -- /usr/local/bin/first-boot-tui.sh
FBEOF
    sudo chmod 755 "$UNSQUASH_DIR/etc/local.d/10-first-boot.start"

    # ── Runtime scripts from repo ─────────────────────────────────────
    if [ -d "$SCRIPTS_DIR" ]; then
        log "Copying runtime scripts..."
        for f in "$SCRIPTS_DIR"/*.sh; do
            [ -f "$f" ] || continue
            sudo install -Dm 755 "$f" \
                "$UNSQUASH_DIR/usr/local/bin/$(basename "$f")"
        done
    fi

    # ── /etc/issue branding ───────────────────────────────────────────
    sudo tee "$UNSQUASH_DIR/etc/issue" > /dev/null <<'ISSUE'

  ████████╗██╗  ██╗ █████╗ ████████╗████████╗██╗  ██╗██╗███╗   ██╗ ██████╗
     ██║   ███████║███████║   ██║      ██║   ███████║██║██╔██╗ ██║██║  ███╗
     ██║   ██╔══██║██╔══██║   ██║      ██║   ██╔══██║██║██║╚██╗██║██║   ██║
     ██║   ██║  ██║██║  ██║   ██║      ██║   ██║  ██║██║██║ ╚████║╚██████╔╝
  v3.0 "RAM SOVEREIGN" | Login: thatthing | \n \l

ISSUE

    # ── wpa_supplicant config dir ────────────────────────────────────
    sudo mkdir -p "$UNSQUASH_DIR/etc/wpa_supplicant"
    sudo tee "$UNSQUASH_DIR/etc/wpa_supplicant/wpa_supplicant.conf" > /dev/null <<'WPAEOF'
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
WPAEOF
    sudo chmod 600 "$UNSQUASH_DIR/etc/wpa_supplicant/wpa_supplicant.conf"

    # ── Re-squash with same settings ────────────────────────────────────
    # FIX #2: -all-root normalizes file ownership.
    # Any scripts injected above (uid=1001 from CI runner, uid=1000 from dev)
    # become root:root inside the squashfs. Critical for /etc/init.d/*, sudoers.
    log "Re-squashing with ZSTD-15 / 256K blocks (mem=$HOST_MEM_SQFS)..."
    sudo mksquashfs "$UNSQUASH_DIR" "$FINAL_SQF" \
        -comp zstd \
        -Xcompression-level "$SQFS_ZSTD_LEVEL" \
        -b "$SQFS_BLOCK_SIZE" \
        -mem "$HOST_MEM_SQFS" \
        -all-root \
        -no-progress \
        -noappend \
        > /dev/null

    echo "$FINAL_SQF" > "$BUILD_DIR/final_sqfs_path.txt"
    local sz
    sz=$(du -sh "$FINAL_SQF" | cut -f1)
    ok "Final SquashFS: $FINAL_SQF ($sz)"
}

apply_overlays

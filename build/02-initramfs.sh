#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 02: Initramfs Builder
# Bundles the initramfs/init with busybox, kernel modules, and tools
# needed for: copytoram, overlayfs, ZRAM, block device detection
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

build_initramfs() {
    step "Building Initramfs (copytoram + hybrid overlay)"

    local CPIO_TMP="$BUILD_DIR/initramfs_root"
    local OUT_CPIO="$BUILD_DIR/initramfs.img"

    rm -rf "$CPIO_TMP"
    mkdir -p "$CPIO_TMP"/{bin,sbin,lib,lib64,lib/modules,\
dev,proc,sys,tmp,run,newroot,\
live_medium,live_squash,.persist}

    # ── Busybox (static) ──────────────────────────────────────────────
    local bb
    bb=$(command -v busybox)
    # Prefer static busybox for maximum portability
    [ -f /usr/lib/busybox/busybox-static ] && bb=/usr/lib/busybox/busybox-static
    cp "$bb" "$CPIO_TMP/bin/busybox"

    local tools="sh ash mount umount mkdir cat ls blkid lsblk parted \
                 modprobe switch_root sleep mknod awk grep sed find stat \
                 cp mv rm ln echo printf read swapon mkswap free"
    for tool in $tools; do
        ln -sf busybox "$CPIO_TMP/bin/$tool" 2>/dev/null || true
    done

    # ── init script ───────────────────────────────────────────────────
    cp "$INITRAMFS_DIR/init" "$CPIO_TMP/init"
    chmod 755 "$CPIO_TMP/init"

    # ── Kernel modules (squashfs, overlay, zram, i915, loop) ─────────
    if [ -d "$BUILD_DIR/out_kernel/lib/modules" ]; then
        log "Copying kernel modules to initramfs..."
        cp -a "$BUILD_DIR/out_kernel/lib/modules" "$CPIO_TMP/lib/"
    else
        warn "No kernel modules found — initramfs will rely on host modules."
    fi

    # ── e2fsck / resize2fs (needed if persistence partition creation) ─
    for tool in e2fsck resize2fs mkfs.ext4 partprobe blockdev; do
        local p
        p=$(command -v "$tool" 2>/dev/null || true)
        [ -n "$p" ] && cp "$p" "$CPIO_TMP/sbin/$tool" || true
    done

    # ── rsync for shutdown-sync (small static build not available in initramfs;
    #    we only need it in userspace. Skip here.) ─────────────────────

    # Pack with gzip (faster decompress on i5-2430M than XZ)
    log "Packing initramfs (gzip)..."
    ( cd "$CPIO_TMP" && find . | cpio -oH newc 2>/dev/null ) | gzip -6 > "$OUT_CPIO"

    local sz
    sz=$(du -sh "$OUT_CPIO" | cut -f1)
    ok "Initramfs ready: $OUT_CPIO ($sz)"
}

build_initramfs

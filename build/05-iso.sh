#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 05: ISO Assembly
#
# Output: Hybrid BIOS (Isolinux) + UEFI (GRUB2) ISO
# Kernel cmdline includes:
#   - copytoram=y           → load squashfs to RAM
#   - video=eDP-1:d         → disable broken internal eDP panel
#   - video=LVDS-1:d        → disable broken LVDS panel
#   - mitigations=off       → +~10% perf on Sandy Bridge (known CVEs acceptable
#                              for single-user, air-gapped use)
#   - zswap.enabled=0       → ZRAM is used instead (avoids double-compression)
#   - quiet loglevel=3      → hide boot noise (TUI startup is cleaner)
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

assemble_iso() {
    step "Assembling Hybrid ISO (BIOS + UEFI)"

    local SQF
    SQF=$(cat "$BUILD_DIR/final_sqfs_path.txt")
    [ -f "$SQF" ] || die "Final squashfs not found: $SQF"

    local KERNEL="$BUILD_DIR/out_kernel/boot/vmlinuz-thatthing"
    [ -f "$KERNEL" ] || die "Kernel not found: $KERNEL"

    local INITRAMFS="$BUILD_DIR/initramfs.img"
    [ -f "$INITRAMFS" ] || die "Initramfs not found: $INITRAMFS"

    local ISO_ROOT="$BUILD_DIR/iso_root"
    local OUT_ISO="$OUT_DIR/$ISO_NAME"

    rm -rf "$ISO_ROOT"
    mkdir -p "$ISO_ROOT"/{boot/isolinux,LiveOS,EFI/BOOT,boot/grub}

    # ── Copy payloads ─────────────────────────────────────────────────
    cp "$SQF"        "$ISO_ROOT/LiveOS/rootfs.img"
    cp "$INITRAMFS"  "$ISO_ROOT/boot/initramfs.img"
    cp "$KERNEL"     "$ISO_ROOT/boot/vmlinuz"

    local SQF_SIZE KERNEL_SIZE INIT_SIZE
    SQF_SIZE=$(du -sh "$SQF" | cut -f1)
    KERNEL_SIZE=$(du -sh "$KERNEL" | cut -f1)
    INIT_SIZE=$(du -sh "$INITRAMFS" | cut -f1)
    log "Payloads: squashfs=$SQF_SIZE kernel=$KERNEL_SIZE initramfs=$INIT_SIZE"

    # ── Shared kernel cmdline ──────────────────────────────────────────
    # DISPLAY_FIX is sourced from 00-env.sh
    local KCMD="quiet loglevel=3 copytoram=y ${DISPLAY_FIX} mitigations=off zswap.enabled=0 zram.num_devices=1 net.ifnames=0 biosdevname=0 pci=noaer"

    # ── BIOS Boot — Isolinux ──────────────────────────────────────────
    local ISOLINUX_BIN=""
    for p in /usr/lib/syslinux/bios /usr/lib/syslinux; do
        [ -f "$p/isolinux.bin" ] && ISOLINUX_BIN="$p" && break
    done
    [ -z "$ISOLINUX_BIN" ] && die "isolinux.bin not found. Install syslinux."

    cp "$ISOLINUX_BIN/isolinux.bin" "$ISO_ROOT/boot/isolinux/"
    cp "$ISOLINUX_BIN/ldlinux.c32"  "$ISO_ROOT/boot/isolinux/"
    # Optional: copy menu.c32 for prettier menu
    [ -f "$ISOLINUX_BIN/menu.c32"   ] && cp "$ISOLINUX_BIN/menu.c32"   "$ISO_ROOT/boot/isolinux/" || true
    [ -f "$ISOLINUX_BIN/libutil.c32"] && cp "$ISOLINUX_BIN/libutil.c32" "$ISO_ROOT/boot/isolinux/" || true

    cat > "$ISO_ROOT/boot/isolinux/isolinux.cfg" <<EOF
UI menu.c32
PROMPT 0
TIMEOUT 30
DEFAULT thatthing

LABEL thatthing
  MENU LABEL ThatThingOS v3.0 (RAM mode)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img ${KCMD}
  TEXT HELP
  Ultra-low-spec build — boots 100%% from RAM. HDD is lazy-synced.
  ENDTEXT

LABEL thatthing-safe
  MENU LABEL ThatThingOS v3.0 (safe mode — no mitigations=off)
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initramfs.img quiet loglevel=3 copytoram=y ${DISPLAY_FIX}
EOF

    # ── UEFI Boot — GRUB2 ─────────────────────────────────────────────
    cat > "$ISO_ROOT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=3
set timeout_style=menu
set gfxmode=auto
set gfxpayload=keep

menuentry "ThatThingOS v3.0 — RAM Sovereign" --id thatthing {
    echo "Loading ThatThingOS v3.0..."
    linux  /boot/vmlinuz ${KCMD}
    initrd /boot/initramfs.img
}

menuentry "ThatThingOS v3.0 — Safe Mode" --id thatthing-safe {
    linux  /boot/vmlinuz quiet loglevel=3 copytoram=y ${DISPLAY_FIX}
    initrd /boot/initramfs.img
}

menuentry "Boot from local disk" --id local {
    exit
}
EOF

    # Embed grub.cfg into EFI image
    grub-mkstandalone \
        -O x86_64-efi \
        -o "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" \
        "boot/grub/grub.cfg=$ISO_ROOT/boot/grub/grub.cfg"

    # EFI FAT image (for El Torito EFI boot)
    local EFI_IMG="$BUILD_DIR/efiboot.img"
    truncate -s 16M "$EFI_IMG"
    mkfs.fat -F32 -n "THATTHINGEFI" "$EFI_IMG" > /dev/null
    mmd  -i "$EFI_IMG" ::/EFI ::/EFI/BOOT
    mcopy -i "$EFI_IMG" "$ISO_ROOT/EFI/BOOT/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI

    # ── xorriso — hybrid ISO assembly ─────────────────────────────────
    log "Running xorriso..."
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "THATTHING_OS" \
        -preparer "ThatThingOS v3.0 Build System" \
        -publisher "ThatThingOS" \
        -b boot/isolinux/isolinux.bin \
        -c boot/isolinux/boot.cat \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/efiboot.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -output "$OUT_ISO" \
        -graft-points \
            "$ISO_ROOT" \
            /boot/efiboot.img="$EFI_IMG" \
        2>/dev/null

    local iso_sz
    iso_sz=$(du -sh "$OUT_ISO" | cut -f1)
    ok "ISO COMPLETE: $OUT_ISO ($iso_sz)"
    echo ""
    echo -e "${G}${B}  SHA256: $(sha256sum "$OUT_ISO" | cut -d' ' -f1)${W}"
}

assemble_iso

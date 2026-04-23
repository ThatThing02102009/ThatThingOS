#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Quick-Patch Helper
#
# Dùng để sửa nhanh SquashFS mà không cần build lại toàn bộ.
# Lưu ý: script này chỉ dùng LOCAL, KHÔNG chạy trong CI.
#
# SECURITY NOTE: Không hardcode path chứa tên user cá nhân.
# Truyền ISO path qua biến hoặc argument.
########################################################################
set -euo pipefail

# ── Config ─────────────────────────────────────────────────────────────
# Dùng biến môi trường thay vì hardcode path cá nhân
ISO_IN="${THATTHING_ISO_PATH:-out/thatthing-os-$(date +%Y%m%d).iso}"
WORKING_DIR="${THATTHING_PATCH_WORKDIR:-./patch_work}"

if [ ! -f "$ISO_IN" ]; then
    echo "[ERROR] ISO not found: $ISO_IN"
    echo "  Set THATTHING_ISO_PATH env var, e.g.:"
    echo "    export THATTHING_ISO_PATH=out/thatthing-os-cachyos-20260422.iso"
    exit 1
fi

mkdir -p "$WORKING_DIR"

# 1. Xả nén SquashFS từ ISO
#    Bạn cần mount ISO trước hoặc dùng 7z để extract rootfs.img:
#    sudo mount -o loop "$ISO_IN" /mnt/iso
#    cp /mnt/iso/LiveOS/rootfs.img "$WORKING_DIR/"
echo "[*] Unsquashing rootfs.img from $WORKING_DIR/rootfs.img ..."
unsquashfs -d "$WORKING_DIR/rootfs_extracted" "$WORKING_DIR/rootfs.img"

# 2. Sửa gì thì sửa ở đây...
# Ví dụ: nano $WORKING_DIR/rootfs_extracted/usr/local/bin/setup-persistence.sh
echo "[*] rootfs extracted to $WORKING_DIR/rootfs_extracted — make your changes now."
echo "    Press Enter when done to re-squash..."
read -r _

# 3. Đóng gói lại SquashFS
# FIX #2: thêm -all-root để normalize ownership (quan trọng khi inject file từ host)
# FIX #1: dùng level 15 (nhất quán với settings production) thay vì 22
echo "[*] Re-squashing..."
mksquashfs "$WORKING_DIR/rootfs_extracted" "$WORKING_DIR/rootfs_new.img" \
    -comp zstd \
    -Xcompression-level 15 \
    -b 262144 \
    -all-root \
    -noappend

echo "[+] Done: $WORKING_DIR/rootfs_new.img"
echo "    Copy rootfs_new.img vào ISO và re-assemble (bước 05-iso.sh)"
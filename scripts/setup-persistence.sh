#!/bin/bash
# /usr/local/bin/setup-persistence.sh
# HDD Persistence Setup — Interactive, safe-by-default.
#
# SAFETY RULES:
#   1. Never touches a disk without explicit user confirmation.
#   2. Never formats a partition that already has the THATTHING_SAVE label.
#   3. Requires >4GB of free space on the chosen device to create a new partition.
#
# Usage:
#   setup-persistence.sh           → Full interactive mode
#   setup-persistence.sh --auto    → Non-interactive (CI / first-boot fallback)
#
set -euo pipefail

LABEL="THATTHING_SAVE"
PERSIST_MNT="/media/persistence"
AUTO_MODE=0
[ "${1-}" = "--auto" ] && AUTO_MODE=1

mkdir -p "$PERSIST_MNT"

###############################################################################
# Phase 1: Check if the labeled partition already exists
###############################################################################
DEV=$(blkid -L "$LABEL" 2>/dev/null || true)

if [ -n "$DEV" ] && [ -b "$DEV" ]; then
    echo "[OK] Found existing persistence partition: $DEV (label=$LABEL)"
    echo "     Skipping format — existing data is preserved."
else
    ###########################################################################
    # Phase 2: No partition found — guide user to create one
    ###########################################################################
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────┐"
    echo "│  ThatThingOS — Persistence Setup                                 │"
    echo "│                                                                   │"
    echo "│  No partition with label '$LABEL' was detected.         │"
    echo "│  A 4GB ext4 partition will be created for saving your data.      │"
    echo "└──────────────────────────────────────────────────────────────────┘"
    echo ""

    # List available block devices for the user to choose from
    echo "Available block devices:"
    echo "──────────────────────────────────────────────────────────────────"
    lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "disk" || lsblk -d -o NAME,SIZE,TYPE
    echo "──────────────────────────────────────────────────────────────────"
    echo ""
    echo "WARNING: This script will create a new partition."
    echo "         Existing partitions and data will NOT be touched."
    echo ""

    # ── Device selection ──────────────────────────────────────────────────
    if [ "$AUTO_MODE" -eq 1 ]; then
        # Auto mode: pick the first non-Ventoy physical disk
        TARGET_DISK=""
        for d in /dev/nvme0n1 /dev/sda /dev/vda /dev/sdb; do
            if [ -b "$d" ] && ! blkid "$d"* 2>/dev/null | grep -qi "ventoy"; then
                TARGET_DISK="$d"
                break
            fi
        done
        if [ -z "$TARGET_DISK" ]; then
            echo "[!] Auto mode: No suitable disk found. Skipping persistence."
            exit 0
        fi
        echo "[AUTO] Selected disk: $TARGET_DISK"
    else
        # Interactive mode: ask the user
        printf "Enter the target disk device (e.g. /dev/sda): "
        read -r TARGET_DISK
        TARGET_DISK="${TARGET_DISK:-}"
    fi

    # ── Validate input ────────────────────────────────────────────────────
    if [ -z "$TARGET_DISK" ] || [ ! -b "$TARGET_DISK" ]; then
        echo "[!] Invalid device: '$TARGET_DISK'. Aborting to protect your data."
        exit 1
    fi

    # Guard: refuse to operate on the Ventoy live USB
    if blkid "${TARGET_DISK}"* 2>/dev/null | grep -qi "ventoy"; then
        echo "[!] '$TARGET_DISK' appears to be your Ventoy boot drive. Refusing to partition it."
        exit 1
    fi

    # ── Locate free space ─────────────────────────────────────────────────
    echo "[*] Scanning $TARGET_DISK for unallocated space (≥4GB required)..."
    FREE_SECTOR=$(parted -ms "$TARGET_DISK" unit MB print free 2>/dev/null \
        | awk -F: '/free;/{print}' | tail -n1 || true)

    if [ -z "$FREE_SECTOR" ]; then
        echo "[!] No free space found on $TARGET_DISK. Aborting."
        exit 1
    fi

    START_MB=$(echo "$FREE_SECTOR" | cut -d':' -f2 | tr -d 'MB ')
    END_MB=$(echo   "$FREE_SECTOR" | cut -d':' -f3 | tr -d 'MB ')
    AVAILABLE_MB=$(awk "BEGIN {print int($END_MB - $START_MB)}")

    if [ "$AVAILABLE_MB" -lt 4000 ]; then
        echo "[!] Only ${AVAILABLE_MB}MB free on $TARGET_DISK (need ≥4000MB). Aborting."
        exit 1
    fi

    TARGET_END_MB=$(awk "BEGIN {print int($START_MB + 4000)}")

    # ── Final confirmation ────────────────────────────────────────────────
    echo ""
    echo "  About to create:"
    echo "    Device  : $TARGET_DISK"
    echo "    From    : ${START_MB}MB → ${TARGET_END_MB}MB"
    echo "    Size    : 4000MB ext4"
    echo "    Label   : $LABEL"
    echo ""

    if [ "$AUTO_MODE" -eq 0 ]; then
        printf "Type YES (uppercase) to confirm, or anything else to abort: "
        read -r CONFIRM
        if [ "$CONFIRM" != "YES" ]; then
            echo "[!] Cancelled by user. No changes made."
            exit 0
        fi
    fi

    # ── Create and format the partition ──────────────────────────────────
    echo "[*] Creating partition on $TARGET_DISK (${START_MB}MB → ${TARGET_END_MB}MB)..."
    parted -s "$TARGET_DISK" unit MB mkpart primary ext4 "${START_MB}" "${TARGET_END_MB}"

    # Let the kernel re-read the partition table
    partprobe "$TARGET_DISK" 2>/dev/null || sleep 3

    # Resolve the new partition device node
    NEW_PART_NUM=$(parted -ms "$TARGET_DISK" print 2>/dev/null | tail -n1 | cut -d':' -f1)
    if echo "$TARGET_DISK" | grep -q "nvme"; then
        DEV="${TARGET_DISK}p${NEW_PART_NUM}"
    else
        DEV="${TARGET_DISK}${NEW_PART_NUM}"
    fi

    echo "[*] Formatting $DEV as ext4 with label '$LABEL'..."
    mkfs.ext4 -L "$LABEL" -E lazy_itable_init=0,lazy_journal_init=0 "$DEV"
    echo "[+] Partition created: $DEV"
fi

###############################################################################
# Phase 3: Mount and set up overlay directories
###############################################################################
if [ -n "$DEV" ] && [ -b "$DEV" ]; then
    echo "[*] Mounting $DEV → $PERSIST_MNT ..."
    mount -o rw,relatime "$DEV" "$PERSIST_MNT"

    # Ensure overlay scaffold exists
    mkdir -p "$PERSIST_MNT/upper" "$PERSIST_MNT/work"

    TARGET_DIR="/home/thatthing"
    mkdir -p "$TARGET_DIR"

    echo "[*] Setting up OverlayFS on $TARGET_DIR ..."
    mount -t overlay overlay \
        -o "lowerdir=$TARGET_DIR,upperdir=$PERSIST_MNT/upper,workdir=$PERSIST_MNT/work" \
        "$TARGET_DIR"

    chown -R thatthing:thatthing "$TARGET_DIR" 2>/dev/null || true
    echo "[+] Persistence for $TARGET_DIR established."
else
    echo "[-] Running in pure Copy-to-RAM mode. User data will not survive reboot."
fi

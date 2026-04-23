#!/bin/bash
# /usr/local/bin/setup-persistence.sh
# HDD Jump Logic: Finds THATTHING_SAVE or creates it in 4GB unallocated space.
# Intended to be executed by OpenRC local.d
set -e

LABEL="THATTHING_SAVE"
PERSIST_MNT="/media/persistence"

mkdir -p "$PERSIST_MNT"

# Phase 1: Scan
DEV=$(blkid -L "$LABEL" || true)

# Phase 2: Creation (if not found in Phase 1)
if [ -z "$DEV" ]; then
    echo "[!] $LABEL not found. Searching for 4GB unallocated space on physical disks..."
    
    PRIMARY_DISK=""
    # Simple heuristic to find primary HDD (skipping Ventoy live media/CD-ROMs)
    for d in /dev/nvme0n1 /dev/sda /dev/vda /dev/sdb; do
        if [ -b "$d" ] && ! blkid "$d"* | grep -qi "ventoy"; then
            PRIMARY_DISK="$d"
            break
        fi
    done
    
    if [ -n "$PRIMARY_DISK" ]; then
        echo "[*] Selected $PRIMARY_DISK. Attempting to locate unallocated space..."
        
        # Extract last free block sequence start and end
        FREE_SECTOR=$(parted -ms "$PRIMARY_DISK" unit MB print free 2>/dev/null | grep "free;" | tail -n1 || true)
        
        if [ -n "$FREE_SECTOR" ]; then
            START_MB=$(echo "$FREE_SECTOR" | cut -d':' -f1 | tr -d 'MBs ')
            END_MB=$(echo "$FREE_SECTOR" | cut -d':' -f2 | tr -d 'MBs ')
            
            # Simple math using awk to handle floats safely
            AVAILABLE_MB=$(awk "BEGIN {print int($END_MB - $START_MB)}")
            
            if [ "$AVAILABLE_MB" -ge 4000 ]; then
                TARGET_END_MB=$(awk "BEGIN {print int($START_MB + 4000)}")
                
                echo "[*] Creating 4GB ext4 partition on $PRIMARY_DISK (${START_MB}MB -> ${TARGET_END_MB}MB)..."
                parted -s "$PRIMARY_DISK" unit MB mkpart primary ext4 "${START_MB}" "${TARGET_END_MB}"
                
                # Settle kernel changes
                partprobe "$PRIMARY_DISK" || sleep 2
                
                # Get the newly created partition (highest number)
                NEW_PART_NUM=$(parted -ms "$PRIMARY_DISK" print | tail -n1 | cut -d':' -f1)
                
                if echo "$PRIMARY_DISK" | grep -q "nvme"; then
                    DEV="${PRIMARY_DISK}p${NEW_PART_NUM}"
                else
                    DEV="${PRIMARY_DISK}${NEW_PART_NUM}"
                fi
                
                echo "[*] Formatting $DEV as ext4 Phase..."
                mkfs.ext4 -L "$LABEL" "$DEV"
            else
                echo "[!] Insufficient unallocated space ($AVAILABLE_MB MB). Requires >4000 MB."
            fi
        fi
    else
        echo "[!] No suitable primary disk found for automatic persistence."
    fi
fi

# Phase 3: Mount and Overlay (Targeting /home/thatthing)
if [ -n "$DEV" ] && [ -b "$DEV" ]; then
    echo "[*] Mounting $DEV to $PERSIST_MNT..."
    mount "$DEV" "$PERSIST_MNT"
    
    mkdir -p "$PERSIST_MNT/upper" "$PERSIST_MNT/work"
    
    TARGET_DIR="/home/thatthing"
    mkdir -p "$TARGET_DIR"
    
    echo "[*] Initiating OverlayFS on $TARGET_DIR..."
    # Lowerdir is the pristine RAM state of /home/thatthing (from the ISO)
    # Upperdir uses the Physical HDD (so it preserves your MC client + scripts instantly)
    mount -t overlay overlay -o lowerdir=$TARGET_DIR,upperdir=$PERSIST_MNT/upper,workdir=$PERSIST_MNT/work "$TARGET_DIR"
    
    # Correct permissions if it's the first time
    chown -R thatthing:thatthing "$TARGET_DIR"
    
    echo "[+] Persistence for $TARGET_DIR established."
else
    echo "[-] Running in pure Copy-to-RAM mode. User Data will evaporate."
fi

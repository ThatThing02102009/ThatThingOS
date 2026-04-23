#!/bin/bash
########################################################################
# ThatThingOS v3.0 — First-Boot TUI Setup
# File: /usr/local/bin/first-boot-tui.sh
#
# Runs ONCE on first boot if /media/persist/.first-boot-done is absent.
# Uses `dialog` for a terminal-based setup wizard.
#
# Configures:
#   1. Username + Password → /etc/shadow (persistent)
#   2. Timezone → Asia/Ho_Chi_Minh (default, user can change)
#   3. Locale → en_US.UTF-8
#   4. Wi-Fi → wpa_supplicant scan + connect
#
# Triggered by: /etc/local.d/10-first-boot.start (OpenRC local.d)
########################################################################
set -euo pipefail

PERSIST_MNT="/media/persist"
FLAG_FILE="$PERSIST_MNT/.first-boot-done"
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
TMP_PASS=$(mktemp)
TMP_WIFI=$(mktemp)

# Ensure we have a terminal
exec 1>/dev/tty1 2>/dev/tty1

cleanup() {
    rm -f "$TMP_PASS" "$TMP_WIFI"
    dialog --clear
}
trap cleanup EXIT

dialog_ok() {
    dialog --colors \
           --backtitle "\Zb\Z5ThatThingOS v3.0 — First Boot Setup\Zn" \
           "$@"
}

### ── Guard: skip if already done ───────────────────────────────────────
# FIX #3: Robust mount guard — Race Condition prevention
#
# Problem: if we just check [ -f "$FLAG" ] without verifying the mount,
# a slow HDD or missing partition causes the flag to never be found.
# Result: TUI launches on EVERY boot — infinite loop.
#
# Solution: try to mount /media/persist first, with retries and timeout.
# Only then check for the flag.
_ensure_persist_mounted() {
    if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
        return 0  # already mounted
    fi
    mkdir -p "$PERSIST_MNT"

    # Strategy 1: mount by label (works even if /dev node order changes)
    if mount -L "THATHING_DATA" "$PERSIST_MNT" -o rw,relatime 2>/dev/null; then
        return 0
    fi

    # Strategy 2: fall back to device path written by initramfs/init
    local persist_dev
    persist_dev=$(cat /run/thatthing-persist-dev 2>/dev/null || true)
    if [ -n "$persist_dev" ] && [ -b "$persist_dev" ]; then
        if mount -o rw,relatime "$persist_dev" "$PERSIST_MNT" 2>/dev/null; then
            return 0
        fi
    fi

    # Strategy 3: wait up to 10s for udev to settle, then retry label
    local attempts=0
    while [ "$attempts" -lt 10 ]; do
        sleep 1
        attempts=$(( attempts + 1 ))
        if mount -L "THATHING_DATA" "$PERSIST_MNT" -o rw,relatime 2>/dev/null; then
            return 0
        fi
    done

    return 1  # all strategies failed
}

# Try to mount persistence before checking the flag
if ! _ensure_persist_mounted; then
    # Persist partition unavailable: skip TUI (volatile mode, nothing to persist to)
    # Show a brief warning on console and exit cleanly
    echo "[first-boot] /media/persist not mountable — running in volatile mode, skipping TUI." > /dev/tty1
    exit 0
fi

if [ -f "$FLAG_FILE" ]; then
    exit 0
fi

### ── Welcome screen ─────────────────────────────────────────────────
dialog_ok --msgbox \
"\Zb\Z6Welcome to ThatThingOS v3.0\Zn

This wizard will configure your system:
  • Username and password
  • Timezone and locale
  • Wi-Fi connection

Changes are saved to permanent storage.
Press Enter to begin." 14 55

### ── Step 1: Username ────────────────────────────────────────────────
USERNAME=""
while [ -z "$USERNAME" ]; do
    USERNAME=$(dialog_ok --stdout --inputbox \
        "Enter your username:" 8 40 "thatthing") || {
        dialog_ok --msgbox "Username cannot be empty." 6 35
        USERNAME=""
    }
    # Validate: lowercase, alphanumeric + underscore
    if ! echo "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]{0,30}$'; then
        dialog_ok --msgbox "Invalid username.\nUse lowercase letters, digits, - or _." 7 45
        USERNAME=""
    fi
done

### ── Step 2: Password ────────────────────────────────────────────────
PASS1="" PASS2="mismatch"
while [ "$PASS1" != "$PASS2" ] || [ -z "$PASS1" ]; do
    PASS1=$(dialog_ok --stdout --passwordbox \
        "Enter password for '$USERNAME':" 8 45) || PASS1=""
    PASS2=$(dialog_ok --stdout --passwordbox \
        "Confirm password:" 8 45) || PASS2="x"
    if [ "$PASS1" != "$PASS2" ]; then
        dialog_ok --msgbox "Passwords do not match. Try again." 6 40
    elif [ ${#PASS1} -lt 4 ]; then
        dialog_ok --msgbox "Password too short (minimum 4 chars)." 6 40
        PASS1="" PASS2="x"
    fi
done

### ── Step 3: Timezone ───────────────────────────────────────────────
TZ_CHOICE=$(dialog_ok --stdout --menu \
    "Select Timezone:" 18 55 10 \
    "Asia/Ho_Chi_Minh" "Vietnam (UTC+7)" \
    "Asia/Bangkok"     "Thailand (UTC+7)" \
    "Asia/Singapore"   "Singapore (UTC+8)" \
    "UTC"              "UTC" \
    "custom"           "Enter manually") || TZ_CHOICE="Asia/Ho_Chi_Minh"

if [ "$TZ_CHOICE" = "custom" ]; then
    TZ_CHOICE=$(dialog_ok --stdout --inputbox \
        "Enter timezone (e.g. America/New_York):" 8 50 "UTC") || TZ_CHOICE="UTC"
fi

### ── Step 4: Wi-Fi Setup ────────────────────────────────────────────
dialog_ok --yesno "Do you want to configure Wi-Fi now?" 7 45
SETUP_WIFI=$?   # 0=yes, 1=no

if [ "$SETUP_WIFI" -eq 0 ]; then
    # Bring up interface for scanning
    WIFI_IF=""
    for iface in $(ls /sys/class/net/); do
        [ -d "/sys/class/net/$iface/wireless" ] && { WIFI_IF="$iface"; break; }
    done

    if [ -z "$WIFI_IF" ]; then
        dialog_ok --msgbox "No wireless interface found.\nConnect via Ethernet or set up Wi-Fi later." 8 50
    else
        dialog_ok --infobox "Scanning for Wi-Fi networks on $WIFI_IF ...\n(This takes ~5 seconds)" 6 50
        ip link set "$WIFI_IF" up 2>/dev/null || true
        sleep 5

        # Get SSID list
        NETWORKS=$(iw dev "$WIFI_IF" scan 2>/dev/null \
            | grep -E '^\s+SSID:' \
            | sed 's/.*SSID: //' \
            | sort -u \
            | head -20 \
            | awk '{print NR, $0}') || NETWORKS=""

        if [ -z "$NETWORKS" ]; then
            SSID=$(dialog_ok --stdout --inputbox \
                "No networks found. Enter SSID manually:" 8 50 "") || SSID=""
        else
            # Build dialog menu from scan
            MENU_ITEMS=()
            while IFS= read -r line; do
                IDX=$(echo "$line" | awk '{print $1}')
                NET=$(echo "$line" | awk '{$1=""; print $0}' | xargs)
                MENU_ITEMS+=("$IDX" "$NET")
            done <<< "$NETWORKS"

            SELECTED_IDX=$(dialog_ok --stdout --menu \
                "Select Wi-Fi network:" 20 55 12 \
                "${MENU_ITEMS[@]}" "0" "Enter SSID manually") || SELECTED_IDX="0"

            if [ "$SELECTED_IDX" = "0" ]; then
                SSID=$(dialog_ok --stdout --inputbox \
                    "Enter SSID:" 8 50 "") || SSID=""
            else
                SSID=$(echo "$NETWORKS" | awk -v idx="$SELECTED_IDX" '$1==idx{$1=""; print $0}' | xargs)
            fi
        fi

        if [ -n "$SSID" ]; then
            WIFI_PASS=$(dialog_ok --stdout --passwordbox \
                "Password for '$SSID' (leave empty if open):" 8 55) || WIFI_PASS=""

            mkdir -p "$(dirname "$WPA_CONF")"
            if [ -z "$WIFI_PASS" ]; then
                cat > "$WPA_CONF" <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
network={
    ssid="$SSID"
    key_mgmt=NONE
}
WPAEOF
            else
                wpa_passphrase "$SSID" "$WIFI_PASS" > "$WPA_CONF" 2>/dev/null \
                    || {
                        cat > "$WPA_CONF" <<WPAEOF
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel
update_config=1
network={
    ssid="$SSID"
    psk="$WIFI_PASS"
}
WPAEOF
                    }
            fi
            # Start wpa_supplicant now
            wpa_supplicant -B -i "$WIFI_IF" -c "$WPA_CONF" 2>/dev/null || true
            dhcpcd -nq "$WIFI_IF" 2>/dev/null &
            dialog_ok --infobox "Connecting to '$SSID'..." 5 40
            sleep 3
        fi
    fi
fi

### ── Apply all settings ──────────────────────────────────────────────
dialog_ok --infobox "Applying configuration..." 5 40

# Create/modify user
if ! id "$USERNAME" &>/dev/null; then
    if command -v adduser &>/dev/null; then
        adduser -s /bin/bash -h "/home/$USERNAME" -G wheel -D "$USERNAME" 2>/dev/null || true
    else
        useradd -m -s /bin/bash -G wheel,audio,video,input "$USERNAME" 2>/dev/null || true
    fi
fi
# Set password
echo "$USERNAME:$PASS1" | chpasswd 2>/dev/null || \
    echo "$PASS1" | passwd --stdin "$USERNAME" 2>/dev/null || true

# Grant passwordless sudo
mkdir -p /etc/sudoers.d
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 440 "/etc/sudoers.d/$USERNAME"

# Timezone
if command -v setup-timezone &>/dev/null; then
    setup-timezone -z "$TZ_CHOICE" 2>/dev/null || true
else
    ln -sf "/usr/share/zoneinfo/$TZ_CHOICE" /etc/localtime 2>/dev/null || true
    echo "$TZ_CHOICE" > /etc/timezone
fi

# Locale
cat > /etc/locale.conf <<LOCEOF
LANG=en_US.UTF-8
LC_ALL=en_US.UTF-8
LOCEOF

### ── Mark first boot complete ───────────────────────────────────────
if mountpoint -q "$PERSIST_MNT" 2>/dev/null; then
    touch "$FLAG_FILE"
fi

### ── Done ──────────────────────────────────────────────────────────
dialog_ok --msgbox \
"\Zb\Z2Setup Complete!\Zn

  User: \Zb$USERNAME\Zn
  Timezone: $TZ_CHOICE
  Locale: en_US.UTF-8

The system is ready. You can now log in.
Press Enter to continue." 14 50

clear
echo "Setup complete. Please log in as: $USERNAME"

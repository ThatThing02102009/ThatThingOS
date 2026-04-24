#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 03: Alpine SquashFS Builder
#
# Design decisions for 4GB RAM target:
#   - ZSTD level 15 (not 22): decompresses ~3x faster on i5-2430M
#     with only ~8% size penalty vs level 22.
#   - Block size 256K: better random-access pattern for live OS workload
#     vs 1M which favors sequential read.
#   - Build-time -mem 12G: exploit MSI host's 16GB for parallel compression.
#   - Strip: no desktop env, no heavy browsers — TUI-first system.
#   - Packages kept: wpa_supplicant, dialog, rsync for wifi+TUI+sync.
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

build_squashfs() {
    step "Building Stripped Alpine RootFS (ZSTD-15 / 256K blocks)"
    log "Target: <600MB squashfs | i5-2430M decompression-optimized"

    local ROOTFS_DIR="$BUILD_DIR/alpine_rootfs"
    rm -rf "$ROOTFS_DIR"
    mkdir -p "$ROOTFS_DIR"

    log "Downloading Alpine 3.19 Mini RootFS..."
    wget -q "https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz" -O "$BUILD_DIR/alpine.tar.gz"
    sudo tar -C "$ROOTFS_DIR" -xf "$BUILD_DIR/alpine.tar.gz"
    rm "$BUILD_DIR/alpine.tar.gz"

    log "Configuring DNS for chroot..."
    sudo cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"

    log "Installing packages in Alpine chroot..."
    cat > "$BUILD_DIR/chroot_build.sh" <<'EOF'
#!/bin/sh
for i in 1 2 3; do
    apk update && \
    apk add --no-cache \
        openrc busybox-extras util-linux e2fsprogs parted rsync dialog \
        wpa_supplicant wireless-tools iw iproute2 dhcpcd \
        linux-firmware-intel linux-firmware-other mesa-dri-gallium \
        libva-intel-media-driver font-terminus sudo shadow bash curl \
        wget tar gzip xz zstd ca-certificates tzdata pciutils usbutils \
        lsof htop nano less && break || sleep 5
done

rc-update del crond default 2>/dev/null || true
rc-update del sshd default 2>/dev/null || true
rc-update del avahi-daemon default 2>/dev/null || true
rc-update del cups default 2>/dev/null || true
rc-update del bluetooth default 2>/dev/null || true

rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

mkdir -p /run/thatthing /media/persist

addgroup -S thatthing 2>/dev/null || groupadd thatthing
adduser  -S -G thatthing -s /bin/bash -h /home/thatthing thatthing 2>/dev/null \
    || useradd -m -G thatthing -s /bin/bash thatthing

echo "thatthing:CHANGEME_FIRST_BOOT" | chpasswd
mkdir -p /etc/sudoers.d
echo "thatthing ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/thatthing
EOF

    sudo mv "$BUILD_DIR/chroot_build.sh" "$ROOTFS_DIR/chroot_build.sh"
    sudo chmod +x "$ROOTFS_DIR/chroot_build.sh"
    
    # Mount virtual filesystems for chroot
    sudo mount -t proc /proc "$ROOTFS_DIR/proc/"
    sudo mount -t sysfs /sys "$ROOTFS_DIR/sys/"
    sudo mount -o bind /dev "$ROOTFS_DIR/dev/"
    
    sudo chroot "$ROOTFS_DIR" /chroot_build.sh
    sudo rm -f "$ROOTFS_DIR/chroot_build.sh"
    
    # Unmount
    sudo umount "$ROOTFS_DIR/dev/"
    sudo umount "$ROOTFS_DIR/sys/"
    sudo umount "$ROOTFS_DIR/proc/"

    log "Building SquashFS on HOST with -mem ${HOST_MEM_SQFS}..."
    rm -rf "$BUILD_DIR/docker_out"
    mkdir -p "$BUILD_DIR/docker_out"

    sudo mksquashfs "$ROOTFS_DIR" "$BUILD_DIR/docker_out/rootfs.img" \
        -e ./proc ./sys ./dev ./run ./tmp ./var/cache/apk \
        -comp zstd \
        -Xcompression-level 15 \
        -b 262144 \
        -no-progress \
        -noappend \
        -all-root \
        -mem "${HOST_MEM_SQFS}"

    local sz
    sz=$(du -sh "$BUILD_DIR/docker_out/rootfs.img" | cut -f1)
    echo "$BUILD_DIR/docker_out/rootfs.img" > "$BUILD_DIR/sqfs_path.txt"
    ok "SquashFS ready: $BUILD_DIR/docker_out/rootfs.img ($sz)"
}

build_squashfs

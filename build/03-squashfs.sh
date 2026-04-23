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

    cat > "$BUILD_DIR/alpine-rootfs.dockerfile" <<'EOF'
FROM alpine:3.19 AS rootfs

# FIX #1+#2: Receive mem budget from docker build --build-arg
# CI: 4G (passed by host script), Local: 12G
ARG SQFS_MEM=12G

# ── Core system (absolute minimum) ───────────────────────────────────
RUN apk add --no-cache --update \
    alpine-base \
    openrc \
    busybox-extras \
    util-linux \
    e2fsprogs \
    parted \
    rsync \
    \
    dialog \
    \
    wpa_supplicant \
    wireless-tools \
    iw \
    iproute2 \
    dhcpcd \
    \
    linux-firmware-i915 \
    linux-firmware-iwlwifi \
    linux-firmware-ath9k-htc \
    linux-firmware-brcm \
    linux-firmware-rtl_nic \
    mesa-dri-gallium \
    libva-intel-driver \
    \
    font-terminus \
    \
    sudo \
    shadow \
    \
    bash \
    curl \
    wget \
    tar \
    gzip \
    xz \
    zstd \
    ca-certificates \
    tzdata \
    \
    pciutils \
    usbutils \
    lsof \
    htop \
    \
    nano \
    less

# ── Strip unneeded services ───────────────────────────────────────────
# Only keep: networking, udev (for hw detection), syslog (for debug)
RUN rc-update del crond default 2>/dev/null || true
RUN rc-update del sshd    default 2>/dev/null || true
RUN rc-update del avahi-daemon default 2>/dev/null || true
RUN rc-update del cups    default 2>/dev/null || true
RUN rc-update del bluetooth default 2>/dev/null || true

# ── Clean apk cache ───────────────────────────────────────────────────
RUN rm -rf /var/cache/apk/* /tmp/* /var/tmp/*

# ── Directory structure for overlay/persistence ───────────────────────
RUN mkdir -p /run/thatthing /media/persist

# -- Create placeholder thatthing user (password set by first-boot TUI)
RUN addgroup -S thatthing 2>/dev/null || groupadd thatthing
RUN adduser  -S -G thatthing -s /bin/bash -h /home/thatthing thatthing 2>/dev/null \
    || useradd -m -G thatthing -s /bin/bash thatthing
# SECURITY NOTE: This is a build-time PLACEHOLDER password only.
# The first-boot TUI (first-boot-tui.sh) will force the user to set a real password
# before the system becomes usable. The value here is intentionally
# obvious so it is never mistaken for a real credential.
RUN echo "thatthing:CHANGEME_FIRST_BOOT" | chpasswd
RUN echo "thatthing ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/thatthing

# ── Prepare squashfs ──────────────────────────────────────────────────
# FIX #2: -all-root ensures ALL injected files (scripts, services) are owned
# by root:root in the squashfs, regardless of the builder's UID on the host.
# Without this, files injected by CI runners (uid=1001) would be owned by a
# non-existent UID inside the rootfs, breaking setuid binaries and services.
RUN mksquashfs / /rootfs.img \
    -e ./proc ./sys ./dev ./run ./tmp ./var/cache/apk ./rootfs.img \
    -comp zstd \
    -Xcompression-level 15 \
    -b 262144 \
    -no-progress \
    -noappend \
    -all-root \
    -mem $SQFS_MEM

EOF

    log "Building Alpine rootfs Docker image (SQFS_MEM=$HOST_MEM_SQFS)..."
    docker build --progress=plain \
        --memory=14g \
        --build-arg SQFS_MEM="$HOST_MEM_SQFS" \
        -t thatthing-rootfs-v3 \
        -f "$BUILD_DIR/alpine-rootfs.dockerfile" \
        "$BUILD_DIR" 2>&1 | tee "$BUILD_DIR/rootfs-build.log"

    rm -rf "$BUILD_DIR/docker_out"
    mkdir -p "$BUILD_DIR/docker_out"

    local CID
    CID=$(docker create thatthing-rootfs-v3)
    docker cp "$CID:/rootfs.img" "$BUILD_DIR/docker_out/rootfs.img"
    docker rm -v "$CID"

    local sz
    sz=$(du -sh "$BUILD_DIR/docker_out/rootfs.img" | cut -f1)
    echo "$BUILD_DIR/docker_out/rootfs.img" > "$BUILD_DIR/sqfs_path.txt"
    ok "SquashFS ready: $BUILD_DIR/docker_out/rootfs.img ($sz)"
}

build_squashfs

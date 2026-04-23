#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 01: CachyOS Kernel Build
# Target: Intel Sandy Bridge i5-2430M/2520M, Intel HD 3000
# Scheduler: BORE (Burst-Oriented Response Enhancer)
# Compiler: Clang + LLVM (faster, better optimizations for old hardware)
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

build_kernel() {
    step "Building CachyOS Kernel (BORE + Sandy Bridge)"
    log "Kernel 6.8.9 | -march=sandybridge | CLANG+LLVM | Intel HD 3000 KMS"

    mkdir -p "$BUILD_DIR/out_kernel"

    cat > "$BUILD_DIR/kernel.dockerfile" <<'EOF'
FROM alpine:3.19 AS kernel-builder

# Build toolchain — musl-based, keeps image small
RUN apk add --no-cache \
    build-base perl bash bc bison flex \
    openssl-dev elfutils-dev linux-headers \
    sed zlib-dev ncurses-dev findutils kmod \
    tar gzip xz argp-standalone curl wget git \
    clang lld llvm python3 make coreutils \
    gawk diffutils patch pahole

WORKDIR /build
ENV KVER=6.8.9

RUN wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz \
 && tar -xf linux-${KVER}.tar.xz \
 && rm linux-${KVER}.tar.xz

WORKDIR /build/linux-${KVER}

# Apply BORE scheduler patch
RUN wget -q \
    https://raw.githubusercontent.com/cachyos/kernel-patches/master/6.8/sched/0001-bore.patch \
    -O bore.patch 2>/dev/null \
 && patch -p1 --forward < bore.patch 2>/dev/null \
 || echo "[INFO] BORE patch not needed or already applied."

# Base config for x86_64 generic
RUN make x86_64_defconfig

# ── Hardware-specific tuning ────────────────────────────────────────
# Sandy Bridge: no AVX2, but has SSE4.2, AES-NI
# Intel HD 3000 = GEN6 i915 (Sandybridge GT2)
RUN scripts/config \
    -e CONFIG_GENERIC_CPU \
    --set-val CONFIG_NR_CPUS 4 \
    \
    -e CONFIG_DRM \
    -e CONFIG_DRM_I915 \
    -e CONFIG_DRM_I915_CAPTURE_ERROR \
    -d CONFIG_DRM_I915_GVT \
    -d CONFIG_DRM_I915_GVT_KVMGT \
    -e CONFIG_AGP \
    -e CONFIG_AGP_INTEL \
    \
    -e CONFIG_FB_EFI \
    -e CONFIG_FRAMEBUFFER_CONSOLE \
    -e CONFIG_VGA_CONSOLE \
    -e CONFIG_ACPI_VIDEO \
    \
    -e CONFIG_SQUASHFS \
    -e CONFIG_SQUASHFS_ZSTD \
    -e CONFIG_OVERLAY_FS \
    -e CONFIG_ZRAM \
    -e CONFIG_ZSMALLOC \
    -e CONFIG_CRYPTO_ZSTD \
    -e CONFIG_CRYPTO_LZ4 \
    \
    -e CONFIG_SCHED_BORE \
    -e CONFIG_BORE_SCHED \
    \
    -e CONFIG_WPA_SUPPLICANT_SUPPORT \
    -e CONFIG_MAC80211 \
    -e CONFIG_CFG80211 \
    -e CONFIG_IWLWIFI \
    -e CONFIG_IWLDVM \
    -e CONFIG_IWLMVM \
    -e CONFIG_ATH9K \
    -e CONFIG_ATH9K_HTC \
    -e CONFIG_RTL8192CE \
    -e CONFIG_RTL8192SE \
    -e CONFIG_RTL8192DE \
    \
    -e CONFIG_NET \
    -e CONFIG_WIRELESS \
    -e CONFIG_RFKILL \
    -e CONFIG_WLAN \
    \
    -e CONFIG_EXT4_FS \
    -e CONFIG_VFAT_FS \
    -e CONFIG_ISO9660_FS \
    -e CONFIG_TMPFS \
    \
    -d CONFIG_MATOM \
    -d CONFIG_GENERIC_CPU_FREEZER \
    -d CONFIG_BTRFS_FS \
    -d CONFIG_GFS2_FS \
    -d CONFIG_OCFS2_FS \
    -d CONFIG_XFS_FS \
    -d CONFIG_CEPH_FS \
    -d CONFIG_NFS_FS \
    -d CONFIG_CIFS \
    \
    -d CONFIG_SOUND_PCI \
    -d CONFIG_SND_HDA_INTEL \
    -d CONFIG_SND_USB_AUDIO \
    \
    -d CONFIG_BT \
    -d CONFIG_BT_HCIUSB \
    \
    -d CONFIG_INFINIBAND \
    -d CONFIG_SCSI_FC_ATTRS \
    -d CONFIG_SCSI_ISCSI_ATTRS

RUN make olddefconfig

# Build: clang + LLVM for better Sandy Bridge optimizations
# nproc on CI/build host = full concurrency
RUN make -j$(nproc) \
    CC=clang \
    LLVM=1 \
    LLVM_IAS=1 \
    KCFLAGS="-march=sandybridge -O2 -pipe" \
    bzImage modules

# Install
RUN mkdir -p /out/lib/modules /out/boot
RUN make INSTALL_MOD_PATH=/out modules_install
RUN cp arch/x86/boot/bzImage /out/boot/vmlinuz-thatthing
RUN cp System.map /out/boot/System.map
RUN cp .config /out/boot/config-thatthing

FROM scratch
COPY --from=kernel-builder /out /out
EOF

    log "Building kernel Docker image (this takes ~15-20 min)..."
    docker build --progress=plain \
        -t thatthing-kernel-v3 \
        -f "$BUILD_DIR/kernel.dockerfile" \
        "$BUILD_DIR" 2>&1 | tee "$BUILD_DIR/kernel-build.log"

    rm -rf "$BUILD_DIR/out_kernel"
    mkdir -p "$BUILD_DIR/out_kernel"

    # Extract using a temporary container
    local CID
    CID=$(docker create thatthing-kernel-v3)
    docker cp "$CID:/out/." "$BUILD_DIR/out_kernel/"
    docker rm -v "$CID"

    local kver
    kver=$(ls "$BUILD_DIR/out_kernel/lib/modules/" | head -1)
    ok "Kernel extracted: vmlinuz-thatthing (modules: $kver)"
}

build_kernel

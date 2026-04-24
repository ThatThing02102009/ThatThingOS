#!/bin/bash
########################################################################
# ThatThingOS v3.0 — Module 01: CachyOS Kernel Build
# Target: Intel Sandy Bridge i5-2430M/2520M, Intel HD 3000
# Scheduler: BORE (Burst-Oriented Response Enhancer)
# Compiler: Clang + LLVM (faster, better optimizations for old hardware)
#
# OPTIMIZATION: Stripped & hardened config for Google Colab (~30-40 min)
#   - CONFIG_DEBUG_INFO=n        → ~50% reduction in build artifacts
#   - LTO=NONE                   → avoids link-time OOM on Colab
#   - Sanitizers OFF             → KASAN/KCSAN/UBSAN/KMSAN disabled
#   - GPU: Intel i915 ONLY       → AMD/Nouveau/Radeon stripped
#   - Net: Intel WiFi ONLY       → Realtek/Broadcom/Atheros stripped
#   - Sound: Intel HDA ONLY      → exotic codecs stripped
########################################################################
# shellcheck source=./00-env.sh
source "$(dirname "$0")/00-env.sh"
set -euo pipefail

build_kernel() {
    step "Building CachyOS Kernel (BORE + Sandy Bridge)"
    log "Kernel 6.8.9 | -march=sandybridge | CLANG+LLVM | Intel HD 3000 KMS"

    mkdir -p "$BUILD_DIR/out_kernel"

    local KVER="6.8.9"
    local KERNEL_DIR="$BUILD_DIR/linux-${KVER}"

    if [ ! -d "$KERNEL_DIR" ]; then
        log "Downloading Kernel ${KVER}..."
        wget -q "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz" -O "$BUILD_DIR/linux-${KVER}.tar.xz"
        tar -C "$BUILD_DIR" -xf "$BUILD_DIR/linux-${KVER}.tar.xz"
        rm "$BUILD_DIR/linux-${KVER}.tar.xz"
    fi

    pushd "$KERNEL_DIR" > /dev/null

    # Apply BORE scheduler patch
    if [ ! -f .patch_applied ]; then
        log "Applying BORE scheduler patch..."
        wget -q https://raw.githubusercontent.com/cachyos/kernel-patches/master/6.8/sched/0001-bore.patch -O bore.patch 2>/dev/null
        patch -p1 --forward < bore.patch 2>/dev/null || echo "[INFO] BORE patch not needed or already applied."
        touch .patch_applied
    fi

    log "Configuring kernel base (x86_64_defconfig)..."
    make x86_64_defconfig

    # ── STEP 1: Compilation Speed Optimization ──────────────────────────
    # These are the highest-ROI changes for Colab build time reduction.
    log "Applying build-speed optimizations..."
    ./scripts/config \
        `# --- Debug Info OFF: single biggest win (~50% less I/O) ---` \
        -d DEBUG_INFO \
        -d DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT \
        -d DEBUG_INFO_DWARF4 \
        -d DEBUG_INFO_DWARF5 \
        -d DEBUG_INFO_REDUCED \
        -d DEBUG_INFO_COMPRESSED_NONE \
        -d DEBUG_INFO_BTF \
        --set-val DEBUG_INFO_NONE y \
        \
        `# --- LTO: NONE (Full/Thin LTO causes link-time OOM on Colab) ---` \
        --set-val LTO_NONE y \
        -d LTO_CLANG_THIN \
        -d LTO_CLANG_FULL \
        \
        `# --- Heavy Sanitizers OFF (enormous compile-time overhead) ---` \
        -d KASAN \
        -d KASAN_GENERIC \
        -d KASAN_SW_TAGS \
        -d KMSAN \
        -d KCSAN \
        -d UBSAN \
        -d UBSAN_ALIGNMENT \
        -d UBSAN_BOUNDS \
        -d UBSAN_SANITIZE_ALL \
        -d KFENCE \
        \
        `# --- Other debug overhead OFF ---` \
        -d DEBUG_KERNEL \
        -d SLUB_DEBUG \
        -d LOCK_DEBUGGING_SUPPORT \
        -d PROVE_LOCKING \
        -d DEBUG_LOCKDEP \
        -d FRAME_POINTER

    # ── STEP 2: Intel Hardware (Keep) ────────────────────────────────────
    log "Enabling required Intel hardware drivers..."
    ./scripts/config \
        `# --- Intel Sandy Bridge GPU (GEN6 / HD 3000) ---` \
        -e DRM \
        -e DRM_I915 \
        -e DRM_I915_CAPTURE_ERROR \
        -d DRM_I915_GVT \
        -d DRM_I915_GVT_KVMGT \
        -e AGP \
        -e AGP_INTEL \
        \
        `# --- Framebuffer / Console ---` \
        -e FB_EFI \
        -e FRAMEBUFFER_CONSOLE \
        -e VGA_CONSOLE \
        -e ACPI_VIDEO \
        \
        `# --- Intel Wireless (iwlwifi / iwlmvm for WifiLink 6300 etc.) ---` \
        -e MAC80211 \
        -e CFG80211 \
        -e RFKILL \
        -e WLAN \
        -e WIRELESS \
        -e IWLWIFI \
        -e IWLDVM \
        -e IWLMVM \
        \
        `# --- Intel HDA Sound (Azalia — required for Dell Latitude) ---` \
        -e SOUND \
        -e SND \
        -e SND_PCI \
        -e SND_HDA_INTEL \
        -e SND_HDA_CODEC_HDMI \
        -e SND_HDA_CODEC_REALTEK \
        -e SND_HDA_CODEC_ANALOG \
        -e SND_HDA_GENERIC \
        \
        `# --- USB Audio (headset / dock support) ---` \
        -e SND_USB_AUDIO \
        \
        `# --- Intel Ethernet (e1000e for GbE NIC on Latitude) ---` \
        -e NET \
        -e NETDEVICES \
        -e E1000E \
        \
        `# --- Core filesystems ---` \
        -e EXT4_FS \
        -e VFAT_FS \
        -e ISO9660_FS \
        -e TMPFS \
        \
        `# --- SquashFS + Overlay (RAM-sovereign boot) ---` \
        -e SQUASHFS \
        -e SQUASHFS_ZSTD \
        -e OVERLAY_FS \
        -e ZRAM \
        -e ZSMALLOC \
        -e CRYPTO_ZSTD \
        -e CRYPTO_LZ4 \
        \
        `# --- BORE Scheduler ---` \
        -e SCHED_BORE \
        -e BORE_SCHED \
        \
        `# --- Sandy Bridge CPU count ---` \
        --set-val NR_CPUS 4

    # ── STEP 3: Strip Redundant GPU Drivers ──────────────────────────────
    # AMD, Radeon, Nouveau = hundreds of C files we will never compile.
    log "Disabling non-Intel GPU drivers..."
    ./scripts/config \
        -d DRM_AMDGPU \
        -d DRM_RADEON \
        -d DRM_NOUVEAU \
        -d DRM_VMWGFX \
        -d DRM_VBOXVIDEO \
        -d DRM_GMA500 \
        -d DRM_AST \
        -d DRM_MGA \
        -d DRM_R128 \
        -d DRM_TDFX \
        -d DRM_SIS \
        -d DRM_VIA \
        -d DRM_SAVAGE \
        -d DRM_VIRTIO_GPU \
        -d DRM_PANEL_SIMPLE \
        -d MATOM

    # ── STEP 4: Strip Redundant Network Drivers ──────────────────────────
    # Realtek, Broadcom, Atheros, Mellanox/Infiniband → not on Dell Latitude
    log "Disabling non-Intel network drivers..."
    ./scripts/config \
        `# --- Realtek WiFi (rtlXXX family) ---` \
        -d RTL8192CE \
        -d RTL8192SE \
        -d RTL8192DE \
        -d RTL8192EE \
        -d RTL8192CU \
        -d RTL8192EU \
        -d RTL8188EE \
        -d RTL8723AE \
        -d RTL8723BE \
        -d RTL8821AE \
        -d RTLWIFI \
        -d RTL8XXXU \
        -d RTL8150 \
        -d R8169 \
        -d R8152 \
        \
        `# --- Broadcom WiFi/Ethernet ---` \
        -d BRCMFMAC \
        -d BRCMSMAC \
        -d B43 \
        -d B44 \
        -d BGMAC \
        -d BNX2 \
        -d BNX2X \
        -d BCMGENET \
        \
        `# --- Atheros WiFi (ath9k was nice but NOT on Dell Latitude 6520) ---` \
        -d ATH9K \
        -d ATH9K_HTC \
        -d ATH10K \
        -d ATH10K_PCI \
        -d ATH11K \
        -d ATH12K \
        -d ATH5K \
        -d ATH6KL \
        \
        `# --- High-end server NICs (Mellanox, Emulex, Qlogic) ---` \
        -d INFINIBAND \
        -d MLX4_EN \
        -d MLX4_CORE \
        -d MLX5_CORE \
        -d BNXT \
        -d BE2NET \
        -d QED \
        -d QEDE \
        -d FCOE \
        -d SCSI_FC_ATTRS \
        -d SCSI_ISCSI_ATTRS \
        \
        `# --- MediaTek WiFi ---` \
        -d MT76x0U \
        -d MT76x0E \
        -d MT76x2U \
        -d MT76x2E \
        -d MT7921E \
        -d MT7921U

    # ── STEP 5: Strip Exotic Sound Codecs ────────────────────────────────
    # Keep Intel HDA (enabled above). Disable embedded/IoT audio.
    log "Disabling exotic sound codecs..."
    ./scripts/config \
        -d SND_SOC \
        -d SND_SOC_INTEL_MACH \
        -d SND_AC97_CODEC \
        -d SND_HDA_CODEC_CIRRUS \
        -d SND_HDA_CODEC_CS8409 \
        -d SND_HDA_CODEC_SIGMATEL \
        -d SND_HDA_CODEC_VIA \
        -d SND_HDA_CODEC_CONEXANT \
        -d SND_HDA_CODEC_IDT \
        -d SND_HDA_CODEC_CMEDIA \
        -d SND_HDA_CODEC_SI3054 \
        -d SND_INTEL_DSP_CONFIG \
        -d SND_CTXFI \
        -d SND_EMU10K1 \
        -d SND_YMFPCI \
        -d SND_ES1968 \
        -d SND_VIA82XX \
        -d SND_ALI5451

    # ── STEP 6: Strip Bloated Misc Subsystems ───────────────────────────
    log "Disabling unused filesystems and subsystems..."
    ./scripts/config \
        -d BTRFS_FS \
        -d GFS2_FS \
        -d OCFS2_FS \
        -d XFS_FS \
        -d CEPH_FS \
        -d NFS_FS \
        -d CIFS \
        -d BT \
        -d BT_HCIUSB \
        -d GENERIC_CPU_FREEZER

    # ── STEP 7: olddefconfig — Non-interactive, auto-fill new symbols ────
    # This is CRITICAL for Colab: prevents the build from pausing and asking
    # questions about new Kernel 6.8.9 symbols. Picks 'default' automatically.
    log "Running olddefconfig (non-interactive auto-fill for new symbols)..."
    make olddefconfig

    log "Building kernel (clang + LLVM) natively (target: ~25-35 min on Colab)..."
    make -j$(nproc) \
        CC=clang \
        LLVM=1 \
        LLVM_IAS=1 \
        KCFLAGS="-march=sandybridge -O2 -pipe" \
        bzImage modules 2>&1 | tee "$BUILD_DIR/kernel-build.log"

    log "Installing kernel modules and image to $BUILD_DIR/out_kernel..."
    rm -rf "$BUILD_DIR/out_kernel"
    mkdir -p "$BUILD_DIR/out_kernel/lib/modules" "$BUILD_DIR/out_kernel/boot"

    make INSTALL_MOD_PATH="$BUILD_DIR/out_kernel" modules_install
    cp arch/x86/boot/bzImage "$BUILD_DIR/out_kernel/boot/vmlinuz-thatthing"
    cp System.map "$BUILD_DIR/out_kernel/boot/System.map"
    cp .config "$BUILD_DIR/out_kernel/boot/config-thatthing"

    popd > /dev/null

    # Step Dependency Marker
    touch "$BUILD_DIR/kernel_ready.txt"

    local kver
    kver=$(ls "$BUILD_DIR/out_kernel/lib/modules/" | head -1)
    ok "Kernel extracted: vmlinuz-thatthing (modules: $kver)"
}

build_kernel

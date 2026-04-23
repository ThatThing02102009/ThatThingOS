FROM alpine:3.19 AS kernel-builder
RUN apk add --no-cache build-base perl bash bc bison flex openssl-dev elfutils-dev linux-headers sed zlib-dev ncurses-dev findutils kmod tar gzip xz argp-standalone curl wget git clang lld llvm python3 make coreutils gawk diffutils patch

WORKDIR /build
ENV KVER=6.8.9
RUN wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz && tar -xf linux-$KVER.tar.xz
WORKDIR /build/linux-$KVER

RUN wget https://raw.githubusercontent.com/cachyos/kernel-patches/master/6.8/sched/0001-bore.patch -O bore.patch || true
RUN patch -p1 --forward < bore.patch || echo "Patch already applied."

RUN make x86_64_defconfig
RUN scripts/config -e CONFIG_GENERIC_CPU \
    -e CONFIG_DRM_I915 -e CONFIG_DRM_I915_KMS \
    -e CONFIG_I915_LEGACY_KMS -e CONFIG_DRM_PANEL_ORIENTATION_QUIRKS \
    -e CONFIG_SQUASHFS_ZSTD -e CONFIG_BORE_SCHED -e CONFIG_SCHED_BORE \
    -d CONFIG_MATOM -d CONFIG_GENERIC_CPU_FREEZER
RUN make olddefconfig
RUN make -j$(nproc) CC=clang LLVM=1 LLVM_IAS=1 bzImage modules

RUN mkdir -p /out/lib/modules /out/boot
RUN make INSTALL_MOD_PATH=/out modules_install
RUN cp arch/x86/boot/bzImage /out/boot/vmlinuz-cachyos

FROM alpine:3.19
COPY --from=kernel-builder /out /out
ENTRYPOINT ["/bin/sh", "-c", "cp -a /out/* /mnt/"]

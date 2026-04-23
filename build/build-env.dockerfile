FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# All host-level build tools the build scripts need
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    cpio \
    gzip \
    xz-utils \
    zstd \
    findutils \
    xorriso \
    squashfs-tools \
    mtools \
    dosfstools \
    grub-efi-amd64-bin \
    grub-pc-bin \
    syslinux \
    syslinux-common \
    isolinux \
    rsync \
    curl \
    wget \
    sudo \
    util-linux \
    e2fsprogs \
    parted \
    busybox-static \
    ca-certificates \
    docker.io \
    && rm -rf /var/lib/apt/lists/*

# Make busybox-static available as busybox
RUN ln -sf /bin/busybox-static /usr/local/bin/busybox

# Grub standalone for EFI
RUN grub-mkstandalone --version > /dev/null

WORKDIR /workspace
ENTRYPOINT ["/bin/bash"]

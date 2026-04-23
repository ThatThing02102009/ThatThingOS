FROM alpine:3.19 AS builder
RUN apk add --no-cache bash sudo openjdk17-jre sway foot nmap python3 py3-pip mesa-dri-gallium xf86-video-intel libva-intel-driver util-linux pciutils usbutils squashfs-tools dbus font-terminus
RUN mkdir -p /out
RUN mksquashfs / /out/rootfs.img -e ./proc ./sys ./dev ./out ./build ./tmp ./var/cache/apk -comp zstd -Xcompression-level 22

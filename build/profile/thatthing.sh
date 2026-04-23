#!/bin/sh
# ThatThingOS — Alpine mkimage profile
# ──────────────────────────────────────────────────────────────────────

profile_thatthing() {
    profile_name="ThatThingOS"
    
    # ── Kernel: Fallback B - Using EDGE for scx (sched-ext) ───────────
    base_url="https://dl-cdn.alpinelinux.org/alpine/edge"
    kernel_flavors="edge"
    kernel_cmdline="quiet loglevel=0 vt.global_cursor_default=0 mitigations=off zswap.enabled=0 copytoram=y"
    arch="x86_64"
    output_filename="thatthing-os-{{tag}}-{{arch}}.iso"

    # ── APK packages baked into squashfs ─────────────────────────────
    # Replaced openjdk17-jre-headless -> openjdk17-jre
    # Filtered linux-firmware down to essentially i915 (HD 3000) & iwlwifi (MSI/Redmi Wifi)
    apks="
        alpine-base
        linux-edge
        linux-firmware-i915
        linux-firmware-iwlwifi
        busybox util-linux e2fsprogs parted lsblk blkid
        dbus eudev openrc
        wayland sway swaybar swaybg swaylock xwayland foot mako wl-clipboard grim slurp
        pipewire pipewire-alsa pipewire-pulse wireplumber
        mesa mesa-dri-gallium mesa-va-gallium libva-intel-driver vulkan-loader
        zram-init zstd
        networkmanager networkmanager-wifi iw wpa_supplicant
        git curl wget python3 py3-pip nmap tcpdump tshark netcat-openbsd socat strace
        bash zsh tmux neovim htop btop jq ripgrep
        openjdk17-jre
        sudo shadow polkit udisks2
        grub grub-efi grub-bios mtools dosfstools
        alacritty fontconfig font-jetbrains-mono-nerd
        agetty bc
    "

    apkovl() {
        # Generates an overlay tarball extracted during RAM-boot phase
        local ovl="$1"
        
        mkdir -p "$ovl"/etc/local.d
        mkdir -p "$ovl"/etc/profile.d
        mkdir -p "$ovl"/etc/sway
        mkdir -p "$ovl"/home/thatthing/.config/sway
        
        # ── 1. Create Default User (Auto-Login prep) ───────────────────
        cat > "$ovl"/etc/local.d/00-create-user.start << 'EOF'
#!/bin/sh
if ! id "thatthing" >/dev/null 2>&1; then
    adduser -D -s /bin/bash thatthing
    echo "thatthing ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/thatthing
    chown -R thatthing:thatthing /home/thatthing
fi
EOF
        chmod +x "$ovl"/etc/local.d/00-create-user.start

        # ── 2. HDD Jump Logic Loader ───────────────────────────────────
        cat > "$ovl"/etc/local.d/10-persistence.start << 'EOF'
#!/bin/sh
# Kick off the persistence setup after the user exists
/usr/local/bin/setup-persistence.sh > /var/log/persistence.log 2>&1
EOF
        chmod +x "$ovl"/etc/local.d/10-persistence.start
        
        # Enable local service on boot
        mkdir -p "$ovl"/etc/runlevels/default
        ln -s /etc/init.d/local "$ovl"/etc/runlevels/default/local

        # ── 3. Global Intel HD 3000 Mesa Overrides ─────────────────────
        cat > "$ovl"/etc/profile.d/mesa-hd3000.sh << 'EOF'
export MESA_LOADER_DRIVER_OVERRIDE=i965
export MESA_GL_VERSION_OVERRIDE=4.3
export MESA_GLSL_VERSION_OVERRIDE=430
export MESA_EXTENSION_OVERRIDE="+GL_ARB_compute_shader +GL_ARB_shader_storage_buffer_object"
export vblank_mode=0
EOF

        # ── 4. Auto-Login via Agetty & TTY Sway Launch ─────────────────
        mkdir -p "$ovl"/etc
        cat > "$ovl"/etc/inittab << 'EOF'
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::wait:/sbin/openrc default

# Auto-login to thatthing account on tty1
tty1::respawn:/sbin/agetty --autologin thatthing --noclear tty1 linux
tty2::respawn:/sbin/getty 38400 tty2

::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/openrc shutdown
EOF

        cat > "$ovl"/home/thatthing/.bash_profile << 'EOF'
if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
    exec sway
fi
EOF
        chown -R 1000:1000 "$ovl"/home/thatthing/.bash_profile 2>/dev/null || true

        # ── 5. Minimalist Cyan/Black Sway Configuration ────────────────
        cat > "$ovl"/home/thatthing/.config/sway/config << 'EOF'
set $mod Mod4
set $term foot

font pango:JetBrainsMono Nerd Font 10
default_border pixel 2
hide_edge_borders smart
gaps inner 5
gaps outer 0

# Cyan #00ffff and Black #000000 
# class                  border    bg        text      indicator child_border
client.focused           #00ffff   #000000   #00ffff   #00ffff   #00ffff
client.unfocused         #111111   #000000   #888888   #111111   #111111
client.focused_inactive  #111111   #000000   #888888   #111111   #111111
client.urgent            #ff0000   #000000   #ffffff   #ff0000   #ff0000

output * bg #000000 solid_color
xwayland enable

bindsym $mod+Return exec $term
bindsym $mod+d exec wofi --show drun
bindsym $mod+q kill
bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit?' -b 'yes' 'swaymsg exit'
bindsym $mod+h focus left
bindsym $mod+j focus down
bindsym $mod+k focus up
bindsym $mod+l focus right

bar {
    position bottom
    colors {
        background #000000
        statusline #00ffff
        separator  #333333
        focused_workspace  #00ffff #000000 #00ffff
        inactive_workspace #000000 #000000 #555555
    }
}
EOF

        # ── 6. ASCII Terminal MOTD ─────────────────────────────────────
        cat > "$ovl"/etc/motd << 'MOTD'
 [36m
  ████████╗██╗  ██╗ █████╗ ████████╗████████╗██╗  ██╗██╗███╗   ██╗ ██████╗ 
     ██╔══╝██║  ██║██╔══██╗╚══██╔══╝╚══██╔══╝██║  ██║██║████╗  ██║██╔════╝ 
     ██║   ███████║███████║   ██║      ██║   ███████║██║██╔██╗ ██║██║      
     ██║   ██╔══██║██╔══██║   ██║      ██║   ██╔══██║██║██║╚██╗██║██║      
     ██║   ██║  ██║██║  ██║   ██║      ██║   ██║  ██║██║██║ ╚████║╚██████╗ 
     ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝      ╚═╝   ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝ 
 [0m
  [ SYSTEM STATS ]
  OS:   ThatThingOS (Live Copy-to-RAM)
  GPU:  Intel HD 3000 Graphics (Forced i965/4.3 GL)
  PERF: CachyOS / sched-ext Responsive Scheduler Setup

  -> Checking persistence status... (see cat /var/log/persistence.log)
MOTD
    }
}

#!/bin/bash
########################################################################
# ThatThingOS — User Environment Setup Script
# Runs once on first login via .bashrc or a systemd user service
# Sets up: colors, Sway, scripts, Java/Prism, MESA env vars
########################################################################

########################################################################
# ~/.bashrc
########################################################################
cat << 'BASHRC' > ~/.bashrc
# ── ThatThingOS Shell ─────────────────────────────────────────────────
[[ $- != *i* ]] && return   # abort if non-interactive

# ── MESA OpenGL spoof for Intel HD 3000 ──────────────────────────────
export MESA_GL_VERSION_OVERRIDE=4.3
export MESA_GLSL_VERSION_OVERRIDE=430
export MESA_EXTENSION_OVERRIDE="+GL_ARB_compute_shader +GL_ARB_shader_storage_buffer_object"
export vblank_mode=0
export __GL_THREADED_OPTIMIZATIONS=1

# ── Wayland ───────────────────────────────────────────────────────────
export XDG_SESSION_TYPE=wayland
export XDG_RUNTIME_DIR=/run/user/$(id -u)
export WAYLAND_DISPLAY=wayland-1
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export CLUTTER_BACKEND=wayland
export EGL_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1

# ── Java for Minecraft ────────────────────────────────────────────────
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH=$JAVA_HOME/bin:$HOME/.local/bin:$HOME/scripts:$PATH

# ── Java performance flags ────────────────────────────────────────────
export _JAVA_OPTIONS="-Xms512m -Xmx3G \
  -XX:+UseG1GC \
  -XX:G1HeapRegionSize=32m \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1MixedGCLiveThresholdPercent=90 \
  -XX:G1RSetUpdatingPauseTimePercent=5 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1"

# ── Tool aliases ──────────────────────────────────────────────────────
alias ls='lsd --color=always'
alias ll='lsd -la --color=always'
alias cat='bat --theme=ansi'
alias grep='grep --color=auto'
alias vim='nvim'
alias s='sudo'
alias sniff='sudo tcpdump -i any -nn'
alias ports='ss -tulnp'
alias nets='ip -br a && ip route'
alias mcs='~/scripts/minecraft_start.sh'
alias matrix='cmatrix -ab -u 4 -C cyan'

# ── Prompt: neon cyan / dark ──────────────────────────────────────────
_git_branch() {
    git branch 2>/dev/null | grep '^*' | awk '{print " \033[35m("$2")\033[0m"}'
}

PS1='\[\033[0;36m\]╔[\[\033[1;32m\]\u\[\033[0;36m\]@\[\033[1;32m\]\h\[\033[0;36m\]] \[\033[1;37m\]\w\[\033[0m\]$(_git_branch)\n\[\033[0;36m\]╚═▶ \[\033[0m\]'

# ── Auto-launch Sway on TTY1 ──────────────────────────────────────────
if [[ -z $DISPLAY && -z $WAYLAND_DISPLAY && $(tty) == /dev/tty1 ]]; then
    exec sway
fi
BASHRC

echo "[thatthing] ~/.bashrc written."

#!/bin/bash
########################################################################
# ThatThingOS — Prism Launcher installer + Minecraft environment setup
# Installs portable PrismLauncher AppImage, sets MESA env vars,
# configures JVM flags for HD 3000 hardware
########################################################################
set -euo pipefail

PRISM_DIR="$HOME/.local/share/prismlauncher"
PRISM_BIN="$HOME/.local/bin/prismlauncher"
PRISM_VER="8.4"   # update to latest stable
PRISM_URL="https://github.com/PrismLauncher/PrismLauncher/releases/download/${PRISM_VER}/PrismLauncher-Linux-x86_64.AppImage"

C='\033[36m'; G='\033[32m'; Y='\033[33m'; R='\033[31m'; W='\033[0m'; B='\033[1m'
log() { echo -e "${C}[*] $*${W}"; }
ok()  { echo -e "${G}[+] $*${W}"; }
die() { echo -e "${R}[!] $*${W}" >&2; exit 1; }

log "Downloading PrismLauncher ${PRISM_VER}..."
mkdir -p "$HOME/.local/bin" "$PRISM_DIR"
curl -Lo "$PRISM_BIN" "$PRISM_URL" || die "Download failed"
chmod +x "$PRISM_BIN"
ok "PrismLauncher installed: $PRISM_BIN"

# ── Desktop entry ─────────────────────────────────────────────────────
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/prismlauncher.desktop" << EOF
[Desktop Entry]
Version=1.0
Name=Prism Launcher
Comment=Minecraft launcher (ThatThingOS)
Exec=$PRISM_BIN
Icon=prismlauncher
Type=Application
Categories=Game;
EOF

# ── MESA + JVM wrapper script ─────────────────────────────────────────
cat > "$HOME/scripts/minecraft_start.sh" << 'MCSCRIPT'
#!/bin/bash
# Minecraft startup wrapper — Intel HD 3000 / MESA overrides

# Mesa GL spoof: expose OpenGL 4.3 to avoid "unsupported version" crashes
export MESA_GL_VERSION_OVERRIDE=4.3
export MESA_GLSL_VERSION_OVERRIDE=430
export MESA_EXTENSION_OVERRIDE="+GL_ARB_compute_shader +GL_ARB_shader_storage_buffer_object +GL_ARB_framebuffer_object"
export LIBGL_ALWAYS_SOFTWARE=0
export vblank_mode=0

# Wayland/X11 compatibility for Prism/LWJGL
export XDG_SESSION_TYPE=wayland
export GDK_BACKEND=wayland
export SDL_VIDEODRIVER=wayland
export _JAVA_AWT_WM_NONREPARENTING=1

# JVM GC flags (Aikar's flags, tuned for 4GB system)
export _JAVA_OPTIONS="\
  -Xms512m -Xmx3G \
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

echo "[ThatThingOS] Launching PrismLauncher with MESA HD3000 overrides..."
exec "$HOME/.local/bin/prismlauncher" "$@"
MCSCRIPT

chmod +x "$HOME/scripts/minecraft_start.sh"
ok "Minecraft launcher script: ~/scripts/minecraft_start.sh"

# ── Recommended mods reminder ─────────────────────────────────────────
cat << 'MODS'

  Recommended mods (install via Prism → Instance → Mods):
  ┌─────────────────────────────────────────────────────┐
  │ Performance:  Sodium, Lithium, Phosphor              │
  │ Render:       Iris (GLSL shaders lite, HD3000 safe)  │
  │ Anarchy:      Meteor Client / Wurst (check MC ver)   │
  │ Utility:      FeatureCreep, BetterPvP                │
  └─────────────────────────────────────────────────────┘
  Note: Verify exploit client compat with your MC version.

MODS

ok "Done. Run: ~/scripts/minecraft_start.sh"

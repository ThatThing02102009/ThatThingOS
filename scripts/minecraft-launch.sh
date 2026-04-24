#!/bin/bash
# Wrapper tool to launch Minecraft (Prism Launcher) correctly 
# under forcing conditions on an Intel HD 3000 (Sandybridge).
# Ensuring copy-to-RAM memory footprint is respected.

echo "=============================================="
echo "    [ThatThing-OS // Intel HD3000 Spoofing]   "
echo "=============================================="

# 1. Enforce the i965 driver overriding standard crocus/iris drivers 
export MESA_LOADER_DRIVER_OVERRIDE=i965

# 2. Spoof OpenGL properties to satisfy MC 1.17+ requirements (usually requires GL 3.3/4.0)
export MESA_GL_VERSION_OVERRIDE=4.3
export MESA_GLSL_VERSION_OVERRIDE=430
export MESA_EXTENSION_OVERRIDE="+GL_ARB_compute_shader +GL_ARB_shader_storage_buffer_object +GL_ARB_framebuffer_object"

# 3. Sync & GPU optimization threads
export vblank_mode=0
export __GL_THREADED_OPTIMIZATIONS=1

# 4. Hardware acceleration for Wayland
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export _JAVA_AWT_WM_NONREPARENTING=1

# 5. Native Wayland overrides for GLFW apps
export GLFW_IM_MODULE=ibus

# 6. JVM Optimizations for 4GB RAM System
# Memory budget: 4GB total − ~800MB RootFS/OS − ~400MB GPU/kernel = ~2800MB usable
# We cap JVM at 1800M to leave comfortable headroom and avoid OOM kills.
# Shenandoah GC: concurrent, low-pause — ideal for Minecraft on Java 17/21.
# Falls back gracefully to G1GC if Shenandoah is unavailable (e.g. OpenJ9 builds).
export _JAVA_OPTIONS="-Xms512m -Xmx1800m \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+UseShenandoahGC \
  -XX:ShenandoahGCMode=adaptive \
  -XX:+ShenandoahUncommit \
  -XX:ShenandoahUncommitDelay=1000 \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:-UsePerfData \
  -Djava.awt.headless=false"

PRISM_APPIMAGE="$HOME/.local/bin/prismlauncher"

if [ ! -f "$PRISM_APPIMAGE" ]; then
    echo "[!] PrismLauncher AppImage not found at $PRISM_APPIMAGE!"
    echo "    Please run the installer script first."
    exit 1
fi

echo "[*] Memory Alloc: 1800MB (Max) | GC: ShenandoahGC (adaptive, low-pause)"
echo "[*] OpenGL Driver: mesa_gallium (i965) at Override v4.3"
echo "[*] Bridging directly to Wayland KMS/DRM..."

# Exec ensures this Bash wrapper gets replaced by Prism process (PID1 inheritance if run tightly)
exec "$PRISM_APPIMAGE" "$@"

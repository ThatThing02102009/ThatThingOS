@echo off
setlocal EnableDelayedExpansion
chcp 65001 > nul

:: ========================================================================
:: ThatThingOS v3.0 - Windows Build Launcher
:: Requires: Docker Desktop for Windows (Linux containers mode)
::
:: Usage:
::   build.bat            -> Full build (all 5 stages)
::   build.bat kernel     -> Kernel only
::   build.bat squashfs   -> SquashFS only
::   build.bat iso        -> ISO packaging only
::   build.bat from=3     -> From stage 3 onwards
::
:: Output: out\  ->  thatthing-os-YYYYMMDD.iso
:: ========================================================================

set "BUILD_ENV_IMAGE=thatthing-build-env:v3"
set "PROJECT_DIR=%~dp0"
:: Remove trailing backslash
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

set "STAGE_ARG=%~1"
if "%STAGE_ARG%"=="" set "STAGE_ARG=all"

echo.
echo  THATTHINGOS v3.0 "RAM SOVEREIGN" - Windows Docker Build Launcher
echo.

:: ── 1. Check Docker binary exists at all ─────────────────────────────────────
where docker > nul 2>&1
if errorlevel 1 (
    echo.
    echo  [FATAL] Docker CLI not found in PATH!
    echo.
    echo  Install Docker Desktop from https://www.docker.com/products/docker-desktop
    echo  Make sure to run the installer and restart this terminal afterwards.
    echo.
    pause
    exit /b 1
)

:: ── 2. Check Docker daemon is running ────────────────────────────────────────
docker info > nul 2>&1
if errorlevel 1 (
    echo.
    echo  [FATAL] Docker Desktop is installed but NOT running!
    echo.
    echo  To fix:
    echo    1. Open the Start Menu and launch "Docker Desktop".
    echo    2. Wait for the Docker whale icon in the system tray to stop animating.
    echo    3. Re-run this script.
    echo.
    pause
    exit /b 1
)
echo [  OK ] Docker daemon is running.

:: ── 3. Verify Linux containers mode (not Windows) ────────────────────────────
for /f "tokens=*" %%A in ('docker info --format "{{.OSType}}" 2^>nul') do set "OS_TYPE=%%A"
if /i not "%OS_TYPE%"=="linux" (
    echo.
    echo  [FATAL] Docker is in Windows containers mode!
    echo.
    echo  To switch:
    echo    Right-click the Docker whale icon in the system tray.
    echo    Click "Switch to Linux containers..." and wait for Docker to restart.
    echo    Then re-run this script.
    echo.
    pause
    exit /b 1
)
echo [  OK ] Linux containers mode confirmed.

:: ── 4. Build the build-environment image (cached after first run) ─────────────
echo.
echo [BUILD] Preparing build environment image "%BUILD_ENV_IMAGE%"...
echo         (First run downloads ~200MB; subsequent runs use the layer cache)
echo.

docker build --quiet ^
    -t "%BUILD_ENV_IMAGE%" ^
    -f "%PROJECT_DIR%\build\build-env.dockerfile" ^
    "%PROJECT_DIR%\build"

if errorlevel 1 (
    echo.
    echo  [FATAL] Failed to build the Docker build-environment image.
    echo.
    echo  Common causes:
    echo    - No internet connection (needed to pull base Alpine image)
    echo    - Dockerfile syntax error in build\build-env.dockerfile
    echo    - Low disk space (Docker needs ~2GB free)
    echo.
    pause
    exit /b 1
)
echo [  OK ] Build environment image ready.

:: ── 5. Create output directory ────────────────────────────────────────────────
if not exist "%PROJECT_DIR%\out" mkdir "%PROJECT_DIR%\out"

:: ── 6. Convert Windows path to Docker-compatible Unix path for -v ────────────
:: Example:  C:\Users\you\ThatThingOS  ->  /c/Users/you/ThatThingOS
:: Note: Docker Desktop on Windows handles the /host_mnt/ prefix internally;
:: using the drive-letter notation (/c/...) is the most portable approach.
set "DOCKER_PATH=%PROJECT_DIR:\=/%"
set "DOCKER_PATH=/%DOCKER_PATH::=%"
:: Lower-case the drive letter (Docker requires it)
for %%A in (a b c d e f g h i j k l m n o p q r s t u v w x y z) do (
    set "DOCKER_PATH=!DOCKER_PATH:/%%A/=/%%A/!"
)

echo.
echo [BUILD] Launching build inside Docker container...
echo         Stage  : %STAGE_ARG%
echo         Source : %PROJECT_DIR%
echo         Mapped : %DOCKER_PATH%
echo.

:: --privileged is required for loopback mounts (squashfs, overlayfs) inside Docker.
:: -v uses the Unix-style path so Docker Desktop's file sharing layer handles it.
:: If you see "permission denied" on the volume:
::   Docker Desktop -> Settings -> Resources -> File Sharing -> add your drive.
docker run --rm ^
    --name thatthing-build ^
    --privileged ^
    -v "%DOCKER_PATH%:/workspace:z" ^
    -e "HOME=/root" ^
    -e "TERM=xterm-256color" ^
    "%BUILD_ENV_IMAGE%" ^
    /bin/bash -c "/workspace/build.sh %STAGE_ARG%"

if errorlevel 1 (
    echo.
    echo  [FATAL] Build failed! Review the output above for the root cause.
    echo.
    echo  Common causes ^& fixes:
    echo    - "permission denied" on /workspace
    echo        -> Docker Desktop: Settings -> Resources -> File Sharing
    echo           Add the drive or folder containing this project.
    echo    - "no space left on device"
    echo        -> Docker Desktop: Settings -> Resources -> Disk image size
    echo           Increase it or run: docker system prune -f
    echo    - A build script error (99%% of failures)
    echo        -> Check the log lines above the [FATAL] message.
    echo.
    pause
    exit /b 1
)

:: ── 7. Report output ──────────────────────────────────────────────────────────
echo.
echo  +--------------------------------------------------------------+
echo  ^|         BUILD COMPLETE - ThatThingOS v3.0                    ^|
echo  +--------------------------------------------------------------+

set "ISO_FOUND=0"
for %%F in ("%PROJECT_DIR%\out\*.iso") do (
    echo  ^|  ISO  : %%~nxF
    echo  ^|  Size : %%~zF bytes
    set "ISO_FOUND=1"
)

if "%ISO_FOUND%"=="0" (
    echo  ^|  WARNING: No ISO file found in out\
    echo  ^|  The build may have failed silently.
)

echo  +--------------------------------------------------------------+
echo  ^|  Copy the ISO to your Ventoy USB drive to boot.             ^|
echo  +--------------------------------------------------------------+
echo.

explorer "%PROJECT_DIR%\out"
pause
endlocal

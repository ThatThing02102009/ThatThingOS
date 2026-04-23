@echo off
setlocal EnableDelayedExpansion
chcp 65001 > nul

:: ========================================================================
:: ThatThingOS v3.0 — Windows Build Launcher
:: Yêu cầu: Docker Desktop for Windows (Linux containers mode)
::
:: Cách dùng:
::   build.bat            → Full build (tất cả 5 giai đoạn)
::   build.bat kernel     → Chỉ build kernel
::   build.bat squashfs   → Chỉ build squashfs
::   build.bat iso        → Chỉ đóng gói ISO
::   build.bat from=3     → Từ giai đoạn 3 trở đi
::
:: Output: thư mục out\  →  thatthing-os-YYYYMMDD.iso
:: ========================================================================

set "BUILD_ENV_IMAGE=thatthing-build-env:v3"
set "PROJECT_DIR=%~dp0"
:: Remove trailing backslash
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"

:: Convert Windows path to Docker-compatible Unix path
:: e.g.  C:\Users\you\MaDoc  →  /c/Users/you/MaDoc
set "DOCKER_PATH=%PROJECT_DIR:\=/%"
set "DOCKER_PATH=/%DOCKER_PATH::=%"

set "STAGE_ARG=%~1"
if "%STAGE_ARG%"=="" set "STAGE_ARG=all"

echo.
echo  ████████╗██╗  ██╗ █████╗ ████████╗████████╗██╗  ██╗██╗███╗   ██╗  ██████╗
echo     ██║   ███████║███████║   ██║      ██║   ███████║██║██╔██╗ ██║ ██║  ███╗
echo     ██║   ██╔══██║██╔══██║   ██║      ██║   ██╔══██║██║██║╚██╗██║ ██║   ██║
echo  v3.0 "RAM SOVEREIGN" — Windows Docker Build Launcher
echo.

:: ── 1. Check Docker is running ────────────────────────────────────────────
echo [CHECK] Verifying Docker Desktop is running...
docker info > nul 2>&1
if errorlevel 1 (
    echo.
    echo  [FATAL] Docker is NOT running!
    echo  Please start Docker Desktop and switch to "Linux containers" mode.
    echo  Then run this script again.
    echo.
    pause
    exit /b 1
)
echo [  OK ] Docker is running.

:: ── 2. Check Linux containers mode (not Windows containers) ──────────────
for /f "tokens=*" %%A in ('docker info --format "{{.OSType}}" 2^>nul') do set "OS_TYPE=%%A"
if /i not "%OS_TYPE%"=="linux" (
    echo.
    echo  [FATAL] Docker is in Windows containers mode!
    echo  Right-click the Docker tray icon → "Switch to Linux containers..."
    echo.
    pause
    exit /b 1
)
echo [  OK ] Linux containers mode confirmed.

:: ── 3. Build the build-environment image (only once, cached after that) ──
echo.
echo [BUILD] Preparing build environment image "%BUILD_ENV_IMAGE%"...
echo         (First run downloads ~200MB, subsequent runs use cache)
echo.

docker build --quiet ^
    -t "%BUILD_ENV_IMAGE%" ^
    -f "%PROJECT_DIR%\build\build-env.dockerfile" ^
    "%PROJECT_DIR%\build"

if errorlevel 1 (
    echo [FATAL] Failed to build the build environment image.
    pause
    exit /b 1
)
echo [  OK ] Build environment ready.

:: ── 4. Create out\ directory if missing ──────────────────────────────────
if not exist "%PROJECT_DIR%\out" mkdir "%PROJECT_DIR%\out"

:: ── 5. Run the build inside the container ────────────────────────────────
echo.
echo [BUILD] Launching build inside Docker container...
echo         Stage: %STAGE_ARG%
echo         Project: %DOCKER_PATH%
echo.

docker run --rm ^
    --name thatthing-build ^
    --privileged ^
    -v "%DOCKER_PATH%:/workspace" ^
    -v /var/run/docker.sock:/var/run/docker.sock ^
    -e "HOME=/root" ^
    -e "TERM=xterm-256color" ^
    "%BUILD_ENV_IMAGE%" ^
    -c "/workspace/build.sh %STAGE_ARG%"

if errorlevel 1 (
    echo.
    echo  [FATAL] Build failed! Check the output above for errors.
    echo.
    pause
    exit /b 1
)

:: ── 6. Report output ────────────────────────────────────────────────────
echo.
echo  ┌──────────────────────────────────────────────────────────────┐
echo  │         BUILD COMPLETE — ThatThingOS v3.0                    │
echo  ├──────────────────────────────────────────────────────────────┤

for %%F in ("%PROJECT_DIR%\out\*.iso") do (
    echo  │  ISO: %%~nxF
    echo  │  Size: %%~zF bytes
)

echo  ├──────────────────────────────────────────────────────────────┤
echo  │  → Copy the ISO to your Ventoy USB drive to boot             │
echo  └──────────────────────────────────────────────────────────────┘
echo.

:: Open the out\ folder in Explorer
explorer "%PROJECT_DIR%\out"

pause
endlocal

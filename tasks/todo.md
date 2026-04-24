# Task: System Hardening & Optimization Pass

## Goal
Rà soát và cải tiến toàn bộ dự án ThatThingOS v3.0 theo 5 nhóm vấn đề:
memory management, data safety, CI/CD speed, boot reliability, và clean code.

## Checklist

### 1. Memory & JVM (scripts/minecraft-launch.sh)
- [x] Giảm `-Xmx` từ 2500m → **1800m** (an toàn với 4GB RAM + RootFS ~800MB)
- [x] Thay G1GC bằng **ShenandoahGC** (adaptive, low-pause — Java 17/21 native)
- [x] Thêm `-XX:ShenandoahUncommit` để giải phóng RAM khi MC nhàn rỗi
- [x] Xác nhận ZRAM trong `initramfs/init` đã dùng `zstd → lz4` fallback ✓ (no change needed)

### 2. Data Safety (scripts/setup-persistence.sh)
- [x] Rewrite hoàn toàn theo hướng **interactive** (yêu cầu user xác nhận device)
- [x] Thêm bước kiểm tra label `THATTHING_SAVE` đã tồn tại → **bỏ qua format**
- [x] Guard: từ chối partition ổ Ventoy USB
- [x] `--auto` flag cho CI/first-boot fallback (non-interactive mode)

### 3. CI/CD Kernel Cache (.github/workflows/build.yml)
- [x] Thêm `actions/cache@v4` cache key = SHA256 của `build/01-kernel.sh`
- [x] Logic rẽ nhánh: cache hit → skip Stage 1, chạy từ Stage 2 (tiết kiệm ~40 phút)
- [x] Touch `build/kernel_ready.txt` khi dùng cache để Stage 4 nhận module

### 4. Boot Race Condition (build/04-overlays.sh — 10-first-boot.start)
- [x] Thêm **wait-loop tối đa 8 giây** retry mount trước khi kiểm tra flag
- [x] Giữ nguyên logic 2 chiến lược mount (label → device path từ initramfs)
- [x] Chỉ bỏ qua TUI khi BOTH: persist mounted VÀ flag tồn tại

### 5. Clean Code — build.bat
- [x] Phân biệt "Docker not installed" vs "Docker not running" vs "wrong mode"
- [x] Thêm hướng dẫn fix cụ thể cho từng lỗi
- [x] Fix volume mapping: thêm `:z` flag (SELinux compatibility)
- [x] Fix shell invocation: `bash -c "..."` thay vì `-c "..."` (thiếu interpreter)
- [x] Thêm troubleshooting cho "permission denied" và "no space left"

## Result

Tất cả 5 nhóm thay đổi đã được áp dụng. Các file đã sửa:
- `scripts/minecraft-launch.sh` — JVM/GC optimization
- `scripts/setup-persistence.sh` — Interactive rewrite
- `.github/workflows/build.yml` — Kernel cache CI/CD
- `build/04-overlays.sh` — Wait-loop race condition fix
- `build.bat` — Improved error messages & volume mapping

Xem chi tiết trong artifact: `tasks/session_changes.md`

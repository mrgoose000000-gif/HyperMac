#!/bin/bash
# HyperMac — build universal binary `Resources/smc` (arm64 + x86_64) cho privileged helper.
#
# Nguồn: CLI `smc` từ dự án GPL hholtmann/smcFanControl
#   https://github.com/hholtmann/smcFanControl  (file: smc-command/smc.c + smc.h)
# Output: ghi đè `Resources/smc` bằng Mach-O universal (cả arm64 lẫn x86_64) →
#   các api feature chạy helper (`fan-set`, `fan-info`, `charge-off/on`) hoạt động trên cả
#   Mac Intel lẫn Apple Silicon. Trước đây `Resources/smc` là arm64-only nên trên Intel
#   mọi thao tác ghi SMC qua helper đều chết.
#
# Yêu cầu: máy Mac có Command Line Tools / Xcode (có clang + lipo). Chạy từ thư mục gốc repo.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Resources/smc"
TMP=".build/smc-src"
SNIP=".build/smc-slices"
mkdir -p .build

echo "🔨 Building universal ${OUT} (arm64 + x86_64) từ hholtmann/smcFanControl ..."
rm -rf "$TMP" "$SNIP" && mkdir -p "$SNIP"

if ! git clone --depth 1 https://github.com/hholtmann/smcFanControl "$TMP" >/dev/null 2>&1; then
    echo "❌ Không clone được hholtmann/smcFanControl (cần kết nối mạng)." >&2
    exit 1
fi

C="smc-command/smc.c"
# -DCMD_TOOL_BUILD bắt buộc: `int main` của smc.c nằm trong `#ifdef CMD_TOOL_BUILD`
# (dòng 421–793); thiếu flag này chương trình chỉ có library function, không có main.
CFLAGS=(-DCMD_TOOL_BUILD -O2 -Wall -Wno-deprecated-declarations -framework IOKit -framework CoreFoundation)

echo "  -> arm64 (Apple Silicon)..."
clang "${CFLAGS[@]}" -target arm64-apple-macos11 -o "$SNIP/smc-arm64" "$TMP/$C"

echo "  -> x86_64 (Intel)..."
clang "${CFLAGS[@]}" -target x86_64-apple-macos10.13 -o "$SNIP/smc-x86_64" "$TMP/$C"

lipo -create "$SNIP/smc-arm64" "$SNIP/smc-x86_64" -output "$OUT"
rm -rf "$TMP" "$SNIP"
echo "✅ ${OUT}: $(file "$OUT")"

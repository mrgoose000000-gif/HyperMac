#!/bin/bash
set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          HyperMac — Build Script         ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Step 0: Terminate existing instances ──
echo "🛑 Stopping any running instances..."
pkill -9 HyperMac 2>/dev/null || true
pkill -9 DisplayControl 2>/dev/null || true
sleep 0.5

# ── Step 1: Build (Default: Apple Silicon chip M / Optional: --universal) ──
BUILD_UNIVERSAL=false
for arg in "$@"; do
    if [ "$arg" = "--universal" ]; then
        BUILD_UNIVERSAL=true
    fi
done

if [ "$BUILD_UNIVERSAL" = "true" ]; then
    echo "🔨 Building HyperMac (Release - Universal 2: arm64 + x86_64)..."
    mkdir -p .build/bin_arm64 .build/bin_x86_64 .build/release
    echo "  -> Compiling arm64 (Apple Silicon)..."
    swift build -c release --triple arm64-apple-macosx >/dev/null 2>&1 || swift build -c release
    if [ -f ".build/out/Products/Release/HyperMac" ]; then
        cp .build/out/Products/Release/HyperMac .build/bin_arm64/HyperMac
    elif [ -f ".build/release/HyperMac" ]; then
        cp .build/release/HyperMac .build/bin_arm64/HyperMac
    fi

    echo "  -> Compiling x86_64 (Intel)..."
    swift build -c release --triple x86_64-apple-macosx >/dev/null 2>&1 || true
    if [ -f ".build/out/Products/Release/HyperMac" ]; then
        cp .build/out/Products/Release/HyperMac .build/bin_x86_64/HyperMac
    fi

    BINARY=".build/release/HyperMac"
    if [ -f ".build/bin_arm64/HyperMac" ] && [ -f ".build/bin_x86_64/HyperMac" ]; then
        echo "  -> Merging with lipo (Universal 2)..."
        lipo -create .build/bin_arm64/HyperMac .build/bin_x86_64/HyperMac -output "$BINARY"
    elif [ -f ".build/bin_arm64/HyperMac" ]; then
        cp .build/bin_arm64/HyperMac "$BINARY"
    fi
else
    echo "⚡ Building HyperMac (Tốc độ cao - Chip M: M1/M2/M3/M4)..."
    swift build -c release
    BINARY=".build/release/HyperMac"
fi

if [ ! -f "$BINARY" ]; then
    echo "❌ Build failed – binary not found."
    exit 1
fi
echo "✅ Build succeeded: $(file "$BINARY")"

# ── Step 2: Create .app bundle ──
APP_NAME="HyperMac"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "📦 Creating app bundle..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

cp "$BINARY" "${MACOS}/"

# Copy Resources (AppIcon.icns, cover.jpg, SMC tools, etc.)
if [ -d "Resources" ]; then
    echo "🎨 Copying app resources (icons, cover image, SMC tools)..."
    cp -R Resources/* "${RESOURCES}/"
    chmod +x "${RESOURCES}/smc" "${RESOURCES}/displaycontrol-power" "${RESOURCES}/install-helper.sh" 2>/dev/null || true
fi

# Info.plist — LSUIElement hides dock icon (menu-bar only)
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>HyperMac</string>
    <key>CFBundleIdentifier</key>
    <string>com.opensource.hypermac</string>
    <key>CFBundleName</key>
    <string>HyperMac</string>
    <key>CFBundleDisplayName</key>
    <string>HyperMac</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>1.6.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>HyperMac sử dụng Bluetooth để tự động ngắt kết nối khi gập nắp máy (Sleep Guard), giúp chống tụt pin và chống nóng máy khi ngủ.</string>
    <key>NSBluetoothPeripheralUsageDescription</key>
    <string>HyperMac quản lý nguồn Bluetooth khi máy Mac vào chế độ ngủ để tiết kiệm pin.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>HyperMac cần quyền ghi màn hình để hiển thị ảnh xem trước các cửa sổ trong trình chuyển đổi Alt+Tab.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>HyperMac sử dụng AppleEvents để điều khiển các ứng dụng và màn hình.</string>
</dict>
</plist>
PLIST

# ── Step 3: Code sign ──
# Dùng chứng chỉ self-signed cố định nếu có (scripts/setup-signing-identity.sh).
# Ký ad-hoc tạo cdhash mới mỗi lần build → macOS thu hồi quyền Accessibility
# sau mỗi lần rebuild. Identity cố định giữ nguyên Designated Requirement.
SIGN_IDENTITY="${HYPERMAC_SIGN_IDENTITY:-HyperMac Self-Signed}"
SIGN_KEYCHAIN="${HYPERMAC_SIGN_KEYCHAIN:-}"
FIND_ARGS=()
if [[ -n "${SIGN_KEYCHAIN}" ]]; then
    FIND_ARGS=("${SIGN_KEYCHAIN}")
fi
if security find-identity -v -p codesigning "${FIND_ARGS[@]}" 2>/dev/null | grep -qF "${SIGN_IDENTITY}"; then
    echo "🔏 Code signing (${SIGN_IDENTITY})..."
    CODESIGN_ARGS=(--force --deep --sign "${SIGN_IDENTITY}" --identifier "com.opensource.hypermac")
    if [[ -n "${SIGN_KEYCHAIN}" ]]; then
        CODESIGN_ARGS+=(--keychain "${SIGN_KEYCHAIN}")
    fi
    codesign "${CODESIGN_ARGS[@]}" "${APP_DIR}"
else
    echo "🔏 Code signing (ad-hoc — quyền Accessibility sẽ mất sau mỗi lần build)..."
    echo "   → Chạy ./scripts/setup-signing-identity.sh một lần để hết bị."
    codesign --force --deep --sign - --identifier "com.opensource.hypermac" "${APP_DIR}" 2>/dev/null || true
fi

# ── Step 3.1: Create release zip package ──
echo "📦 Packaging ${BUILD_DIR}/HyperMac.zip for distribution..."
COPYFILE_DISABLE=1 ditto -c -k --norsrc --keepParent "${APP_DIR}" "${BUILD_DIR}/HyperMac.zip"
echo "✅ Package created: ${BUILD_DIR}/HyperMac.zip"

if [ "$CI" = "true" ] || [ "$1" = "--no-run" ]; then
    echo "📦 CI build completed. Artifact is ready at: ${BUILD_DIR}/HyperMac.zip"
    exit 0
fi

# ── Step 4: Install to /Applications/ ──
echo "🚀 Installing to /Applications/HyperMac.app..."
rm -rf /Applications/HyperMac.app
cp -R "${APP_DIR}" /Applications/HyperMac.app
rm -rf /Applications/DisplayControl.app 2>/dev/null || true

# ── Step 5: Launch ──
echo "▶️ Launching /Applications/HyperMac.app..."
open /Applications/HyperMac.app

sleep 1
PID=$(pgrep -x HyperMac || true)
if [ -n "$PID" ]; then
    echo "✅ HyperMac is running with PID: $PID"
else
    echo "⚠️ HyperMac not detected yet, please check Console."
fi

echo ""
echo "══════════════════════════════════════════"
echo "  ✅  HyperMac updated & running!"
echo "══════════════════════════════════════════"
echo ""

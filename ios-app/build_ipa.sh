#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SDK_PATH="/tmp/ios-sdk/iPhoneOS16.5.sdk"
BUILD_DIR="/tmp/autoshorts-ios-build"
APP_DIR="$BUILD_DIR/Payload/AutoShorts.app"
OUT_IPA="$ROOT_DIR/dist/AutoShorts-App.ipa"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR" "$ROOT_DIR/dist"

echo "[1/4] Compiling native iOS executable (arm64)..."
clang -arch arm64 \
  -isysroot "$SDK_PATH" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -O2 \
  -framework UIKit \
  -framework Foundation \
  -framework WebKit \
  -framework CoreMotion \
  -framework AVFoundation \
  -framework CoreGraphics \
  -framework QuartzCore \
  "$SCRIPT_DIR/main.m" \
  -o "$APP_DIR/AutoShorts"

chmod +x "$APP_DIR/AutoShorts"

echo "[2/4] Copying Info.plist and generating PkgInfo..."
cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Info.plist"
printf "APPL????" > "$APP_DIR/PkgInfo"

echo "[3/4] Generating App Icons..."
python3 - <<'PY'
import struct, zlib, math

def make_icon(width, height, path):
    raw = bytearray()
    cx, cy = width / 2.0, height / 2.0
    for y in range(height):
        raw.append(0)
        for x in range(width):
            # Dark sleek gradient background with red-coral play + lightning accent
            nx = (x - cx) / (width * 0.5)
            ny = (y - cy) / (height * 0.5)
            dist = math.sqrt(nx*nx + ny*ny)
            r, g, b = 18, 18, 24
            if dist < 0.72:
                # Rounded red circle badge
                r, g, b = 238, 45, 58
                # White play triangle inside
                if nx > -0.22 and nx < 0.32 and abs(ny) < (0.32 - nx) * 0.68:
                    r, g, b = 255, 255, 255
            raw.extend((r, g, b, 255))

    def chunk(tag, data):
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data) & 0xffffffff)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 6))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

make_icon(120, 120, "/tmp/autoshorts-ios-build/Payload/AutoShorts.app/AppIcon60x60@2x.png")
make_icon(180, 180, "/tmp/autoshorts-ios-build/Payload/AutoShorts.app/AppIcon60x60@3x.png")
PY

echo "[4/4] Ad-hoc signing and packaging IPA..."
codesign --force --sign - "$APP_DIR/AutoShorts"
(cd "$BUILD_DIR" && zip -qry "$OUT_IPA" Payload)
ls -lh "$OUT_IPA"
echo "Done! Output: $OUT_IPA"

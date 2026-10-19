#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
DELIVERY_DIR="${SOURCE_DIR:h}"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp/}reading-highlighter.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/荧光阅读.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macosx13.0 \
  -framework AppKit -framework Carbon \
  "$SOURCE_DIR/main.swift" -o "$APP/Contents/MacOS/ReadingHighlighter"
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
"$APP/Contents/MacOS/ReadingHighlighter" --make-icon "$BUILD_DIR/icon.png"
mkdir -p "$BUILD_DIR/AppIcon.iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD_DIR/icon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$BUILD_DIR/icon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 "$SOURCE_DIR/make_icns.py" "$BUILD_DIR/AppIcon.iconset" "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
ditto --norsrc --noextattr "$APP" "$DELIVERY_DIR/荧光阅读.app"
xattr -d com.apple.FinderInfo "$DELIVERY_DIR/荧光阅读.app" 2>/dev/null || true
codesign --verify --deep --strict "$DELIVERY_DIR/荧光阅读.app"
echo "已生成：$DELIVERY_DIR/荧光阅读.app"

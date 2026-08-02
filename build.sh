#!/bin/bash
#
# Xcode 없이 .app 번들을 만든다. Command Line Tools만 있으면 된다.
#
#   ./build.sh          빌드만
#   ./build.sh --run    빌드하고 실행
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CAGONG"
EXEC_NAME="Cagong"
BUNDLE_ID="com.yeekrim.cagong"
TARGET="arm64-apple-macos14.0"

APP="$ROOT/build/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"

echo "▸ 정리"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$CONTENTS/Resources"

echo "▸ Info.plist"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$EXEC_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

echo "▸ 리소스 복사"
if [ -f "$ROOT/Sources/Cagong/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Sources/Cagong/Resources/AppIcon.icns" "$CONTENTS/Resources/"
    echo "  AppIcon.icns"
fi
for FOLDER in Backgrounds Drinks; do
    SRC="$ROOT/Sources/Cagong/Resources/$FOLDER"
    if [ -d "$SRC" ]; then
        cp -R "$SRC" "$CONTENTS/Resources/"
        echo "  $FOLDER $(ls -1 "$CONTENTS/Resources/$FOLDER" | wc -l | tr -d ' ')장"
    fi
done

echo "▸ 컴파일"
# shellcheck disable=SC2046
swiftc -O -parse-as-library \
    -target "$TARGET" \
    -o "$MACOS_DIR/$EXEC_NAME" \
    $(find "$ROOT/Sources/Cagong" -name '*.swift' | sort)

echo "▸ 서명 (ad-hoc)"
codesign --force --sign - "$APP" >/dev/null 2>&1

echo "✓ $APP"

if [[ "${1:-}" == "--run" ]]; then
    echo "▸ 실행"
    pkill -f "$APP_NAME.app/Contents/MacOS/$EXEC_NAME" 2>/dev/null || true
    open "$APP"
fi

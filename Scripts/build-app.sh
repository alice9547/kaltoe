#!/bin/zsh
# Kaltoe.app 을 dist/ 에 만든다. 사용: Scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Kaltoe"
APP="dist/Kaltoe.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Kaltoe"
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
[[ -f Resources/AppIcon-maltese-1024.png ]] && cp Resources/AppIcon-maltese-1024.png "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Kaltoe</string>
    <key>CFBundleDisplayName</key><string>칼퇴</string>
    <key>CFBundleIdentifier</key><string>dev.kaltoe.app</string>
    <key>CFBundleExecutable</key><string>Kaltoe</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Kaltoe 2>/dev/null || true
    rm -rf /Applications/Kaltoe.app
    cp -R "$APP" /Applications/Kaltoe.app
    open /Applications/Kaltoe.app
    echo "installed /Applications/Kaltoe.app"
fi

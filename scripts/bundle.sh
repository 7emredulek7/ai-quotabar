#!/bin/bash
# Builds a release binary and wraps it in Headroom.app (menu bar only, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Headroom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Headroom "$APP/Contents/MacOS/Headroom"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Headroom</string>
    <key>CFBundleIdentifier</key><string>local.headroom</string>
    <key>CFBundleExecutable</key><string>Headroom</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

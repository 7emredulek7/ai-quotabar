#!/bin/bash
# Builds a release binary and wraps it in UsageBar.app (menu bar only, no Dock icon).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/UsageBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/UsageBar "$APP/Contents/MacOS/UsageBar"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>UsageBar</string>
    <key>CFBundleIdentifier</key><string>local.usagebar</string>
    <key>CFBundleExecutable</key><string>UsageBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

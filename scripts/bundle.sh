#!/bin/bash
# Builds a release binary and wraps it in "AI Quotabar.app" (menu bar only, no Dock icon).
# Usage: scripts/bundle.sh [--universal]   (VERSION=x.y.z sets the bundle version)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${VERSION:-0.1.0}
if [[ "${1:-}" == "--universal" ]]; then
    swift build -c release --arch arm64 --arch x86_64
    BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AIQuotabar"
else
    swift build -c release
    BIN=.build/release/AIQuotabar
fi

APP="build/AI Quotabar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AIQuotabar"
# Regenerate with `swift scripts/make-icon.swift` after editing assets/icon.svg.
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>AI Quotabar</string>
    <key>CFBundleDisplayName</key><string>AI Quotabar</string>
    <key>CFBundleIdentifier</key><string>local.aiquotabar</string>
    <key>CFBundleExecutable</key><string>AIQuotabar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"

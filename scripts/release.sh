#!/bin/bash
# Builds a universal "AI Quotabar.app" and packages it as a .dmg and a .zip
# for a GitHub release.
# Usage: scripts/release.sh 0.2.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>}
VERSION=$VERSION scripts/bundle.sh --universal

APP="build/AI Quotabar.app"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/AIQuotabar")

# Disk image with the usual drag-to-Applications layout.
STAGE=build/dmg
rm -rf "$STAGE" build/AIQuotabar.dmg
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "AI Quotabar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov build/AIQuotabar.dmg
rm -rf "$STAGE"
echo "Built build/AIQuotabar.dmg ($ARCHS)"

# ditto keeps the bundle's structure and code signature intact.
rm -f build/AIQuotabar.zip
ditto -c -k --keepParent "$APP" build/AIQuotabar.zip
echo "Built build/AIQuotabar.zip ($ARCHS)"

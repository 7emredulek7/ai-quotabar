#!/bin/bash
# Builds a universal "AI Quotabar.app" and zips it for a GitHub release.
# Usage: scripts/release.sh 0.2.1
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>}
VERSION=$VERSION scripts/bundle.sh --universal

APP="build/AI Quotabar.app"
rm -f build/AIQuotabar.zip
# ditto keeps the bundle's structure and code signature intact.
ditto -c -k --keepParent "$APP" build/AIQuotabar.zip
echo "Built build/AIQuotabar.zip ($(lipo -archs "$APP/Contents/MacOS/AIQuotabar"))"

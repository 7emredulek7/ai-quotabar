#!/bin/bash
# Builds a universal Headroom.app and zips it for a GitHub release.
# Usage: scripts/release.sh 0.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>}
VERSION=$VERSION scripts/bundle.sh --universal

rm -f build/Headroom.zip
# ditto keeps the bundle's structure and code signature intact.
ditto -c -k --keepParent build/Headroom.app build/Headroom.zip
echo "Built build/Headroom.zip ($(lipo -archs build/Headroom.app/Contents/MacOS/Headroom))"

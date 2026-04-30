#!/bin/sh
# Xcode Cloud: post-clone hook.
# Stamps every target's CFBundleVersion with "<CI_BUILD_NUMBER>.<UTC timestamp>"
# so TestFlight/App Store sees a unique, monotonically-increasing build number.

set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

BUILD_NUM="${CI_BUILD_NUMBER:?CI_BUILD_NUMBER is not set}.$(date -u +%Y%m%d%H%M)"
echo "Setting CFBundleVersion to $BUILD_NUM"

for plist in \
    Grit/Info.plist \
    GritWidget/Info.plist \
    GritShareExtension/Info.plist
do
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUM" "$plist"
    echo "  ✓ $plist"
done

#!/bin/sh
# Stamps a fresh date-serial build number (YYYY.MMDD.HHMM) into
# project.yml's CURRENT_PROJECT_VERSION and regenerates the Xcode
# project. Run before archiving locally — every stamp is guaranteed
# higher than the last, so App Store Connect always accepts the upload.
#
# Every target (app, widget extension, share extension) inherits the
# value through $(CURRENT_PROJECT_VERSION) in its generated Info.plist,
# which keeps their CFBundleVersions matched (App Store validation
# requires it). Xcode Cloud builds are unaffected: ci_scripts/ci_post_clone.sh
# writes its own CI_BUILD_NUMBER-based value straight into the plists.
set -e
cd "$(dirname "$0")/.."

BUILD=$(date +%Y.%m%d.%H%M)
sed -i '' "s/^    CURRENT_PROJECT_VERSION: .*/    CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
xcodegen generate
echo "Build number set to $BUILD — archive away."

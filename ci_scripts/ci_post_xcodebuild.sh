#!/bin/sh
# Xcode Cloud: post-xcodebuild hook.
# Posts a changelog thread to Bluesky after a successful archive.

set -euo pipefail

if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
    echo "Build did not succeed (exit $CI_XCODEBUILD_EXIT_CODE) — skipping Bluesky post."
    exit 0
fi

# Only post for archive actions (i.e. real TestFlight builds), not test runs.
if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    echo "Action is '${CI_XCODEBUILD_ACTION:-unknown}', not archive — skipping Bluesky post."
    exit 0
fi

cd "$CI_PRIMARY_REPOSITORY_PATH"
exec swift ci_scripts/bluesky-changelog.swift

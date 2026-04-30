#!/bin/sh
# Xcode Cloud: post-xcodebuild hook.
#   1. Updates a GitHub gist with a shields.io-compatible JSON so a build
#      status badge in the README reflects the latest run.
#   2. Posts a changelog thread to Bluesky after a successful archive.

set -euo pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

# ── 1. Update build-status gist ─────────────────────────────────────────
# Required env vars (set in Xcode Cloud workflow → Environment, Secret):
#   GH_GIST_TOKEN     – GitHub PAT with `gist` scope only
#   GH_GIST_ID        – ID of the gist that holds the badge JSON
#   GH_GIST_FILENAME  – filename inside the gist (e.g. grit-build.json)
update_badge() {
    if [ -z "${GH_GIST_TOKEN:-}" ] || [ -z "${GH_GIST_ID:-}" ] || [ -z "${GH_GIST_FILENAME:-}" ]; then
        echo "Gist env vars not set — skipping badge update."
        return 0
    fi

    if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" = "0" ]; then
        message="passing"
        color="brightgreen"
    else
        message="failing"
        color="red"
    fi

    label="Xcode Cloud"
    if [ -n "${CI_WORKFLOW:-}" ]; then
        label="Xcode Cloud · $CI_WORKFLOW"
    fi

    payload=$(cat <<EOF
{
  "files": {
    "$GH_GIST_FILENAME": {
      "content": "{\"schemaVersion\":1,\"label\":\"$label\",\"message\":\"$message\",\"color\":\"$color\"}"
    }
  }
}
EOF
)

    http_status=$(curl -sS -o /tmp/gist-resp.json -w "%{http_code}" \
        -X PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer $GH_GIST_TOKEN" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "https://api.github.com/gists/$GH_GIST_ID" \
        -d "$payload")

    if [ "$http_status" = "200" ]; then
        echo "Badge updated: $message"
    else
        echo "Badge update failed (HTTP $http_status):"
        cat /tmp/gist-resp.json
        # Don't fail the build over a badge — this is best-effort.
    fi
}

update_badge

# ── 2. Bluesky changelog (only on successful archive) ───────────────────
if [ "${CI_XCODEBUILD_EXIT_CODE:-1}" != "0" ]; then
    echo "Build did not succeed (exit $CI_XCODEBUILD_EXIT_CODE) — skipping Bluesky post."
    exit 0
fi

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    echo "Action is '${CI_XCODEBUILD_ACTION:-unknown}', not archive — skipping Bluesky post."
    exit 0
fi

exec swift ci_scripts/bluesky-changelog.swift

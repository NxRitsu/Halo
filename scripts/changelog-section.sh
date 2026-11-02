#!/bin/bash
# Prints the section of CHANGELOG.md for a version, such as "0.1.0" or "Unreleased".
# Fails if the section is missing or empty, so a release can't go out without notes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?Usage: changelog-section.sh <version>}

SECTION=$(awk -v header="## [$VERSION]" '
    index($0, "## [") == 1 {
        if (found) exit
        if (index($0, header) == 1) { found = 1; next }
    }
    found
' CHANGELOG.md)

if [ -z "${SECTION//[[:space:]]/}" ]; then
    echo "CHANGELOG.md has no notes for $VERSION" >&2
    exit 1
fi
printf '%s\n' "$SECTION"

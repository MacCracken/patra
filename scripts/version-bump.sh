#!/bin/sh
# Version bump script for patra — single source of truth for all
# version references. Mirrors cyrius's scripts/version-bump.sh
# pattern, tailored to patra's manifest layout.
#
# Usage: ./scripts/version-bump.sh 1.9.0
#
# Why this script exists: pre-1.9.0, patra had no version-bump
# tooling. A bump required hand-editing VERSION + cyrius.cyml +
# CLAUDE.md + CHANGELOG.md. A v1.9.0 bump that updated VERSION
# but not cyrius.cyml landed the CI check
# (`VERSION ($FILE_VERSION) != cyrius.cyml ($CYML_VERSION)`) on
# the path. The cyrius project hit the same shape pre-v5.6.39
# with `cc5 --version` drift; the fix is the same: one script,
# all-or-nothing, no opportunity for the human to forget a site.

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    echo "Current: $(cat VERSION 2>/dev/null || echo '<no VERSION file>')"
    exit 1
fi

NEW="$1"
OLD=$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo '')

if [ -z "$OLD" ]; then
    echo "error: VERSION file missing or empty" >&2
    exit 1
fi

if [ "$NEW" = "$OLD" ]; then
    echo "Already at $OLD (no changes)"
    exit 0
fi

# Sanity: NEW looks like a semver
case "$NEW" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "error: '$NEW' does not look like a semver" >&2; exit 1 ;;
esac

# 1. VERSION file (source of truth)
echo "$NEW" > VERSION

# 2. cyrius.cyml package.version (the field the CI ci.yml pre-flight
#    check compares against VERSION — see .github/workflows/ci.yml).
if [ -f cyrius.cyml ]; then
    sed -i "s/^version = \"$OLD\"/version = \"$NEW\"/" cyrius.cyml
fi

# 3. CLAUDE.md `- **Version**: X.Y.Z` line (cyrius's CLAUDE.md
#    pattern; patra adopted it pre-v1.8.x).
if [ -f CLAUDE.md ]; then
    sed -i "s/^- \*\*Version\*\*: $OLD$/- **Version**: $NEW/" CLAUDE.md
fi

# 4. CHANGELOG.md — add a dated stub if no entry for $NEW yet.
#    Inserts the stub after the file header (line containing
#    "Semantic Versioning"). The stub is intentionally empty so
#    the human author writes the actual Fixed/Changed/Added
#    sections — this script only guarantees the version line
#    appears (CI line 111 requires it).
if [ -f CHANGELOG.md ]; then
    if ! grep -q "## \[$NEW\]" CHANGELOG.md; then
        TODAY=$(date +%Y-%m-%d)
        # Use awk for portable in-place insert
        awk -v new="$NEW" -v today="$TODAY" '
            /^and this project adheres to/ && !inserted {
                print
                print ""
                print "## [" new "] - " today
                print ""
                print "**TODO:** describe this release."
                inserted = 1
                next
            }
            { print }
        ' CHANGELOG.md > CHANGELOG.md.tmp && mv CHANGELOG.md.tmp CHANGELOG.md
    fi
fi

echo "$OLD -> $NEW"
echo ""
echo "Updated:"
echo "  VERSION"
echo "  cyrius.cyml (package.version)"
echo "  CLAUDE.md (Version line)"
if grep -q "## \[$NEW\]" CHANGELOG.md 2>/dev/null; then
    echo "  CHANGELOG.md ([$NEW] entry)"
fi
echo ""
echo "Still manual:"
echo "  - CHANGELOG.md sections (Fixed/Changed/Added)"
echo "  - Regenerate dist: cyrius distlib"
echo "  - Bump cyrius toolchain pin in cyrius.cyml if needed"
echo "    (\`cyrius = \"X.Y.Z\"\` line — separate from package.version)"

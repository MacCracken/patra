#!/usr/bin/env bash
# Bundle patra into a single dist/patra.cyr for stdlib distribution.
# Strips include statements — consumers provide their own stdlib.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(cat "$REPO/VERSION" | tr -d '[:space:]')
OUT="$REPO/dist/patra.cyr"

echo "Bundling patra v${VERSION} -> dist/patra.cyr"

cat > "$OUT" << HEADER
# patra.cyr — structured storage and SQL queries for Cyrius
# Bundled distribution of patra v${VERSION}
# Source: https://github.com/MacCracken/patra
# License: GPL-3.0-only
#
# Usage: include "lib/patra.cyr"
# Init:  alloc_init(); fl_init(); patra_init();
#
# Requires stdlib: syscalls, string, alloc, freelist, io, fmt, str, vec, sakshi

HEADER

# Append each module in dependency order
for mod in file wal page row sql where btree table jsonl; do
    echo "" >> "$OUT"
    echo "# --- ${mod}.cyr ---" >> "$OUT"
    cat "$REPO/src/${mod}.cyr" >> "$OUT"
done

# Append lib.cyr (API entry point) without include lines
echo "" >> "$OUT"
echo "# --- lib.cyr (API) ---" >> "$OUT"
grep -v "^include " "$REPO/src/lib.cyr" >> "$OUT"

LINES=$(wc -l < "$OUT")
echo "Done: ${LINES} lines"

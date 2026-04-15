#!/bin/sh
# Bundle patra into a single dist/patra.cyr for stdlib distribution.
# Usage: sh scripts/bundle.sh
# Output: dist/patra.cyr

set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=$(cat "$ROOT/VERSION" | tr -d '[:space:]')

mkdir -p "$ROOT/dist"

{
echo "# patra.cyr — structured storage and SQL queries for Cyrius"
echo "# Bundled distribution of patra v${VERSION}"
echo "# Source: https://github.com/MacCracken/patra"
echo "# License: GPL-3.0-only"
echo "#"
echo "# Usage: include \"lib/patra.cyr\""
echo "# Init:  alloc_init(); fl_init(); patra_init();"
echo "#"
echo "# Requires stdlib: syscalls, string, alloc, freelist, io, fmt, str, vec, sakshi"
echo ""
for f in src/file.cyr src/wal.cyr src/page.cyr src/row.cyr src/sql.cyr \
         src/where.cyr src/btree.cyr src/table.cyr src/jsonl.cyr src/lib.cyr; do
    echo ""
    echo "# --- $(basename "$f") ---"
    echo ""
    grep -v "^include " "$ROOT/$f"
done
} > "$ROOT/dist/patra.cyr"

echo "dist/patra.cyr: $(wc -l < "$ROOT/dist/patra.cyr") lines (v${VERSION})"

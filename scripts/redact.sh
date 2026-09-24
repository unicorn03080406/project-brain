#!/bin/sh
# Redact credentials from text before it is saved to the brain. The rules are pb_redact in lib.sh.
# Usage: sh redact.sh [report-file] < in > out
# The report gets one line per kind found: "<kind> <count>".
p=$0; case "$p" in *\\*) p=$(printf '%s' "$p" | tr '\\' '/') ;; esac
case "$p" in */*) PB_ROOT=${p%/*}/.. ;; *) PB_ROOT=.. ;; esac
. "$PB_ROOT/scripts/lib.sh"
t=${TMPDIR:-/tmp}; t="${t%/}/pb-redact.$$"
cat > "$t"
pb_redact "$t" "$t.out" "${1:-}"
cat "$t.out"
rm -f "$t" "$t.out"

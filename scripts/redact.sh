#!/bin/sh
# Redact credentials from text before it is saved to the brain.
# Usage: sh redact.sh [report-file] < in > out
# Writes the redacted text to stdout. If a report file is given, writes one line per kind found:
# "<kind> <count>". Patterns use sed -E (POSIX ERE with intervals), which BSD and GNU sed support.
report=${1:-/dev/null}
tmp=${TMPDIR:-/tmp}/pb-redact.$$
cat > "$tmp"
: > "$report"

count() {   # count <kind> <ERE>
  c=$(grep -cE -- "$2" "$tmp" 2>/dev/null)
  [ "${c:-0}" -gt 0 ] && echo "$1 $c" >> "$report"
}
count private-key   '-----BEGIN [A-Z ]*PRIVATE KEY-----'
count aws-key       'AKIA[0-9A-Z]{16}'
count github-token  'gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}'
count slack-token   'xox[abprs]-[A-Za-z0-9-]{10,}'
count api-key       '(sk|rk|pk)[-_](live|test|ant|proj)?[-_]?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}'
count jwt           'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
count bearer        '[Bb]earer [A-Za-z0-9._~+/-]{20,}'
count url-password  '[a-z][a-z0-9+.-]*://[^/:@ ]+:[^/@ ]+@'
count password      '(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)["'"'"']?[[:space:]]*[:=][[:space:]]*[^[:space:]]'

sed -E \
  -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/c\
[REDACTED: private-key]' \
  -e 's/AKIA[0-9A-Z]{16}/[REDACTED: aws-key]/g' \
  -e 's/gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}/[REDACTED: github-token]/g' \
  -e 's/xox[abprs]-[A-Za-z0-9-]{10,}/[REDACTED: slack-token]/g' \
  -e 's/(sk|rk|pk)[-_](live|test|ant|proj)?[-_]?[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{35}/[REDACTED: api-key]/g' \
  -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/[REDACTED: jwt]/g' \
  -e 's/([Bb]earer )[A-Za-z0-9._~+\/-]{20,}/\1[REDACTED: token]/g' \
  -e 's#([a-z][a-z0-9+.-]*://[^/:@ ]+:)[^/@ ]+@#\1[REDACTED: password]@#g' \
  -e 's/((password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|client[_-]?secret)["'"'"']?[[:space:]]*[:=][[:space:]]*)[^[:space:]\[][^[:space:]]*/\1[REDACTED: secret]/gI' \
  "$tmp" 2>/dev/null || sed -E \
  -e 's/((password|passwd|pwd|secret|token|api[_-]?key)[[:space:]]*[:=][[:space:]]*)[^[:space:]]+/\1[REDACTED: secret]/g' "$tmp"
rm -f "$tmp"

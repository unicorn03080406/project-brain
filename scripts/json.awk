# Minimal JSON string reader for project-brain (no jq). Run with LC_ALL=C so bytes pass through.
#
# jget(s, key): decoded value of the first string field "key":"..." in s, or "" if absent.
#   Good for flat hook input and for JSONL transcript lines. Not a general JSON parser: it does
#   not care about nesting, so pick keys that are unique enough.
# jdecode(s, i): decode the JSON string body starting at index i (just after the opening quote);
#   sets JEND to the index of the closing quote.

function jhex(h,    i, c, n) {
  n = 0; h = tolower(h)
  for (i = 1; i <= length(h); i++) { c = index("0123456789abcdef", substr(h, i, 1)) - 1; n = n * 16 + c }
  return n
}

function jutf8(n) {
  if (n < 128) return sprintf("%c", n)
  if (n < 2048) return sprintf("%c%c", 192 + int(n / 64), 128 + n % 64)
  if (n < 65536) return sprintf("%c%c%c", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
  return sprintf("%c%c%c%c", 240 + int(n / 262144), 128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64)
}

function jdecode(s, i,    out, c, e, n, lo, L, j) {
  out = ""; L = length(s)
  while (i <= L) {
    # copy the run of plain characters in one go (much faster than char by char)
    j = i
    while (j <= L) { c = substr(s, j, 1); if (c == "\"" || c == "\\") break; j++ }
    if (j > i) out = out substr(s, i, j - i)
    i = j
    if (i > L) break
    c = substr(s, i, 1)
    if (c == "\"") { JEND = i; return out }
    e = substr(s, i + 1, 1)
    if (e == "n") out = out "\n"
    else if (e == "t") out = out "\t"
    else if (e == "r") out = out "\r"
    else if (e == "b") out = out "\b"
    else if (e == "f") out = out "\f"
    else if (e == "u") {
      n = jhex(substr(s, i + 2, 4)); i += 4
      if (n >= 55296 && n < 56320 && substr(s, i + 2, 2) == "\\u") {   # surrogate pair
        lo = jhex(substr(s, i + 4, 4)); n = 65536 + (n - 55296) * 1024 + (lo - 56320); i += 6
      }
      out = out jutf8(n)
    }
    else out = out e     # \" \\ \/
    i += 2
  }
  JEND = L + 1
  return out
}

function jget(s, key,    p, q, rest) {
  p = index(s, "\"" key "\"")
  while (p > 0) {
    rest = substr(s, p + length(key) + 2)
    if (match(rest, /^[ \t]*:[ \t]*"/)) return jdecode(rest, RLENGTH + 1)
    q = index(rest, "\"" key "\"")
    if (q == 0) break
    p = p + length(key) + 1 + q
  }
  return ""
}

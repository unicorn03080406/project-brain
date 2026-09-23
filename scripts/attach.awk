# Pull attachments out of Claude Code transcript lines (JSONL). Needs json.awk loaded first.
# Only lines typed by a person are read. For each image or document block it writes the payload
# to <out>/<n>.payload and prints a manifest line:
#   <n> TAB <b64|text> TAB <media type> TAB <title or empty> TAB <payload file>
# Run with LC_ALL=C and -v out=<dir>. Blocks look like:
#   {"type":"image","source":{"type":"base64","media_type":"image/png","data":"..."}}
#   {"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"..."},"title":"x.pdf"}
#   {"type":"document","source":{"type":"text","media_type":"text/plain","data":"..."},"title":"x.txt"}

function human() {
  return ($0 ~ /"type":"user"/ && $0 !~ /tool_use_id/ && $0 !~ /"isMeta":true/ &&
          ($0 !~ /"origin":\{"kind":"/ || $0 ~ /"origin":\{"kind":"human"/))
}

function scan(s, marker,    p, rest, m, enc, mime, data, title, t, f) {
  while ((p = index(s, marker)) > 0) {
    rest = substr(s, p + length(marker))
    if (!match(rest, /^\{"type":"(base64|text)","media_type":"[^"]*","data":"/)) { s = rest; continue }
    m = substr(rest, 1, RLENGTH)
    enc = (m ~ /"type":"text"/) ? "text" : "b64"
    mime = m; sub(/^.*"media_type":"/, "", mime); sub(/".*$/, "", mime)
    data = jdecode(rest, RLENGTH + 1)
    rest = substr(rest, JEND + 1)
    title = ""
    t = substr(rest, 1, 400)
    if (index(t, "\"title\":\"") > 0 && index(t, "\"title\":\"") < index(t "{\"type\"", "{\"type\""))
      title = jget(t, "title")
    n++
    f = out "/" n ".payload"
    printf "%s", data > f; close(f)
    gsub(/[\t\n]/, " ", title)
    printf "%d\t%s\t%s\t%s\t%s\n", n, enc, mime, title, f
    s = rest
  }
}

human() {
  scan($0, "{\"type\":\"document\",\"source\":")
  if (images) scan($0, "{\"type\":\"image\",\"source\":")
}

#!/bin/sh
# project-brain hook entry point. Usage (from hooks/hooks.json): sh hook.sh <event>
# Events: session-start, session-end.
# Rules: with no .brain/ in the project, print nothing and exit 0. On any error, exit 0 and
# print nothing: a hook must never block or clutter the session. Errors go to a log file.
PB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)
. "$PB_ROOT/scripts/lib.sh" || exit 0
EVENT=${1:-}
PB_MAX_START=8000   # characters injected at session start (~2k tokens)

errlog() {   # keep hook errors out of the session; one log per plugin install
  d=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}
  mkdir -p "$d" 2>/dev/null && cat >> "$d/project-brain-errors.log" 2>/dev/null
}

# Read the hook's JSON input and pull out the fields we use, in one awk pass.
read_input() {
  IN=$(cat)
  eval "$(printf '%s' "$IN" | LC_ALL=C awk "$(cat "$PB_ROOT/scripts/json.awk")"'
    function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
    { all = all $0 "\n" }
    END {
      printf "SID=%s\nSRC=%s\nIN_CWD=%s\nTRANSCRIPT=%s\n", q(jget(all, "session_id")),
        q(jget(all, "source")), q(jget(all, "cwd")), q(jget(all, "transcript_path"))
    }')"
  SID=${SID:-${CLAUDE_CODE_SESSION_ID:-unknown}}
  S8=$(printf '%s' "$SID" | cut -c1-8)
}

find_brain_or_exit() {
  # The hook's own cwd follows the session's shell, so trust the project dir first.
  BRAIN=$(PB_BRAIN= pb_find_brain "$(pb_path "${IN_CWD:-.}")" 2>/dev/null) || exit 0
  MAP="$BRAIN/MAP.md"
  PROJ=$(pb_project_of "$BRAIN")
}

# --- Session registration -------------------------------------------------------------------

register_session() {
  f="$BRAIN/sessions/$S8.md"
  mkdir -p "$BRAIN/sessions"
  if [ ! -f "$f" ]; then
    sed -e "s|{{SID}}|$S8|g" -e "s|{{TS}}|$(pb_now)|g" "$PB_ROOT/templates/core/session.md" > "$f"
  fi
  # Own file only: status and last start. Other sessions never write here.
  awk -v now="$(pb_now)" -v src="$SRC" '
    /^status:/ && !s { print "status: live"; s = 1; next }
    /^last-start:/ { next }
    /^---$/ && ++dash == 2 { print "last-start: " now " (" src ")" }
    { print }' "$f" | pb_replace "$f"
  mark_seen
  # Later Bash calls in this session know who they are and where the brain is.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    { echo "export BRAIN_SESSION='$S8'"; echo "export PB_BRAIN='$BRAIN'"; } >> "$CLAUDE_ENV_FILE"
  fi
}

# The marker: for every log file, how many lines this session has already been shown.
# Kept in sessions/<id>.seen; its mtime lets the digest skip unchanged files with find -newer.
mark_seen() {
  s="$BRAIN/sessions/$S8.seen"
  (cd "$BRAIN/log" 2>/dev/null && for l in *.md; do [ -f "$l" ] && printf '%s %s\n' "$l" "$(wc -l < "$l" | tr -d ' ')"; done) > "$s.tmp" 2>/dev/null
  mv -f "$s.tmp" "$s"
}

end_session() {
  f="$BRAIN/sessions/$S8.md"
  [ -f "$f" ] || exit 0
  awk -v now="$(pb_now)" '
    /^status:/ && !s { print "status: ended " now; s = 1; next }
    { print }' "$f" | pb_replace "$f"
}

# --- Start summary --------------------------------------------------------------------------

# NOW.md without the header, comments and empty sections; each section capped.
now_summary() {
  awk '
    /^# / { next }
    /^Edit one section|^Label facts/ { next }
    /<!--/ { inc = 1 } inc { if (/-->/) inc = 0; next }
    /^## / { flush(); head = $0; n = 0; body = ""; next }
    /^[[:space:]]*$/ { next }
    head != "" { n++; if (n <= 8) body = body $0 "\n"; else more++ }
    function flush() {
      if (body != "") { printf "#%s\n%s", head, body; if (more) printf "(+%d more lines in .brain/NOW.md)\n", more }
      more = 0
    }
    END { flush() }' "$BRAIN/NOW.md"
}

open_sessions() {
  now=$(pb_epoch)
  for f in "$BRAIN"/sessions/*.md; do
    [ -f "$f" ] || continue
    id=$(basename -- "$f" .md)
    [ "$id" = "$S8" ] && continue
    grep -q '^status: live' "$f" || continue
    # Stale after 24 h without a start or a prompt (the marker file is touched on both).
    seen="$BRAIN/sessions/$id.seen"; [ -f "$seen" ] || seen=$f
    if [ -z "$(find "$seen" -mmin -1440 2>/dev/null)" ]; then continue; fi
    goal=$(awk '/^## Goal/ { g = 1; next } /^## / { g = 0 } g && NF { print; exit }' "$f")
    claims=$(awk '/^## Claims/ { c = 1; next } /^## / { c = 0 } c && /^- / { n++ } END { print n + 0 }' "$f")
    printf -- '- s:%s · %s%s\n' "$id" "${goal:-goal not set}" "$( [ "$claims" -gt 0 ] && echo " · $claims claim(s)")"
  done
}

today_tail() {
  f="$BRAIN/log/$(pb_today).md"
  [ -f "$f" ] || return 0
  awk '/^### / { if (h != "") print h (l != "" ? ": " l : ""); h = substr($0, 5); l = ""; next }
       h != "" && l == "" && NF { l = substr($0, 1, 140) }
       END { if (h != "") print h (l != "" ? ": " l : "") }' "$f" | tail -n 8 | sed 's/^/- /'
}

# Commits in each repo since the Freshness stamp in NOW.md.
repo_drift() {
  awk '/^## Freshness/ { f = 1; next } /^## / { f = 0 } f && /^- repo / { print }' "$BRAIN/NOW.md" |
  while IFS= read -r line; do
    path=$(printf '%s' "$line" | sed -n 's/^- repo \([^ ]*\) · last seen \([0-9a-f]*\).*/\1/p')
    hash=$(printf '%s' "$line" | sed -n 's/^- repo \([^ ]*\) · last seen \([0-9a-f]*\).*/\2/p')
    [ -n "$path" ] && [ -n "$hash" ] || continue
    case "$path" in /*) r=$path ;; *) r="$PROJ/$path" ;; esac
    n=$(git -C "$r" rev-list --count "$hash..HEAD" 2>/dev/null) || { echo "- $path: last-seen commit $hash not found"; continue; }
    [ "$n" -gt 0 ] && echo "- $path: $n new commit(s) since $hash ($(git -C "$r" log -1 --format='%h %ad' --date=short 2>/dev/null))"
  done
}

warnings() {
  fmt=$(pb_map_meta "$MAP" format)
  [ "$fmt" = "$PB_FORMAT" ] || {
    if [ "${fmt:-0}" -lt "$PB_FORMAT" ] 2>/dev/null; then echo "- Brain format $fmt is older than the plugin's ($PB_FORMAT): run /project-brain:init to upgrade."
    else echo "- Brain format $fmt is newer than this plugin ($PB_FORMAT): update the plugin; do not restructure the brain."; fi
  }
  n=$(sh "$PB_ROOT/scripts/brain.sh" map-check 2>/dev/null | grep -c '^ERROR' || true)
  [ "${n:-0}" -gt 0 ] && echo "- MAP.md has $n problem(s): run sh \"$PB_ROOT/scripts/brain.sh\" map-check and fix them."
  if [ "$(pb_map_meta "$MAP" mode)" = private ]; then
    sh "$PB_ROOT/scripts/brain.sh" privacy-check 2>/dev/null | grep -v 'privacy: ok\|not in a git repo' | sed 's/^privacy: /- Privacy: /'
  fi
  grep -q 'inferred: reconstructed' "$BRAIN/NOW.md" 2>/dev/null && echo "- NOW.md is still marked inferred: ask the owner to confirm it when it fits."
  return 0
}

start_summary() {
  name=$(pb_map_meta "$MAP" project)
  echo "# Project brain: ${name:-this project}"
  echo "This project keeps a shared knowledge base in .brain/ (mode: $(pb_map_meta "$MAP" mode)). MAP.md says"
  echo "what lives where. Keep it current as you work, following the project-brain protocol skill."
  echo "You are session s:$S8. Log with: echo \"<text>\" | sh \"$PB_ROOT/scripts/brain.sh\" log --type <type> --session $S8"
  [ "$SRC" = compact ] && echo "(Context was just compacted: this is a fresh summary of the brain.)"
  s=$(now_summary); [ -n "$s" ] && printf '\n## From .brain/NOW.md\n%s\n' "$s"
  s=$(open_sessions); [ -n "$s" ] && printf '\n## Other live sessions (.brain/sessions/)\n%s\n' "$s"
  s=$(today_tail); [ -n "$s" ] && printf '\n## Today in .brain/log/%s.md\n%s\n' "$(pb_today)" "$s"
  s=$(repo_drift); [ -n "$s" ] && printf '\n## Repos changed since last seen (update Freshness in NOW.md after catching up)\n%s\n' "$s"
  s=$(warnings); [ -n "$s" ] && printf '\n## Needs attention\n%s\n' "$s"
  return 0
}

# Cap the injection at PB_MAX_START characters, cutting at a line.
cap() {
  awk -v max="$PB_MAX_START" '{ n += length($0) + 1; if (n > max) { print "(summary cut to fit the budget; read .brain/NOW.md for the rest)"; exit } print }'
}

# ---------------------------------------------------------------------------------------------
main() {
  read_input
  find_brain_or_exit
  case "$EVENT" in
    session-start) register_session; start_summary | cap ;;
    session-end) end_session ;;
    *) ;;
  esac
}

{ main 2>&1 >&3 3>&- | errlog; } 3>&1
exit 0

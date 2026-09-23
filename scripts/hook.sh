#!/bin/sh
# project-brain hook entry point. Usage (from hooks/hooks.json): sh hook.sh <event>
# Events: session-start, session-end, prompt (UserPromptSubmit), stop.
# Rules: with no .brain/ in the project, print nothing and exit 0. On any error, exit 0 and
# print nothing: a hook must never block or clutter the session. Errors go to a log file.
PB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." 2>/dev/null && pwd)
. "$PB_ROOT/scripts/lib.sh" || exit 0
EVENT=${1:-}
PB_MAX_START=8000   # characters injected at session start (~2k tokens)
PB_DIGEST_MAX=6     # log entries shown per prompt before "+N more"

errlog() {   # keep hook errors out of the session; one log per plugin install
  d=${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}
  mkdir -p "$d" 2>/dev/null && cat >> "$d/project-brain-errors.log" 2>/dev/null
}

# Read the hook's JSON input and pull out the fields we use, in one awk pass. The prompt goes
# to a file, never through a shell variable (it can be large and contain anything).
read_input() {
  TMPD=$(mktemp -d 2>/dev/null) || { TMPD="${TMPDIR:-/tmp}/pb.$$"; mkdir -p "$TMPD"; }
  trap 'rm -rf "$TMPD"' EXIT
  cat > "$TMPD/in.json"
  eval "$(LC_ALL=C awk -v pf="$TMPD/prompt.txt" "$(cat "$PB_ROOT/scripts/json.awk")"'
    function q(s) { gsub(/\047/, "\047\\\047\047", s); return "\047" s "\047" }
    { all = all $0 "\n" }
    END {
      printf "SID=%s\nSRC=%s\nIN_CWD=%s\nTRANSCRIPT=%s\nPROMPT_ID=%s\nSCRATCH=%s\n",
        q(jget(all, "session_id")), q(jget(all, "source")), q(jget(all, "cwd")),
        q(jget(all, "transcript_path")), q(jget(all, "prompt_id")), q(jget(all, "scratchpad_dir"))
      printf "%s", jget(all, "prompt") > pf
    }' "$TMPD/in.json")"
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
  init_att
  # Later Bash calls in this session know who they are and where the brain is.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    { echo "export BRAIN_SESSION='$S8'"; echo "export PB_BRAIN='$BRAIN'"; } >> "$CLAUDE_ENV_FILE"
  fi
}

# Attachments already present when a session registers (a resumed chat, a session that predates
# the brain) are not new: remember them so only later ones are captured.
init_att() {
  att="$BRAIN/sessions/$S8.att"
  [ -f "$att" ] && return 0
  : > "$att"
  if [ -n "$SCRATCH" ]; then
    dir="$(dirname -- "$(pb_path "$SCRATCH")")/images"
    for i in "$dir"/*; do [ -f "$i" ] && echo "img $(basename -- "$i")" >> "$att"; done
  fi
  t=$(pb_path "${TRANSCRIPT:-}")
  [ -n "$t" ] && [ -f "$t" ] && echo "tlines $(wc -l < "$t" | tr -d ' ')" >> "$att"
  return 0
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
  # A chat that closed without a single prompt (VS Code opens and closes such sessions on its
  # own) leaves only an empty stub: remove it. It holds no knowledge.
  if ! grep -q '^prompts: [1-9]' "$f" &&
     [ -z "$(awk '/^## (Goal|Claims|Handoff)/ { s = 1; next } /^## / { s = 0 } s && NF' "$f")" ]; then
    rm -f "$f" "$BRAIN/sessions/$S8.seen" "$BRAIN/sessions/$S8.att" "$BRAIN/sessions/$S8.pending"
    exit 0
  fi
  # A closed chat cannot work on anything: release its claims so others can take them.
  if grep -q " · s:$S8 · since " "$BRAIN/NOW.md" 2>/dev/null; then
    n=$(BRAIN_SESSION=$S8 PB_BRAIN=$BRAIN sh "$PB_ROOT/scripts/brain.sh" release --all --session "$S8" 2>/dev/null | sed -n 's/^released: \([0-9]*\).*/\1/p')
    [ "${n:-0}" -gt 0 ] && log_entry status claims "Session closed: released $n claim(s)."
  fi
  grep -q '^status: handed-off' "$f" && exit 0     # keep the handoff status
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


today_tail() {
  f="$BRAIN/log/$(pb_today).md"
  [ -f "$f" ] || return 0
  awk '/^### / { if (h != "") print h (l != "" ? ": " l : ""); h = substr($0, 5); l = ""; next }
       h != "" && l == "" && NF { l = substr($0, 1, 140) }
       END { if (h != "") print h (l != "" ? ": " l : "") }' "$f" | tail -n 8 | sed 's/^/- /'
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
  now=$(pb_epoch)
  x=$(awk -v now="$now" '/^## Claims/ { c = 1; next } /^## / { c = 0 } c && match($0, /\(@[0-9]+\)[[:space:]]*$/) { if (substr($0, RSTART + 2, RLENGTH - 3) + 0 < now) n++ } END { print n + 0 }' "$BRAIN/NOW.md")
  [ "$x" -gt 0 ] && echo "- $x expired claim(s) in NOW.md: clear them with sh \"$PB_ROOT/scripts/brain.sh\" claims --expire."
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

# --- Every prompt: spread (digest) and save (capture) -------------------------------------------

# Count prompts in the session's own file; register quietly if the session predates the plugin.
bump_session() {
  f="$BRAIN/sessions/$S8.md"
  if [ ! -f "$f" ]; then
    mkdir -p "$BRAIN/sessions"
    sed -e "s|{{SID}}|$S8|g" -e "s|{{TS}}|$(pb_now)|g" "$PB_ROOT/templates/core/session.md" > "$f"
    init_att
  fi
  awk '
    /^prompts: / && !d { print "prompts: " ($2 + 1); d = 1; next }
    /^---$/ && ++dash == 2 && !d { print "prompts: 1"; d = 1 }
    { print }' "$f" | pb_replace "$f"
}

# New log entries from other sessions since this session's marker. Updates the marker.
digest() {
  seen="$BRAIN/sessions/$S8.seen"
  [ -f "$seen" ] || { mark_seen; return 0; }     # first prompt without a marker: start from now
  changed=$(find "$BRAIN/log" -name '*.md' -newer "$seen" 2>/dev/null | sort)
  [ -n "$changed" ] || return 0
  # shellcheck disable=SC2086
  awk -v me="s:$S8" -v out="$seen.tmp" -v max="$PB_DIGEST_MAX" '
    FILENAME == ARGV[1] { cnt[$1] = $2; next }
    FNR == 1 { f = FILENAME; sub(/.*\//, "", f); start = (f in cnt) ? cnt[f] : 0 }
    { cnt[f] = FNR }
    FNR <= start { next }
    /^### / {
      want = 0; split(substr($0, 5), p, " · ")
      if (p[2] == me) next
      if ($0 ~ / · backfilled$/) { back++; next }
      t = p[1]; if (t ~ /T[0-9][0-9]:[0-9][0-9]/) { sub(/^[^T]*T/, "", t); t = substr(t, 1, 5) }
      shown++; want = 1
      line[shown] = "- " t " " p[2] " " p[3] (p[4] != "" ? " (" p[4] ")" : "") ": "
      src[shown] = f
      next
    }
    want && NF { line[shown] = line[shown] substr($0, 1, 140); want = 0 }
    END {
      for (k in cnt) print k, cnt[k] > out
      first = shown > max ? shown - max + 1 : 1
      if (shown > max) printf "(+%d earlier entries in .brain/log/)\n", shown - max
      for (i = first; i <= shown; i++) printf "%s [log/%s]\n", line[i], src[i]
      if (back) printf "(+%d backfilled entries)\n", back
    }' "$seen" $changed
  [ -f "$seen.tmp" ] && mv -f "$seen.tmp" "$seen"
  return 0
}

inbox_name() {   # inbox_name <suffix>: a free path in sources/inbox/, no ':' (Windows)
  d="$BRAIN/sources/inbox"; mkdir -p "$d"
  b="$(pb_stamp)-$S8"; n=""; k=1
  while [ -e "$d/$b$n$1" ]; do k=$((k + 1)); n="-$k"; done
  printf '%s\n' "$d/$b$n$1"
}

log_entry() {   # log_entry <type> <tag> <text>
  lf="$BRAIN/log/$(pb_today).md"
  [ -f "$lf" ] || sed "s|{{DAY}}|$(pb_today)|" "$PB_ROOT/templates/core/log-day.md" > "$lf"
  printf '\n### %s · s:%s · %s · %s\n%s\n' "$(pb_now)" "$S8" "$1" "$2" "$3" | pb_append "$BRAIN" "$lf"
}

# If an identical file is already somewhere in sources/, print its path (relative to .brain/).
# Same size first (cheap), then a byte comparison.
same_as() {   # same_as <new file>
  s=$(wc -c < "$1" | tr -d ' ')
  find "$BRAIN/sources" -type f -size "${s}c" ! -path "$1" 2>/dev/null | while IFS= read -r o; do
    if cmp -s "$1" "$o"; then printf '%s\n' "${o#"$BRAIN"/}"; break; fi
  done
}

# Save pasted project material verbatim (secrets redacted) before Claude replies.
capture() {
  [ -s "$TMPD/prompt.txt" ] || return 0
  v=$(LC_ALL=C awk -f "$PB_ROOT/scripts/detect.awk" < "$TMPD/prompt.txt")
  case "$v" in context*) ;; *) return 0 ;; esac
  kind=${v#context }
  f=$(inbox_name .md); rel=${f#"$BRAIN"/}
  sh "$PB_ROOT/scripts/redact.sh" "$TMPD/redacted" < "$TMPD/prompt.txt" > "$TMPD/body"
  red=$(awk '{ printf "%s%s x%s", s, $1, $2; s = ", " }' "$TMPD/redacted")
  lines=$(wc -l < "$TMPD/body" | tr -d ' ')
  {
    echo "---"
    echo "captured: $(pb_now)"
    echo "session: $S8"
    echo "prompt_id: $PROMPT_ID"
    echo "detected: $kind"
    echo "redacted: ${red:-none}"
    echo "---"
    cat "$TMPD/body"
  } > "$f"
  log_entry capture inbox "Saved $rel ($kind, $lines lines${red:+; redacted: $red}). Filing: s:$S8."
  echo "Saved the pasted $kind verbatim to .brain/$rel${red:+ (credentials removed from the saved copy: $red; tell the owner)}."
}

# Pasted images: Claude Code stores them next to the session scratchpad before this hook runs.
images() {
  [ -n "$SCRATCH" ] || return 0
  dir="$(dirname -- "$(pb_path "$SCRATCH")")/images"
  [ -d "$dir" ] || return 0
  att="$BRAIN/sessions/$S8.att"; touch "$att"
  saved=""; dups=""
  for i in "$dir"/*; do
    [ -f "$i" ] || continue
    n=$(basename -- "$i")
    grep -qxF "img $n" "$att" && continue
    f=$(inbox_name "-img-$n"); cp "$i" "$f" && echo "img $n" >> "$att"
    o=$(same_as "$f"); if [ -n "$o" ]; then rm -f "$f"; dups="$dups .brain/$o"; continue; fi
    saved="$saved .brain/${f#"$BRAIN"/}"
  done
  [ -n "$dups" ] && echo "The pasted image(s) were already in the brain, not saved again:$dups."
  [ -n "$saved" ] || return 0
  log_entry capture inbox "Saved pasted image(s):$saved. Filing: s:$S8."
  echo "Saved the pasted image(s) to:$saved."
}

# Attachments found by the Stop hook after the previous reply.
pending() {
  p="$BRAIN/sessions/$S8.pending"
  [ -s "$p" ] || return 0
  echo "Attachments from your previous message: $(awk '{ printf "%s%s", s, $0; s = "; " }' "$p")."
  rm -f "$p"
}

json_out() {   # stdin text -> UserPromptSubmit JSON with additionalContext
  LC_ALL=C awk 'BEGIN { printf "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, ""); gsub(/[\001-\010\013\014\016-\037]/, "")
      printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }
    END { printf "\"}}\n" }'
}

prompt_hook() {
  bump_session
  d=$(digest); c=$(capture); i=$(images); p=$(pending)
  [ -n "$d$c$i$p" ] || return 0
  {
    echo "[project-brain]"
    [ -n "$d" ] && printf 'Other sessions added to the brain since your last prompt:\n%s\n' "$d"
    for s in "$c" "$i" "$p"; do [ -n "$s" ] && echo "$s"; done
    if [ -n "$c$i$p" ]; then
      echo "Do what the owner asked first. Then file what was saved, per the project-brain protocol skill:"
      echo "sort it from sources/inbox/ into the sources/ folder MAP.md names for it, add a line to"
      echo "sources/INDEX.md (and a <file>.md note for images and PDFs), log it, and update the brain"
      echo "files that hold this kind of information. If it is not project material, move it to sources/not-context/."
    fi
  } | json_out
}

# --- After each reply: attachments that only appear in the transcript (PDFs, files) --------------

stop_hook() {
  [ -n "$TRANSCRIPT" ] || return 0
  t=$(pb_path "$TRANSCRIPT"); [ -f "$t" ] || return 0
  # Decoding can take a moment: do it in the background so the session is not held up.
  ( stop_work "$t" ) </dev/null >/dev/null 2>>"${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/project-brain-errors.log" &
}

ext_for() {
  case "$1" in
    application/pdf) echo pdf ;; image/png) echo png ;; image/jpeg) echo jpg ;; image/gif) echo gif ;;
    image/webp) echo webp ;; text/plain) echo txt ;; text/markdown) echo md ;; text/csv) echo csv ;;
    application/json) echo json ;; text/html) echo html ;; *) echo bin ;;
  esac
}

b64dec() { base64 -d 2>/dev/null || base64 -D 2>/dev/null || openssl base64 -d -A; }

stop_work() {
  t=$1
  att="$BRAIN/sessions/$S8.att"; touch "$att"
  from=$(sed -n 's/^tlines //p' "$att" | tail -n 1); from=${from:-0}
  total=$(wc -l < "$t" | tr -d ' ')
  [ "$total" -gt "$from" ] || return 0
  w=$(mktemp -d 2>/dev/null) || { w="${TMPDIR:-/tmp}/pbs.$$"; mkdir -p "$w"; }
  imgs=1
  [ -n "$SCRATCH" ] && [ -d "$(dirname -- "$(pb_path "$SCRATCH")")/images" ] && imgs=0   # already copied by the prompt hook
  tail -n +"$((from + 1))" "$t" | head -n "$((total - from))" |
    LC_ALL=C awk -v out="$w" -v images="$imgs" "$(cat "$PB_ROOT/scripts/json.awk")
$(cat "$PB_ROOT/scripts/attach.awk")" > "$w/manifest"
  saved=""
  while IFS='	' read -r n enc mime title payload; do
    [ -f "$payload" ] || continue
    e=$(ext_for "$mime")
    base=$(printf '%s' "${title:-attachment-$n.$e}" | sed 's/[^A-Za-z0-9._-]/-/g')
    case "$base" in *.*) ;; *) base="$base.$e" ;; esac
    f=$(inbox_name "-$base")
    if [ "$enc" = b64 ]; then b64dec < "$payload" > "$f"
    else sh "$PB_ROOT/scripts/redact.sh" < "$payload" > "$f"; fi
    [ -s "$f" ] || { rm -f "$f"; continue; }
    o=$(same_as "$f"); if [ -n "$o" ]; then rm -f "$f"; echo "already in the brain, not saved again: .brain/$o" >> "$BRAIN/sessions/$S8.pending"; continue; fi
    saved="$saved .brain/${f#"$BRAIN"/}"
  done < "$w/manifest"
  rm -rf "$w"
  echo "tlines $total" >> "$att"
  [ -n "$saved" ] || return 0
  log_entry capture inbox "Saved attachment(s):$saved. Filing: s:$S8."
  echo "saved:$saved" >> "$BRAIN/sessions/$S8.pending"
}

# ---------------------------------------------------------------------------------------------
main() {
  read_input
  find_brain_or_exit
  case "$EVENT" in
    session-start) register_session; start_summary | cap ;;
    session-end) end_session ;;
    prompt) prompt_hook ;;
    stop) stop_hook ;;
    *) ;;
  esac
}

{ main 2>&1 >&3 3>&- | errlog; } 3>&1
exit 0

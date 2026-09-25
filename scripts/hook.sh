#!/bin/sh
# project-brain hook entry point. Usage (from hooks/hooks.json): sh hook.sh <event>
# Events: session-start, session-end, prompt (UserPromptSubmit), stop.
# Rules: with no .brain/ in the project, print nothing and exit 0. On any error, exit 0 and
# print nothing: a hook must never block or clutter the session. Errors go to a log file.
#
# Speed matters: this runs on every prompt in every project. Starting a program costs ~1 ms on
# macOS/Linux but 15-30 ms in Git Bash on Windows, so the common paths use shell built-ins and
# at most one or two awk runs. Keep it that way.

# Git Bash on Windows: put Git's own tools first. Started from cmd (or by a program with the Windows
# PATH order), `find` and `sort` would be Windows' find.exe and sort.exe, which are different
# programs. /usr/bin/cygpath exists only under Git Bash/MSYS, so this costs no program start.
if [ -x /usr/bin/cygpath ] || [ -n "${PB_FORCE_UNIX_PATH:-}" ]; then
  case "$PATH" in /usr/bin:*) ;; *) PATH="/usr/bin:/bin:$PATH"; export PATH ;; esac
fi

# Fast exit, no programs started: is there a .brain/ at or above the project folder?
d=${CLAUDE_PROJECT_DIR:-}
if [ -n "$d" ]; then
  case "$d" in *\\*) d=$(printf '%s' "$d" | tr '\\' '/') ;; esac
  PB_FAST=""
  while [ -n "$d" ]; do
    if [ -f "$d/.brain/MAP.md" ]; then PB_FAST="$d/.brain"; break; fi
    case "$d" in */*) d=${d%/*} ;; *) break ;; esac
  done
  [ -n "$PB_FAST" ] || exit 0
fi

p=$0; case "$p" in *\\*) p=$(printf '%s' "$p" | tr '\\' '/') ;; esac   # Windows passes C:\...
case "$p" in
  */scripts/hook.sh) PB_ROOT=${p%/scripts/hook.sh} ;;
  scripts/hook.sh) PB_ROOT=. ;;
  */*) PB_ROOT=${p%/*}/.. ;;
  *) PB_ROOT=.. ;;
esac
. "$PB_ROOT/scripts/lib.sh" || exit 0
EVENT=${1:-}
PB_MAX_START=8000   # characters injected at session start (~2k tokens)
PB_DIGEST_MAX=6     # log entries shown per prompt before "+N more"
PB_CAPTURE_MIN=120  # shorter prompts are never checked for capture
T=${TMPDIR:-/tmp}; T=${T%/}
PF="$T/pb-prompt.$$"; OUT="$T/pb-out.$$"
trap '[ -e "$PF" ] && rm -f "$PF"; [ -e "$OUT" ] && rm -f "$OUT"' EXIT   # rm only if there is something to remove

# Read the hook's JSON input in one awk run. The prompt goes to a file (only if it is long enough
# to capture), never through a shell variable.
read_input() {
  eval "$(LC_ALL=C awk -v pf="$PF" -v min="$PB_CAPTURE_MIN" -f "$PB_ROOT/scripts/json.awk" -f "$PB_ROOT/scripts/hookin.awk")"
  SID=${SID:-${CLAUDE_CODE_SESSION_ID:-unknown}}
  if [ ${#SID} -gt 8 ]; then S8=${SID%"${SID#????????}"}; else S8=$SID; fi
}

find_brain_or_exit() {
  if [ -n "${PB_FAST:-}" ]; then BRAIN=$PB_FAST
  else BRAIN=$(PB_BRAIN= pb_find_brain "$(pb_path "${IN_CWD:-.}")" 2>/dev/null) || exit 0; fi
  MAP="$BRAIN/MAP.md"
  PROJ=${BRAIN%/.brain}
  SES="$BRAIN/sessions/$S8"
}

now() {   # one date call per run, only when needed: sets NOW (local, with offset) and EPOCH
  [ -n "${NOW:-}" ] && return 0
  set -- $(date '+%Y-%m-%dT%H:%M:%S%z %s'); NOW=$1; EPOCH=$2
}
scratch_images() {   # the folder where Claude Code keeps this session's pasted images
  [ -n "$SCRATCH" ] || return 1
  case "$SCRATCH" in *\\*|?:*) s=$(pb_path "$SCRATCH") ;; *) s=$SCRATCH ;; esac
  IMGDIR="${s%/*}/images"
}

# --- Session registration -------------------------------------------------------------------

new_session_file() {
  now
  [ -d "$BRAIN/sessions" ] || mkdir -p "$BRAIN/sessions"
  sed -e "s|{{SID}}|$S8|g" -e "s|{{TS}}|$NOW|g" "$PB_ROOT/templates/core/session.md" > "$SES.md"
  init_att
}

register_session() {
  [ -f "$SES.md" ] || new_session_file
  now
  # Own file only: status and last start. Other sessions never write here.
  awk -v now="$NOW" -v src="$SRC" '
    /^status:/ && !s { print "status: live"; s = 1; next }
    /^last-start:/ { next }
    /^---$/ && ++dash == 2 { print "last-start: " now " (" src ")" }
    { print }' "$SES.md" > "$SES.md.tmp" && mv -f "$SES.md.tmp" "$SES.md"
  mark_seen
  # Later Bash calls in this session know who they are and where the brain is.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    { echo "export BRAIN_SESSION='$S8'"; echo "export PB_BRAIN='$BRAIN'"; } >> "$CLAUDE_ENV_FILE"
  fi
}

# Attachments already present when a session registers (a resumed chat, a session that predates
# the brain) are not new: remember them so only later ones are captured.
init_att() {
  [ -f "$SES.att" ] && return 0
  : > "$SES.att"
  if scratch_images && [ -d "$IMGDIR" ]; then
    for i in "$IMGDIR"/*; do [ -f "$i" ] && echo "img ${i##*/}" >> "$SES.att"; done
  fi
  t=$(pb_path "${TRANSCRIPT:-}")
  [ -n "$t" ] && [ -f "$t" ] && echo "tlines $(wc -l < "$t" | tr -d ' ')" >> "$SES.att"
  return 0
}

# The marker: for every log file, how many lines this session has already been shown.
mark_seen() {
  set -- "$BRAIN"/log/*.md
  if [ -f "$1" ]; then
    awk '{ c[FILENAME]++ } END { for (f in c) { n = f; sub(/.*\//, "", n); print n, c[f] } }' "$@" > "$SES.seen"
  else
    : > "$SES.seen"
  fi
}

end_session() {
  [ -f "$SES.md" ] || exit 0
  # A chat that closed without a single prompt (VS Code opens and closes such sessions on its
  # own) leaves only an empty stub: remove it. It holds no knowledge.
  if [ ! -s "$SES.prompts" ] &&
     [ -z "$(awk '/^## (Goal|Claims|Handoff)/ { s = 1; next } /^## / { s = 0 } s && NF' "$SES.md")" ]; then
    rm -f "$SES.md" "$SES.seen" "$SES.att" "$SES.pending" "$SES.prompts"
    exit 0
  fi
  # A closed chat cannot work on anything: release its claims so others can take them.
  if grep -q " · s:$S8 · since " "$BRAIN/NOW.md" 2>/dev/null; then
    n=$(BRAIN_SESSION=$S8 PB_BRAIN=$BRAIN sh "$PB_ROOT/scripts/brain.sh" release --all --session "$S8" 2>/dev/null | sed -n 's/^released: \([0-9]*\).*/\1/p')
    [ "${n:-0}" -gt 0 ] && log_entry status claims "Session closed: released $n claim(s)."
  fi
  grep -q '^status: handed-off' "$SES.md" && exit 0     # keep the handoff status
  now
  awk -v now="$NOW" '/^status:/ && !s { print "status: ended " now; s = 1; next } { print }' "$SES.md" \
    > "$SES.md.tmp" && mv -f "$SES.md.tmp" "$SES.md"
}

# --- Start summary --------------------------------------------------------------------------

# MAP meta, NOW.md sections, expired claims and the inferred flag, in one awk run.
now_and_meta() {
  now
  awk -v now_epoch="$EPOCH" -v metaf="$T/pb-meta.$$" '
    FILENAME == ARGV[1] {
      if (/^```brain-map/) { inb = 1; next }
      if (inb && /^```/) { inb = 0; next }
      if (inb && $0 !~ /\|/ && match($0, /^[a-z]+: /)) { k = substr($0, 1, RLENGTH - 2); meta[k] = substr($0, RLENGTH + 1) }
      next
    }
    /^# / || /^Edit one section/ || /^Label facts/ { next }
    /<!--/ { inc = 1 } inc { if (/-->/) inc = 0; next }
    /^## / { flush(); head = $0; sec = substr($0, 4); n = 0; body = ""; next }
    /inferred: reconstructed/ { inferred = 1 }
    sec == "Claims" && match($0, /\(@[0-9]+\)[[:space:]]*$/) { if (substr($0, RSTART + 2, RLENGTH - 3) + 0 < now_epoch) expired++ }
    /^[[:space:]]*$/ { next }
    head != "" { n++; if (n <= 8) body = body $0 "\n"; else more++ }
    function flush() {
      if (body != "") { if (!shown++) printf "\n## From .brain/NOW.md\n"
        printf "#%s\n%s", head, body; if (more) printf "(+%d more lines in .brain/NOW.md)\n", more }
      more = 0
    }
    END {
      flush()
      printf "%s\n%s\n%s\n%s\n%s\n", meta["project"], meta["mode"], meta["format"], expired + 0, inferred + 0 > metaf
    }' "$MAP" "$BRAIN/NOW.md"
}

today_tail() {
  now; f="$BRAIN/log/${NOW%%T*}.md"
  [ -f "$f" ] || return 0
  awk -v day="${NOW%%T*}" '
    /^### / { if (h != "") keep(); h = substr($0, 5); l = ""; next }
    h != "" && l == "" && NF { l = substr($0, 1, 140) }
    function keep() { r[++n] = "- " h (l != "" ? ": " l : "") }
    END { if (h != "") keep(); if (!n) exit
          printf "\n## Today in .brain/log/%s.md\n", day
          for (i = (n > 8 ? n - 7 : 1); i <= n; i++) print r[i] }' "$f"
}

start_summary() {
  now_and_meta > "$T/pb-now.$$"
  { read -r name; read -r mode; read -r fmt; read -r expired; read -r inferred; } < "$T/pb-meta.$$"
  echo "# Project brain: ${name:-this project}"
  echo "This project keeps a shared knowledge base in .brain/ (mode: $mode). MAP.md says"
  echo "what lives where. Keep it current as you work, following the project-brain protocol skill."
  echo "You are session s:$S8. Log with: echo \"<text>\" | sh \"$PB_ROOT/scripts/brain.sh\" log --type <type> --session $S8"
  [ "$SRC" = compact ] && echo "(Context was just compacted: this is a fresh summary of the brain.)"
  cat "$T/pb-now.$$"
  s=$(open_sessions); [ -n "$s" ] && printf '\n## Other live sessions (.brain/sessions/)\n%s\n' "$s"
  today_tail
  s=$(repo_drift); [ -n "$s" ] && printf '\n## Repos changed since last seen (update Freshness in NOW.md after catching up)\n%s\n' "$s"
  {
    if [ "$fmt" != "$PB_FORMAT" ]; then
      if [ "${fmt:-0}" -lt "$PB_FORMAT" ] 2>/dev/null; then echo "- Brain format $fmt is older than the plugin's ($PB_FORMAT): run /project-brain:init to upgrade."
      else echo "- Brain format $fmt is newer than this plugin ($PB_FORMAT): update the plugin; do not restructure the brain."; fi
    fi
    [ "$mode" = private ] && sh "$PB_ROOT/scripts/brain.sh" privacy-check 2>/dev/null | grep -v 'privacy: ok\|not in a git repo' | sed 's/^privacy: /- Privacy: /'
    [ "${expired:-0}" -gt 0 ] && echo "- $expired expired claim(s) in NOW.md: clear them with sh \"$PB_ROOT/scripts/brain.sh\" claims --expire."
    [ "${inferred:-0}" = 1 ] && echo "- NOW.md is still marked inferred: ask the owner to confirm it when it fits."
  } > "$T/pb-warn.$$"
  [ -s "$T/pb-warn.$$" ] && { printf '\n## Needs attention\n'; cat "$T/pb-warn.$$"; }
  rm -f "$T/pb-now.$$" "$T/pb-meta.$$" "$T/pb-warn.$$"
  return 0
}

# Cap the injection at PB_MAX_START characters, cutting at a line.
cap() {
  awk -v max="$PB_MAX_START" '{ n += length($0) + 1; if (n > max) { print "(summary cut to fit the budget; read .brain/NOW.md for the rest)"; exit } print }'
}

# --- Every prompt: spread (digest) and save (capture) -------------------------------------------
# Each part appends what the session should hear to $OUT. No output file, no JSON.

# New log entries from other sessions since this session's marker. Updates the marker.
digest() {
  [ -f "$SES.seen" ] || { mark_seen; return 0; }     # first prompt without a marker: start from now
  set --
  for l in "$BRAIN"/log/*.md; do
    # a log file changed if it is not older than the marker (equal seconds count as changed)
    [ -f "$l" ] && ! [ "$SES.seen" -nt "$l" ] && set -- "$@" "$l"
  done
  [ $# -gt 0 ] || return 0
  awk -v me="s:$S8" -v out="$SES.seen" -v max="$PB_DIGEST_MAX" -v res="$OUT" '
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
      if (!shown && !back) exit
      print "Other sessions added to the brain since your last prompt:" >> res
      first = shown > max ? shown - max + 1 : 1
      if (shown > max) printf "(+%d earlier entries in .brain/log/)\n", shown - max >> res
      for (i = first; i <= shown; i++) printf "%s [log/%s]\n", line[i], src[i] >> res
      if (back) printf "(+%d backfilled entries)\n", back >> res
    }' "$SES.seen" "$@"
}

inbox_name() {   # inbox_name <suffix>: sets INBOX to a free path in sources/inbox/ (no ':', Windows)
  now   # ib_* names: callers use n, d, f, ... (shell variables are global)
  ib_x=${NOW%[-+]*}; ib_d=${ib_x%%T*}; ib_t=${ib_x#*T}   # 20260923-101433 from NOW, no program
  ib_r=${ib_d#*-}; ib_m=${ib_t#*:}
  ib_b="${ib_d%%-*}${ib_r%%-*}${ib_r#*-}-${ib_t%%:*}${ib_m%%:*}${ib_m#*:}-$S8"
  ib_dir="$BRAIN/sources/inbox"; [ -d "$ib_dir" ] || mkdir -p "$ib_dir"
  ib_n=""; ib_k=1
  while [ -e "$ib_dir/$ib_b$ib_n$1" ]; do ib_k=$((ib_k + 1)); ib_n="-$ib_k"; done
  INBOX="$ib_dir/$ib_b$ib_n$1"
}

log_entry() {   # log_entry <type> <tag> <text>: one locked append, no temp files
  now; day=${NOW%%T*}; lf="$BRAIN/log/$day.md"
  [ -f "$lf" ] || sed "s|{{DAY}}|$day|" "$PB_ROOT/templates/core/log-day.md" > "$lf"
  pb_lock "$BRAIN" append || return 0
  printf '\n### %s · s:%s · %s · %s\n%s\n' "$NOW" "$S8" "$1" "$2" "$3" >> "$lf"
  pb_unlock "$BRAIN" append
}

# If an identical file is already somewhere in sources/, print its path (relative to .brain/).
same_as() {   # same_as <new file>
  s=$(wc -c < "$1" | tr -d ' ')
  find "$BRAIN/sources" -type f -size "${s}c" ! -path "$1" 2>/dev/null | while IFS= read -r o; do
    if cmp -s "$1" "$o"; then printf '%s\n' "${o#"$BRAIN"/}"; break; fi
  done
}

# Save pasted project material verbatim (secrets redacted) before Claude replies.
capture() {
  [ "${PLEN:-0}" -ge "$PB_CAPTURE_MIN" ] && [ -s "$PF" ] || return 0
  v=$(LC_ALL=C awk -f "$PB_ROOT/scripts/detect.awk" < "$PF")
  case "$v" in context*) ;; *) return 0 ;; esac
  kind=${v#context }
  inbox_name .md; f=$INBOX; rel=${f#"$BRAIN"/}
  pb_redact "$PF" "$T/pb-body.$$" "$T/pb-red.$$"
  red=""; while read -r rk rc; do red="${red:+$red, }$rk x$rc"; done < "$T/pb-red.$$"
  {
    echo "---"
    echo "captured: $NOW"
    echo "session: $S8"
    echo "prompt_id: $PROMPT_ID"
    echo "detected: $kind"
    echo "redacted: ${red:-none}"
    echo "---"
    cat "$T/pb-body.$$"
  } > "$f"
  rm -f "$T/pb-red.$$" "$T/pb-body.$$"
  log_entry capture inbox "Saved $rel ($kind${red:+; redacted: $red}). Filing: s:$S8."
  echo "Saved the pasted $kind verbatim to .brain/$rel${red:+ (credentials removed from the saved copy: $red; tell the owner)}." >> "$OUT"
  FILED=1
}

# Pasted images: Claude Code stores them next to the session scratchpad before this hook runs.
images() {
  scratch_images && [ -d "$IMGDIR" ] || return 0
  saved=""; dups=""
  for i in "$IMGDIR"/*; do
    [ -f "$i" ] || continue
    n=${i##*/}
    grep -qxF "img $n" "$SES.att" 2>/dev/null && continue
    inbox_name "-img-$n"; f=$INBOX; cp "$i" "$f" && echo "img $n" >> "$SES.att"
    o=$(same_as "$f"); if [ -n "$o" ]; then rm -f "$f"; dups="$dups .brain/$o"; continue; fi
    saved="$saved .brain/${f#"$BRAIN"/}"
  done
  [ -n "$dups" ] && echo "The pasted image(s) were already in the brain, not saved again:$dups." >> "$OUT"
  [ -n "$saved" ] || return 0
  log_entry capture inbox "Saved pasted image(s):$saved. Filing: s:$S8."
  echo "Saved the pasted image(s) to:$saved." >> "$OUT"
  FILED=1
}

# Attachments found by the Stop hook after the previous reply.
pending() {
  [ -s "$SES.pending" ] || return 0
  { printf 'Attachments from your previous message: '
    awk '{ printf "%s%s", s, $0; s = "; " } END { print "." }' "$SES.pending"; } >> "$OUT"
  rm -f "$SES.pending"
  FILED=1
}

json_out() {   # stdin text -> UserPromptSubmit JSON with additionalContext
  LC_ALL=C awk 'BEGIN { printf "{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"" }
    { gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); gsub(/\t/, "\\t"); gsub(/\r/, ""); gsub(/[\001-\010\013\014\016-\037]/, "")
      printf "%s%s", (NR > 1 ? "\\n" : ""), $0 }
    END { printf "\"}}\n" }'
}

prompt_hook() {
  [ -f "$SES.md" ] || new_session_file            # a session that predates the plugin
  echo >> "$SES.prompts"                          # count prompts (no program started)
  FILED=""
  digest; capture; images; pending
  [ -s "$OUT" ] || return 0
  {
    echo "[project-brain]"
    cat "$OUT"
    if [ -n "$FILED" ]; then
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
  ( stop_work "$t" ) </dev/null >/dev/null 2>>"$ERRF" &
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
  [ -f "$SES.att" ] || : > "$SES.att"
  from=$(sed -n 's/^tlines //p' "$SES.att" | tail -n 1); from=${from:-0}
  total=$(wc -l < "$t" | tr -d ' ')
  [ "$total" -gt "$from" ] || return 0
  w=$(mktemp -d 2>/dev/null) || { w="$T/pbs.$$"; mkdir -p "$w"; }
  imgs=1
  scratch_images && [ -d "$IMGDIR" ] && imgs=0   # already copied by the prompt hook
  tail -n +"$((from + 1))" "$t" | head -n "$((total - from))" |
    LC_ALL=C awk -v out="$w" -v images="$imgs" -f "$PB_ROOT/scripts/json.awk" -f "$PB_ROOT/scripts/attach.awk" > "$w/manifest"
  saved=""
  while IFS='	' read -r n enc mime title payload; do
    [ -f "$payload" ] || continue
    e=$(ext_for "$mime")
    base=$(printf '%s' "${title:-attachment-$n.$e}" | sed 's/[^A-Za-z0-9._-]/-/g')
    case "$base" in *.*) ;; *) base="$base.$e" ;; esac
    inbox_name "-$base"; f=$INBOX
    if [ "$enc" = b64 ]; then b64dec < "$payload" > "$f"
    else pb_redact "$payload" "$f"; fi
    [ -s "$f" ] || { rm -f "$f"; continue; }
    o=$(same_as "$f"); if [ -n "$o" ]; then rm -f "$f"; echo "already in the brain, not saved again: .brain/$o" >> "$SES.pending"; continue; fi
    saved="$saved .brain/${f#"$BRAIN"/}"
  done < "$w/manifest"
  rm -rf "$w"
  echo "tlines $total" >> "$SES.att"
  [ -n "$saved" ] || return 0
  log_entry capture inbox "Saved attachment(s):$saved. Filing: s:$S8."
  echo "saved:$saved" >> "$SES.pending"
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

# Errors go to a log file, never into the session.
ERRF="${CLAUDE_PLUGIN_DATA:-$T}/project-brain-errors.log"
[ -d "${ERRF%/*}" ] || mkdir -p "${ERRF%/*}" 2>/dev/null
main 2>>"$ERRF"
exit 0

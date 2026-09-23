#!/bin/sh
# project-brain command-line helper. Skills call it; you can too.
# Usage: sh brain.sh <command> [args]. Run with no command for the list.
set -u
PB_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$PB_ROOT/scripts/lib.sh"

usage() {
  cat <<'EOF'
project-brain helper. Commands:
  detect [dir]                  what is here: brain, git, workspace size, intake, memory (read-only)
  inventory [dir] [--limit N]   read-only survey of a workspace, for adopting it
  scaffold <dir> --name N --mode private|shared
                                create the fixed core in <dir>/.brain (refuses if present)
  add "path|tier|kind|holds|read when"
                                add a row to MAP.md and create the file or folder (seeded if a
                                starter file exists). kind ext: link only, nothing is created
  claude-block [--dry-run]      write the import block for auto-tier files into CLAUDE.md (shared)
                                or CLAUDE.local.md (private), backing up the file first
  git-hide                      keep the brain out of git via .git/info/exclude (private mode)
  map-check                     check MAP.md against the files on disk
  budget                        estimate the auto tier's size against the ~3k token budget
  log --type T [--tag X] [--session S] [--date YYYY-MM-DD [--time HH:MM]]
                                append one log entry (text on stdin); --date marks it backfilled
  snapshot [dir]                checksum every workspace file outside the brain (for no-change checks)
  privacy-check                 warn if brain or Claude traces could reach the git remote
  transcripts [dir] [N]        list past sessions for this folder (only with the owner's permission)
  transcript <id|file> [--all] [--max N]
                                print one session's prompts (and replies with --all), shortened
Claims and structure (split, merge, move and retire need a claim; the fixed core is off limits):
  claim "<what>" [--hours N]    claim work or a structure change (default 4 h); refused if it overlaps
  release "<what>" | --all      release this session's claims
  claims [--expire]             list claims; --expire clears expired ones
  move <old> <new> --why "..."  rename a brain file or folder; MAP.md, CLAUDE block, references follow
  retire <path> --why "..."     move to archive/ (or drop a link row); MAP.md and references follow
  retier <path> <tier>          change a file's load tier; CLAUDE block and budget follow
  refs-check                    paths mentioned in brain files that no longer exist
Work:
  capture [file] [--kind K]     save a file (or text on stdin) to sources/inbox/, redacted, not twice
  catchup [--since DATE]        everything other sessions did since this session started
  tidy-report                   sizes, budget, stale, empty, overlaps, inbox, claims, links, privacy
  upgrade [--dry-run]           bring the brain to the plugin's format, step by step
  session-status <state>        mark this session live, handed-off or ended
Most commands take --session <id> (or use $BRAIN_SESSION, set by the start hook).
Other:
  slug [dir]                    Claude Code's folder name for this workspace under ~/.claude/projects
  find                          print the brain folder, or exit 1
  version                       plugin version and brain format
Brain location: found from $PB_BRAIN, $CLAUDE_PROJECT_DIR or by walking up from the current folder.
EOF
}

need_brain() {
  BRAIN=$(pb_find_brain) || pb_die "no brain found (run /project-brain:init first)"
  MAP="$BRAIN/MAP.md"
  PROJ=$(pb_project_of "$BRAIN")
}

# ---------------------------------------------------------------------------------------------
cmd_detect() {
  dir=$(CDPATH= cd -- "$(pb_path "${1:-.}")" 2>/dev/null && pwd) || pb_die "no such folder: ${1:-.}"
  echo "project: $dir"
  echo "plugin: $(pb_version) (brain format $PB_FORMAT)"
  if b=$(PB_BRAIN= CLAUDE_PROJECT_DIR= pb_find_brain "$dir"); then
    echo "brain: $b"
    echo "brain-format: $(pb_map_meta "$b/MAP.md" format)"
    echo "brain-mode: $(pb_map_meta "$b/MAP.md" mode)"
  else
    echo "brain: none"
  fi
  if top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
    echo "git: inside repo $top"
    echo "git-remote: $(git -C "$dir" remote get-url origin 2>/dev/null || echo none)"
  else
    echo "git: not a repo"
  fi
  nrepos=$(find "$dir" -mindepth 2 -maxdepth 4 -name .git 2>/dev/null | grep -c . || true)
  echo "nested-repos: $nrepos"
  files=$(pb_find_files "$dir" | grep -v '/\.claude/' | grep -v '/\.brain/' | grep -v '/sources/intake/' | grep -v '/intake/' | grep -c . || true)
  echo "workspace-files: $files (excluding .claude/ and intake folders)"
  for i in sources/intake intake .brain/sources/intake; do
    [ -d "$dir/$i" ] && echo "intake: $dir/$i ($(find "$dir/$i" -type f | grep -c . || true) files)"
  done
  for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md; do
    [ -f "$dir/$f" ] && echo "found: $f ($(wc -l < "$dir/$f" | tr -d ' ') lines)"
  done
  slug=$(pb_slug "${top:-$dir}")
  mem="$HOME/.claude/projects/$slug/memory"
  [ -d "$mem" ] && echo "auto-memory: $mem ($(find "$mem" -type f | grep -c . || true) files)"
  tdir="$HOME/.claude/projects/$(pb_slug "$dir")"
  if [ -d "$tdir" ]; then
    n=$(find "$tdir" -maxdepth 1 -name '*.jsonl' | grep -c . || true)
    echo "transcripts: $tdir ($n sessions; not read without permission)"
  fi
  if [ "$files" -le 3 ]; then echo "suggested-mode: NEW"; else echo "suggested-mode: ADOPT"; fi
  if grep -q '"attribution"' "$HOME/.claude/settings.json" 2>/dev/null; then
    echo "claude-credit-in-commits: configured in ~/.claude/settings.json"
  else
    echo "claude-credit-in-commits: default (Claude Code adds Co-Authored-By and 'Generated with Claude Code')"
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------
cmd_inventory() {
  dir=.; limit=40
  while [ $# -gt 0 ]; do
    case "$1" in --limit) limit=$2; shift 2 ;; *) dir=$1; shift ;; esac
  done
  dir=$(CDPATH= cd -- "$(pb_path "$dir")" && pwd) || exit 1
  echo "# Inventory of $dir"
  echo "(read-only; each list capped at $limit entries)"
  echo
  echo "## Git repos"
  find "$dir" -maxdepth 4 -name .git 2>/dev/null | sort | while read -r g; do
    r=$(dirname -- "$g")
    echo "### ${r#"$dir"/}"
    [ "$r" = "$dir" ] && echo "(the workspace itself)"
    echo "remote: $(git -C "$r" remote get-url origin 2>/dev/null || echo none)"
    echo "branch: $(git -C "$r" branch --show-current 2>/dev/null)"
    n=$(git -C "$r" rev-list --count HEAD 2>/dev/null || echo 0)
    echo "commits: $n; first: $(git -C "$r" log --reverse --format=%ad --date=short 2>/dev/null | head -n 1); last: $(git -C "$r" log -1 --format=%ad --date=short 2>/dev/null)"
    echo "authors: $(git -C "$r" log --format=%an 2>/dev/null | sort | uniq -c | sort -rn | head -n 5 | awk '{c=$1; $1=""; printf "%s%s (%s)", sep, substr($0,2), c; sep=", "}')"
    # stop at the first hit: macOS and Windows file names ignore case
    for rd in README.md README README.txt readme.md; do [ -f "$r/$rd" ] && { echo "readme: ${r#"$dir"/}/$rd"; break; }; done
    echo "recent commits:"
    git -C "$r" log -n "$limit" --format='  %ad %h %s' --date=short 2>/dev/null
    echo
  done
  echo "## Instructions and memory"
  for f in CLAUDE.md CLAUDE.local.md .claude/CLAUDE.md AGENTS.md; do
    [ -f "$dir/$f" ] && echo "- $f ($(wc -l < "$dir/$f" | tr -d ' ') lines)"
  done
  find "$dir" -mindepth 2 -maxdepth 4 \( -name CLAUDE.md -o -name AGENTS.md \) ! -path '*/node_modules/*' 2>/dev/null | sed "s|^$dir/|- |"
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || echo "$dir")
  mem="$HOME/.claude/projects/$(pb_slug "$top")/memory"
  [ -d "$mem" ] && find "$mem" -type f | sed 's/^/- auto-memory: /'
  tdir="$HOME/.claude/projects/$(pb_slug "$dir")"
  if [ -d "$tdir" ]; then
    echo "- transcripts: $(find "$tdir" -maxdepth 1 -name '*.jsonl' | grep -c . || true) in $tdir (ask before reading)"
  fi
  echo
  echo "## Dated files (name contains a date), oldest first"
  pb_find_files "$dir" | grep -v -e "^$dir/.claude/" -e "^$dir/.brain/" \
    | awk '{ n = $0; sub(/.*\//, "", n)
             if (match(n, /(19|20)[0-9][0-9][-_.]?[01][0-9][-_.]?[0-3][0-9]/)) {
               d = substr(n, RSTART, RLENGTH); gsub(/[-_.]/, "", d)
               print substr(d,1,4) "-" substr(d,5,2) "-" substr(d,7,2) "  " $0 } }' \
    | sort | head -n "$limit" | sed "s|  $dir/|  |"
  echo
  echo "## Documents outside repos, by folder"
  pb_find_files "$dir" 6 | grep -v -e "^$dir/.claude/" -e "^$dir/.brain/" \
    | grep -iE '\.(md|txt|pdf|docx?|pptx?|xlsx?|csv|eml|vtt|srt|rtf|html?|png|jpe?g)$' \
    | while read -r f; do
        in_repo=0; p=$(dirname -- "$f")
        while [ "$p" != "$dir" ] && [ "$p" != "/" ]; do [ -d "$p/.git" ] && { in_repo=1; break; }; p=$(dirname -- "$p"); done
        [ $in_repo = 0 ] && printf '%s\n' "${f#"$dir"/}"
      done | awk -F/ '{ d = (NF > 1) ? $1 : "."; c[d]++; if (c[d] <= 8) l[d] = l[d] "\n  " $0 }
                    END { for (d in c) printf "- %s/ (%d files)%s\n", d, c[d], l[d] }'
  echo
  echo "## Size"
  bytes=$(pb_find_files "$dir" | grep -v -e "^$dir/.claude/" -e "^$dir/.brain/" | grep -iE '\.(md|txt|eml|vtt|srt|csv)$' | while read -r f; do wc -c < "$f"; done | awk '{s+=$1} END {print s+0}')
  echo "text notes: about $((bytes / 4)) tokens in total (read in passes if large)"
}

# ---------------------------------------------------------------------------------------------
# Past sessions. Only used by init when the owner allows it.
tdir_of() { printf '%s\n' "$HOME/.claude/projects/$(pb_slug "$1")"; }

# awk: is this JSONL line a message typed by a person? (newer transcripts tag origin.kind)
PB_HUMAN_AWK='function is_human() { return (/"type":"user"/ && !/tool_use_id/ && !/"isMeta":true/ && (!/"origin":\{"kind":"/ || /"origin":\{"kind":"human"/)) }'

cmd_transcripts() {   # list sessions, newest first: date, size, first prompt
  dir=$(CDPATH= cd -- "$(pb_path "${1:-.}")" && pwd) || exit 1
  td=$(tdir_of "$dir")
  [ -d "$td" ] || { echo "no transcripts for $dir"; return 0; }
  ls -t "$td"/*.jsonl 2>/dev/null | head -n "${2:-30}" | while read -r f; do
    LC_ALL=C awk -v f="$(basename -- "$f" .jsonl)" -v kb="$(( $(wc -c < "$f") / 1024 ))" "
      $(cat "$PB_ROOT/scripts/json.awk")
$PB_HUMAN_AWK"'
      is_human() {
        t = jget($0, "timestamp"); if (first == "") first = substr(t, 1, 10); last = substr(t, 1, 10)
        n++; if (p == "") { p = jget($0, "text"); if (p == "") p = jget($0, "content") }
      }
      END { gsub(/[ \t\r\n]+/, " ", p); printf "%s  %s..%s  %d prompts  %d KB  %s\n", f, first, last, n, kb, substr(p, 1, 120) }' "$f"
  done
}

cmd_transcript() {    # one session: prompts (and replies with --all), each cut to --max chars
  f=""; all=0; max=600
  while [ $# -gt 0 ]; do
    case "$1" in --all) all=1; shift ;; --max) max=$2; shift 2 ;; *) f=$1; shift ;; esac
  done
  [ -f "$f" ] || { td=$(tdir_of "$(pwd)"); f="$td/$f.jsonl"; }
  [ -f "$f" ] || pb_die "no such transcript: $f"
  LC_ALL=C awk -v all="$all" -v max="$max" "$(cat "$PB_ROOT/scripts/json.awk")
$PB_HUMAN_AWK"'
    { who = is_human() ? "USER" : ((all && /"type":"assistant"/) ? "CLAUDE" : "") }
    who != "" {
      x = jget($0, "text"); if (x == "" && who == "USER") x = jget($0, "content")
      if (x == "") next
      if (length(x) > max) x = substr(x, 1, max) " [...]"
      print "--- " who " " substr(jget($0, "timestamp"), 1, 16); print x
    }' "$f"
}

# ---------------------------------------------------------------------------------------------
fill() { sed -e "s|{{PROJECT}}|$name|g" -e "s|{{MODE}}|$mode|g" -e "s|{{DATE}}|$(pb_today)|g" \
             -e "s|{{VERSION}}|$(pb_version)|g" -e "s|{{STATUS}}|$status|g" "$1"; }

cmd_scaffold() {
  dir=""; name=""; mode=""
  status="new: filled from the intake, confirm with the owner"
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) name=$2; shift 2 ;;
      --mode) mode=$2; shift 2 ;;
      --adopt) status="inferred: reconstructed from the workspace, NOT yet confirmed by the owner"; shift ;;
      *) dir=$1; shift ;;
    esac
  done
  [ -n "$dir" ] && [ -n "$name" ] || pb_die "usage: scaffold <dir> --name N --mode private|shared"
  case "$mode" in private|shared) ;; *) pb_die "--mode must be private or shared" ;; esac
  name=$(printf '%s' "$name" | tr -d '|\n' | sed 's/[&\\]/ and /g')
  dir=$(CDPATH= cd -- "$dir" && pwd) || exit 1
  b="$dir/.brain"
  [ -f "$b/MAP.md" ] && pb_die "a brain already exists at $b; it is never overwritten"
  mkdir -p "$b/log" "$b/sources/inbox" "$b/sources/not-context" "$b/sessions" "$b/archive" || exit 1
  fill "$PB_ROOT/templates/core/MAP.md" > "$b/MAP.md"
  fill "$PB_ROOT/templates/core/NOW.md" > "$b/NOW.md"
  cp "$PB_ROOT/templates/core/INDEX.md" "$b/sources/INDEX.md"
  echo "$b"
}

# ---------------------------------------------------------------------------------------------
cmd_add() {
  need_brain
  row=$1
  path=$(printf '%s' "$row" | awk -F'|' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1}')
  tier=$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/, "", $2); print $2}')
  kind=$(printf '%s' "$row" | awk -F'|' '{gsub(/[[:space:]]/, "", $3); print $3}')
  [ "$(printf '%s' "$row" | awk -F'|' '{print NF}')" -eq 5 ] || pb_die "row needs 5 fields: path|tier|kind|holds|read when"
  case "$tier" in auto|inject|demand) ;; *) pb_die "tier must be auto, inject or demand" ;; esac
  case "$kind" in file|dir|ext) ;; core) pb_die "core rows are fixed" ;; *) pb_die "kind must be file, dir or ext" ;; esac
  case "$path" in /*|*..*) [ "$kind" = ext ] || pb_die "brain paths are relative and stay inside the brain" ;; esac
  [ "$kind" = dir ] && case "$path" in */) ;; *) path="$path/" ;; esac
  [ "$kind" = ext ] && case "$path" in @ext:*) ;; *) path="@ext:$path" ;; esac
  pb_map_has "$MAP" "$path" && { echo "already mapped: $path"; return 0; }
  case "$kind" in
    file) if [ ! -e "$BRAIN/$path" ]; then
            mkdir -p "$(dirname -- "$BRAIN/$path")"
            seed="$PB_ROOT/templates/files/$(basename -- "$path")"
            if [ -f "$seed" ]; then cp "$seed" "$BRAIN/$path"
            else printf '# %s\n' "$(basename -- "$path" .md)" > "$BRAIN/$path"; fi
          fi ;;
    dir) mkdir -p "$BRAIN/$path" ;;
    ext) [ -e "$PROJ/${path#@ext:}" ] || pb_warn "linked file does not exist yet: ${path#@ext:}" ;;
  esac
  line=$(printf '%s' "$row" | awk -F'|' -v p="$path" '{
           for (i = 2; i <= 5; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
           printf "%-19s | %-6s | %-4s | %s | %s", p, $2, $3, $4, $5 }')
  pb_lock "$BRAIN" map || pb_die "MAP.md is locked by another session"
  awk -v line="$line" '
    /^```brain-map[[:space:]]*$/ { inb = 1 }
    inb && /^```[[:space:]]*$/ && !done { print line; done = 1; inb = 0 }
    { print }' "$MAP" | pb_replace "$MAP"
  pb_unlock "$BRAIN" map
  echo "added: $line"
}

# ---------------------------------------------------------------------------------------------
BEGIN_MARK='<!-- project-brain:begin (managed by the project-brain plugin; change .brain/MAP.md instead) -->'
END_MARK='<!-- project-brain:end -->'

cmd_claude_block() {
  need_brain
  dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
  mode=$(pb_map_meta "$MAP" mode)
  case "$mode" in private) target="$PROJ/CLAUDE.local.md" ;; *) target="$PROJ/CLAUDE.md" ;; esac
  block=$(
    echo "$BEGIN_MARK"
    echo "This project keeps a shared knowledge base in .brain/ (the project brain). MAP.md below"
    echo "says what lives where. Follow the project-brain protocol skill to keep it current."
    pb_map_rows "$MAP" | awk -F'|' '$2 == "auto" && $3 != "ext" { print "@.brain/" $1 }'
    pb_map_rows "$MAP" | awk -F'|' '$2 == "auto" && $3 == "ext" { sub(/^@ext:/, "", $1); print "@" $1 }'
    echo "$END_MARK"
  )
  if [ $dry = 1 ]; then echo "target: $target"; printf '%s\n' "$block"; return 0; fi
  if [ -f "$target" ]; then
    mkdir -p "$BRAIN/archive/backups"
    cp "$target" "$BRAIN/archive/backups/$(basename -- "$target").$(pb_stamp).bak"
    if grep -qF 'project-brain:begin' "$target"; then
      PB_BLOCK=$block awk '
        /project-brain:begin/ { print ENVIRON["PB_BLOCK"]; skip = 1; next }
        skip && /project-brain:end/ { skip = 0; next }
        !skip { print }' "$target" | pb_replace "$target"
    else
      { cat "$target"; [ -n "$(tail -c 1 "$target")" ] && echo; echo; printf '%s\n' "$block"; } | pb_replace "$target"
    fi
  else
    printf '%s\n' "$block" > "$target"
  fi
  echo "updated: $target"
}

# ---------------------------------------------------------------------------------------------
cmd_git_hide() {
  need_brain
  top=$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null) || { echo "not in a git repo: nothing to hide"; return 0; }
  excl=$(git -C "$PROJ" rev-parse --git-path info/exclude)
  case "$excl" in /*|?:*) ;; *) excl="$PROJ/$excl" ;; esac
  rel=$(git -C "$PROJ" rev-parse --show-prefix)   # "" or "sub/dir/"; immune to symlinked paths
  mkdir -p "$(dirname -- "$excl")"
  touch "$excl"
  for p in ".brain/" "CLAUDE.local.md" ".claude/settings.local.json"; do
    line="/$rel$p"
    grep -qxF "$line" "$excl" || { grep -qF '# project-brain' "$excl" || printf '\n# project-brain (private mode): never committed\n' >> "$excl"; echo "$line" >> "$excl"; }
  done
  echo "hidden via $excl"
  tracked=$(git -C "$top" ls-files -- "$rel.brain" "${rel}CLAUDE.local.md" "$rel.claude/settings.local.json" 2>/dev/null)
  if [ -n "$tracked" ]; then
    echo "WARNING: already tracked by git (ignore rules cannot hide these):"
    printf '%s\n' "$tracked" | sed 's/^/  /'
    echo "To untrack without deleting: git rm -r --cached <path>, then commit."
  fi
}

# ---------------------------------------------------------------------------------------------
cmd_map_check() {
  need_brain
  err=0
  e() { echo "ERROR: $*"; err=1; }
  [ "$(pb_map_meta "$MAP" format)" = "$PB_FORMAT" ] || e "format is '$(pb_map_meta "$MAP" format)', plugin expects $PB_FORMAT"
  for c in MAP.md NOW.md log/ sources/ sessions/ archive/; do
    pb_map_rows "$MAP" | awk -F'|' -v p="$c" '$1 == p && $3 == "core" { f = 1 } END { exit !f }' || e "core row missing: $c"
  done
  rows=$(pb_map_rows "$MAP")
  printf '%s\n' "$rows" | awk -F'|' '{ print $1 }' | sort | uniq -d | while read -r d; do echo "ERROR: duplicate row: $d"; done | grep . && err=1
  while IFS='|' read -r path tier kind holds when; do
    case "$tier" in auto|inject|demand) ;; *) e "$path: bad tier '$tier'" ;; esac
    case "$kind" in core|file|dir|ext) ;; *) e "$path: bad kind '$kind'" ;; esac
    [ -n "$holds" ] || e "$path: 'holds' is empty"
    case "$kind" in
      ext) [ -e "$PROJ/${path#@ext:}" ] || echo "WARN: linked file missing: ${path#@ext:}" ;;
      *) [ -e "$BRAIN/$path" ] || e "mapped but missing: $path" ;;
    esac
  done <<EOF
$rows
EOF
  # Every file in the brain must be covered by a row (itself or a mapped folder).
  # One awk pass: rows first (from the variable), then the file list.
  (cd "$BRAIN" && find . -type f ! -path './.locks/*' ! -name '.DS_Store' | sed 's|^\./||') \
    | PB_ROWS=$rows awk '
        BEGIN { n = split(ENVIRON["PB_ROWS"], r, "\n")
                for (i = 1; i <= n; i++) { split(r[i], c, "|"); p = c[1]
                  if (p ~ /\/$/) dirs[++nd] = p; else files[p] = 1 } }
        { if ($0 in files) next
          for (i = 1; i <= nd; i++) if (index($0, dirs[i]) == 1) next
          print "ERROR: not in MAP.md: " $0 }' | grep . && err=1
  # The CLAUDE block must import exactly the auto rows.
  mode=$(pb_map_meta "$MAP" mode)
  case "$mode" in private) t="$PROJ/CLAUDE.local.md" ;; *) t="$PROJ/CLAUDE.md" ;; esac
  want=$(printf '%s\n' "$rows" | awk -F'|' '$2 == "auto" { p = $1; if ($3 == "ext") sub(/^@ext:/, "", p); else p = ".brain/" p; print "@" p }' | sort)
  have=$( [ -f "$t" ] && awk '/project-brain:begin/ {i=1; next} /project-brain:end/ {i=0} i && /^@/' "$t" | sort)
  [ "$want" = "$have" ] || e "$(basename -- "$t") imports do not match the auto rows (run: brain.sh claude-block)"
  cmd_budget | tail -n 1 | grep -q OVER && e "auto tier over budget (run: brain.sh budget)"
  [ $err = 0 ] && echo "map ok: $(printf '%s\n' "$rows" | grep -c .) rows"
  return $err
}

cmd_budget() {
  need_brain
  total=0
  for r in $(pb_map_rows "$MAP" | awk -F'|' '$2 == "auto" { p = $1; if ($3 == "ext") { sub(/^@ext:/, "", p); p = "EXT:" p } print p }'); do
    case "$r" in EXT:*) f="$PROJ/${r#EXT:}" ;; *) f="$BRAIN/$r" ;; esac
    t=0; [ -f "$f" ] && t=$(( $(wc -c < "$f") / 4 ))
    total=$((total + t))
    printf '%6d  %s\n' "$t" "${r#EXT:}"
  done
  if [ $total -gt $PB_AUTO_BUDGET ]; then s=OVER; else s=ok; fi
  printf '%6d  total auto tier (budget %d): %s\n' "$total" "$PB_AUTO_BUDGET" "$s"
}

# ---------------------------------------------------------------------------------------------
cmd_log() {
  need_brain
  type=""; tag=""; sid="${BRAIN_SESSION:-manual}"; day=""; time=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --type) type=$2; shift 2 ;;
      --tag) tag=$2; shift 2 ;;
      --session) sid=$2; shift 2 ;;
      --date) day=$2; shift 2 ;;
      --time) time=$2; shift 2 ;;
      *) pb_die "unknown option $1" ;;
    esac
  done
  [ -n "$type" ] || pb_die "--type is required"
  sid=$(printf '%s' "$sid" | cut -c1-8)
  if [ -n "$day" ]; then
    printf '%s' "$day" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || pb_die "--date must be YYYY-MM-DD"
    stamp="$day${time:+ $time}"; extra=" · backfilled"
  else
    day=$(pb_today); stamp=$(pb_now); extra=""
  fi
  text=$(cat)
  [ -n "$text" ] || pb_die "log text is empty (pass it on stdin)"
  f="$BRAIN/log/$day.md"
  if [ ! -f "$f" ]; then
    pb_lock "$BRAIN" newday && { [ -f "$f" ] || sed "s|{{DAY}}|$day|" "$PB_ROOT/templates/core/log-day.md" > "$f"; pb_unlock "$BRAIN" newday; }
  fi
  printf '\n### %s · s:%s · %s%s%s\n%s\n' "$stamp" "$sid" "$type" "${tag:+ · $tag}" "$extra" "$text" | pb_append "$BRAIN" "$f"
  echo "logged: log/$day.md"
}

# ---------------------------------------------------------------------------------------------
cmd_snapshot() {
  dir=$(CDPATH= cd -- "${1:-.}" && pwd) || exit 1
  (cd "$dir" && find . \( -path ./.brain -o -name .git \) -prune -o -type f ! -name CLAUDE.local.md -print \
     | LC_ALL=C sort | while read -r f; do cksum "$f"; done)
}

cmd_privacy_check() {
  need_brain
  top=$(git -C "$PROJ" rev-parse --show-toplevel 2>/dev/null) || { echo "privacy: not in a git repo"; return 0; }
  mode=$(pb_map_meta "$MAP" mode)
  issues=0
  if [ "$mode" = private ]; then
    rel=$(git -C "$PROJ" rev-parse --show-prefix)   # "" or "sub/dir/"; immune to symlinked paths
    tr=$(git -C "$top" ls-files -- "$rel.brain" "${rel}CLAUDE.local.md" "$rel.claude/settings.local.json" | head -n 5)
    [ -n "$tr" ] && { echo "privacy: tracked by git: $(printf '%s' "$tr" | tr '\n' ' ')"; issues=1; }
    st=$(git -C "$top" status --porcelain --ignored=no -- "$rel.brain" "${rel}CLAUDE.local.md" 2>/dev/null | head -n 3)
    [ -n "$st" ] && { echo "privacy: brain files visible to git (run: brain.sh git-hide)"; issues=1; }
  fi
  n=$(git -C "$top" log --branches --not --remotes -n 200 --format=%B 2>/dev/null \
      | grep -ciE 'co-authored-by:.*(claude|anthropic)|generated with .?claude code' || true)
  [ "${n:-0}" -gt 0 ] && { echo "privacy: $n line(s) crediting Claude in commits not yet pushed"; issues=1; }
  [ $issues = 0 ] && echo "privacy: ok"
  return 0
}

# --- Sessions and claims ------------------------------------------------------------------------
# A claim is one line in NOW.md "## Claims" and in the session's own file:
#   - [claim] <what> · s:<id> · since <date time> · until <date time> (@<epoch>)
# Claims expire at "until". Anyone may clear expired claims. Additive changes need no claim;
# split, merge, rename (move) and retire do.

my_session() { S8=$(printf '%s' "${opt_session:-${BRAIN_SESSION:-}}" | cut -c1-8); [ -n "$S8" ] || pb_die "no session id: pass --session <id> (your id is in the start summary)"; }

fmt_epoch() {   # epoch -> "YYYY-MM-DD HH:MM" local time, on BSD, GNU and Git Bash date
  date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null || echo "@$1"
}

claim_lines() { awk '/^## Claims/ { c = 1; next } /^## / { c = 0 } c && /^- \[claim\] /' "$BRAIN/NOW.md"; }

claim_epoch() { printf '%s\n' "$1" | sed -n 's/.*(@\([0-9]*\))[[:space:]]*$/\1/p'; }
claim_owner() { printf '%s\n' "$1" | sed -n 's/.* · s:\([^ ]*\) · since .*/\1/p'; }
claim_what()  { printf '%s\n' "$1" | sed -n 's/^- \[claim\] \(.*\) · s:[^ ]* · since .*/\1/p'; }

# Path-like words in a claim ("split decisions.md" -> decisions.md). Two claims conflict when
# they are equal, share such a word, or either is the whole-brain claim "structure".
claim_tokens() {
  mapped=$(pb_map_rows "$MAP" 2>/dev/null | awk -F'|' '{ p = $1; sub(/\/$/, "", p); print p }')
  printf '%s\n' "$1" | tr ' ,;()' '\n\n\n\n\n' | sed -e 's|^\.brain/||' -e 's|/$||' | while IFS= read -r w; do
    [ -n "$w" ] || continue
    case "$w" in */*|*.[a-z]*) echo "$w" ;; *) printf '%s\n' "$mapped" | grep -qxF "$w" && echo "$w" ;; esac
  done | sort -u
}
claims_conflict() {
  [ "$1" = "$2" ] && return 0
  case "$1" in structure) return 0 ;; esac
  case "$2" in structure) return 0 ;; esac
  a=$(claim_tokens "$1"); b=$(claim_tokens "$2")
  [ -n "$a" ] && [ -n "$b" ] && [ -n "$(printf '%s\n%s\n' "$a" "$b" | sort | uniq -d)" ]
}

# Rewrite the "## Claims" section of a file (NOW.md or a session file) with an awk filter.
edit_claims() {   # edit_claims <file> <awk program on claim lines; print what to keep> [line to add]
  f=$1; prog=$2; add=${3:-}
  [ -f "$f" ] || return 0
  awk -v add="$add" '
    function flush() { if (inc && add != "" && !added) { print add; added = 1 } }
    /^## Claims/ { print; inc = 1; next }
    inc && /^## / { flush(); inc = 0 }
    inc && /^- \[claim\] / { if ('"$prog"') print; next }
    { print }
    END { flush() }' "$f" | pb_replace "$f"
}

expire_claims() {   # drop expired claims from NOW.md; print what was dropped
  now=$(pb_epoch)
  claim_lines | while IFS= read -r l; do
    e=$(claim_epoch "$l"); [ -n "$e" ] && [ "$e" -lt "$now" ] && echo "expired: $l"
  done
  edit_claims "$BRAIN/NOW.md" 'match($0, /\(@[0-9]+\)[[:space:]]*$/) == 0 || substr($0, RSTART + 2, RLENGTH - 3) + 0 >= '"$now"
}

cmd_claim() {
  need_brain; hours=4; what=""
  while [ $# -gt 0 ]; do
    case "$1" in --hours) hours=$2; shift 2 ;; --session) opt_session=$2; shift 2 ;; *) what="$what${what:+ }$1"; shift ;; esac
  done
  my_session
  [ -n "$what" ] || pb_die 'usage: claim "<what>" [--hours N] [--session ID]'
  what=$(printf '%s' "$what" | tr -d '·\n' | sed 's/(@/(/g')
  pb_lock "$BRAIN" now || pb_die "NOW.md is locked, try again"
  expire_claims >/dev/null
  conflict=$(claim_lines | while IFS= read -r l; do
    o=$(claim_owner "$l"); [ "$o" = "$S8" ] && continue
    claims_conflict "$what" "$(claim_what "$l")" && { echo "$l"; break; }
  done)
  if [ -n "$conflict" ]; then pb_unlock "$BRAIN" now; echo "REFUSED: another session holds a claim that overlaps:"; echo "$conflict"; return 3; fi
  now=$(pb_epoch); until=$((now + hours * 3600))
  line="- [claim] $what · s:$S8 · since $(fmt_epoch "$now") · until $(fmt_epoch "$until") (@$until)"
  edit_claims "$BRAIN/NOW.md" "1" "$line"
  pb_unlock "$BRAIN" now
  sf="$BRAIN/sessions/$S8.md"
  [ -f "$sf" ] || sed -e "s|{{SID}}|$S8|g" -e "s|{{TS}}|$(pb_now)|g" "$PB_ROOT/templates/core/session.md" > "$sf"
  edit_claims "$BRAIN/sessions/$S8.md" "1" "$line"
  echo "claimed: $what (until $(fmt_epoch "$until"))"
}

cmd_release() {
  need_brain; what=""; all=0
  while [ $# -gt 0 ]; do
    case "$1" in --all) all=1; shift ;; --session) opt_session=$2; shift 2 ;; *) what="$what${what:+ }$1"; shift ;; esac
  done
  my_session
  [ $all = 1 ] || [ -n "$what" ] || pb_die 'usage: release "<what>" | --all [--session ID]'
  if [ $all = 1 ]; then keep='index($0, " · s:'"$S8"' · since ") == 0'
  else keep='!(index($0, " · s:'"$S8"' · since ") > 0 && index($0, "- [claim] '"$(printf '%s' "$what" | sed 's/[\\"]/\\&/g')"' · ") == 1)'; fi
  pb_lock "$BRAIN" now || pb_die "NOW.md is locked, try again"
  before=$(claim_lines | grep -c . || true)
  edit_claims "$BRAIN/NOW.md" "$keep"
  after=$(claim_lines | grep -c . || true)
  pb_unlock "$BRAIN" now
  edit_claims "$BRAIN/sessions/$S8.md" "$keep"
  echo "released: $((before - after)) claim(s)"
}

cmd_claims() {
  need_brain
  if [ "${1:-}" = --expire ]; then
    pb_lock "$BRAIN" now || pb_die "NOW.md is locked, try again"; expire_claims; pb_unlock "$BRAIN" now; return 0
  fi
  now=$(pb_epoch)
  claim_lines | while IFS= read -r l; do
    e=$(claim_epoch "$l"); if [ -n "$e" ] && [ "$e" -lt "$now" ]; then echo "EXPIRED $l"; else echo "active  $l"; fi
  done
}

require_claim() {   # require_claim <path>: this session must hold a claim covering the path
  my_session
  p=${1#.brain/}; p=${p%/}
  held=$(claim_lines | while IFS= read -r l; do
    [ "$(claim_owner "$l")" = "$S8" ] || continue
    w=$(claim_what "$l")
    { [ "$w" = structure ] || claim_tokens "$w" | grep -qxF "$p"; } && { echo yes; break; }
  done)
  [ "$held" = yes ] || pb_die "claim it first: brain.sh claim \"<change> $p\" --session $S8 (split, merge, move and retire need a claim)"
}

# --- References ---------------------------------------------------------------------------------
# Living files: everything in the brain except sources/ (verbatim), log/ (append-only history),
# archive/ (retired) and sessions/ (each owned by its session).
living_files() {
  (cd "$BRAIN" && find . -type f -name '*.md' ! -path './sources/*' ! -path './log/*' ! -path './archive/*' \
     ! -path './sessions/*' ! -path './.locks/*' | sed 's|^\./||' | LC_ALL=C sort)
}

# Replace a path wherever it appears as a whole path (optionally written as .brain/<path>).
rewrite_refs() {   # rewrite_refs <old> <new>; prints the files it changed
  old=$1; new=$2
  living_files | while IFS= read -r f; do
    grep -qF "$old" "$BRAIN/$f" || continue
    LC_ALL=C awk -v old="$old" -v new="$new" '
      function ok_before(s, i, c) { if (i == 1) return 1; c = substr(s, i - 1, 1)
        if (c !~ /[A-Za-z0-9_.\/-]/) return 1
        return (i > 7 && substr(s, i - 7, 7) == ".brain/") }
      function ok_after(s, j, c) { if (j > length(s)) return 1; c = substr(s, j, 1)
        if (old ~ /\/$/) return 1
        return (c !~ /[A-Za-z0-9_\/-]/) && !(c == "." && substr(s, j + 1, 1) ~ /[A-Za-z0-9]/) }
      /^- \[claim\] / { print; next }
      { out = ""; s = $0
        while ((i = index(s, old)) > 0) {
          if (ok_before(s, i) && ok_after(s, i + length(old))) { out = out substr(s, 1, i - 1) new; hit = 1 }
          else out = out substr(s, 1, i - 1 + length(old))
          s = substr(s, i + length(old)) }
        print out s }
      END { exit !hit }' "$BRAIN/$f" > "$BRAIN/$f.pb-tmp.$$" && { mv -f "$BRAIN/$f.pb-tmp.$$" "$BRAIN/$f"; echo "$f"; } \
      || rm -f "$BRAIN/$f.pb-tmp.$$"
  done
}

# Paths mentioned in living files that point into the brain but do not exist.
cmd_refs_check() {
  need_brain
  tops=$(pb_map_rows "$MAP" | awk -F'|' '$3 != "ext" { p = $1; sub(/\/.*/, "", p); print p }' | sort -u)
  living_files | while IFS= read -r f; do
    LC_ALL=C awk '{ s = $0
        while (match(s, /[A-Za-z0-9_.\/-]+\.(md|pdf|png|jpe?g|txt|csv|eml|json|docx?)|[A-Za-z0-9_.-]+\/[A-Za-z0-9_.\/-]*/)) {
          print substr(s, RSTART, RLENGTH); s = substr(s, RSTART + RLENGTH) } }' "$BRAIN/$f" |
    sed -e 's/[.,:;]*$//' | sort -u | while IFS= read -r ref; do
      r=${ref#.brain/}; top=${r%%/*}
      [ "$ref" != "$r" ] || printf '%s\n' "$tops" | grep -qxF "$top" || continue
      [ -e "$BRAIN/$r" ] || [ -e "$PROJ/$r" ] || [ -e "$PROJ/$ref" ] || echo "BROKEN: $f mentions $ref"
    done
  done
}

# --- Structure changes ---------------------------------------------------------------------------

map_row_of() { pb_map_rows "$MAP" | awk -F'|' -v p="$1" '$1 == p || $1 == p "/"'; }

map_edit_row() {   # map_edit_row <path> <new path or "-" to delete> [new tier]
  pb_lock "$BRAIN" map || pb_die "MAP.md is locked by another session"
  awk -v p="$1" -v np="$2" -v nt="${3:-}" '
    /^```brain-map[[:space:]]*$/ { inb = 1; print; next }
    inb && /^```/ { inb = 0 }
    inb && /\|/ && $0 !~ /^[[:space:]]*#/ {
      split($0, c, "|"); k = c[1]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
      if (k == p || k == p "/") {
        if (np == "-") next
        rest = substr($0, index($0, "|"))
        if (nt != "") { n = split(rest, r, "|"); r[2] = " " sprintf("%-6s", nt) " "; rest = ""; for (i = 1; i <= n; i++) rest = rest (i > 1 ? "|" : "") r[i] }
        printf "%-19s %s\n", (np == "" ? k : np), rest; next
      }
    }
    { print }' "$MAP" | pb_replace "$MAP"
  pb_unlock "$BRAIN" map
}

struct_log() { printf '%s\n' "$1" | cmd_log --type structure --session "$S8" >/dev/null; }

cmd_move() {
  need_brain; old=""; new=""; why=""
  while [ $# -gt 0 ]; do
    case "$1" in --why) why=$2; shift 2 ;; --session) opt_session=$2; shift 2 ;; *) [ -z "$old" ] && old=$1 || new=$1; shift ;; esac
  done
  [ -n "$old" ] && [ -n "$new" ] || pb_die 'usage: move <old> <new> --why "<reason>" [--session ID]'
  old=${old#.brain/}; new=${new#.brain/}
  row=$(map_row_of "${old%/}")
  [ -n "$row" ] || pb_die "not in MAP.md: $old"
  case "$(printf '%s' "$row" | cut -d'|' -f3)" in core) pb_die "the fixed core is off limits: $old" ;; ext) pb_die "$old is a workspace file; the brain never moves those" ;; esac
  [ -e "$BRAIN/$old" ] || pb_die "missing: $old"
  [ -e "$BRAIN/$new" ] && pb_die "already exists: $new"
  require_claim "$old"
  case "$new" in */*) mkdir -p "$BRAIN/$(dirname -- "$new")" ;; esac
  mv "$BRAIN/${old%/}" "$BRAIN/${new%/}" || exit 1
  kindd=$(printf '%s' "$row" | cut -d'|' -f3)
  [ "$kindd" = dir ] && { old="${old%/}/"; new="${new%/}/"; }
  map_edit_row "${old%/}" "$new"
  changed=$(rewrite_refs "$old" "$new" | awk '{ printf "%s%s", s, $0; s = ", " }')
  [ "$(printf '%s' "$row" | cut -d'|' -f2)" = auto ] && cmd_claude_block >/dev/null
  struct_log "move: $old → $new. Why: ${why:-not given}. References updated in: ${changed:-none}."
  echo "moved: $old → $new"; [ -n "$changed" ] && echo "references updated in: $changed"
  return 0
}

cmd_retire() {
  need_brain; p=""; why=""; refsto=""
  while [ $# -gt 0 ]; do
    case "$1" in --why) why=$2; shift 2 ;; --refs-to) refsto=${2#.brain/}; shift 2 ;; --session) opt_session=$2; shift 2 ;; *) p=$1; shift ;; esac
  done
  [ -n "$p" ] || pb_die 'usage: retire <path> --why "<reason>" [--refs-to <merged-into path>] [--session ID]'
  p=${p#.brain/}
  row=$(map_row_of "${p%/}")
  [ -n "$row" ] || pb_die "not in MAP.md: $p"
  kind=$(printf '%s' "$row" | cut -d'|' -f3); tier=$(printf '%s' "$row" | cut -d'|' -f2)
  [ "$kind" = core ] && pb_die "the fixed core is off limits: $p"
  require_claim "$p"
  if [ "$kind" = ext ]; then       # a link: drop the row, never touch the workspace file
    map_edit_row "${p%/}" "-"
    [ "$tier" = auto ] && cmd_claude_block >/dev/null
    struct_log "retire link: ${p#@ext:} (row removed from MAP.md; the workspace file is untouched). Why: ${why:-not given}."
    echo "unlinked: $p"; return 0
  fi
  [ -e "$BRAIN/${p%/}" ] || pb_die "missing: $p"
  dest="archive/${p%/}"
  [ -e "$BRAIN/$dest" ] && dest="archive/$(pb_today)-$(printf '%s' "${p%/}" | tr '/' '-')"
  mkdir -p "$BRAIN/$(dirname -- "$dest")"
  mv "$BRAIN/${p%/}" "$BRAIN/$dest" || exit 1
  [ "$kind" = dir ] && { p="${p%/}/"; dest="$dest/"; }
  map_edit_row "${p%/}" "-"
  changed=$(rewrite_refs "$p" "${refsto:-$dest}" | awk '{ printf "%s%s", s, $0; s = ", " }')
  [ "$tier" = auto ] && cmd_claude_block >/dev/null
  struct_log "retire: $p → $dest${refsto:+ (merged into $refsto)}. Why: ${why:-not given}. References updated in: ${changed:-none}."
  echo "retired: $p → $dest"; [ -n "$changed" ] && echo "references updated in: $changed"
  return 0
}

cmd_retier() {
  need_brain; p=""; t=""
  while [ $# -gt 0 ]; do
    case "$1" in --session) opt_session=$2; shift 2 ;; *) [ -z "$p" ] && p=$1 || t=$1; shift ;; esac
  done
  case "$t" in auto|inject|demand) ;; *) pb_die 'usage: retier <path> auto|inject|demand [--session ID]' ;; esac
  p=${p#.brain/}
  row=$(map_row_of "${p%/}"); [ -n "$row" ] || pb_die "not in MAP.md: $p"
  [ "$(printf '%s' "$row" | cut -d'|' -f3)" = core ] && pb_die "the fixed core is off limits: $p"
  old=$(printf '%s' "$row" | cut -d'|' -f2)
  map_edit_row "${p%/}" "" "$t"
  cmd_claude_block >/dev/null
  S8=$(printf '%s' "${opt_session:-${BRAIN_SESSION:-manual}}" | cut -c1-8)
  struct_log "retier: $p $old → $t."
  echo "retiered: $p $old → $t"
  cmd_budget | tail -n 1
}

# --- Manual capture ------------------------------------------------------------------------------

cmd_capture() {
  need_brain; src=""; kind=manual
  while [ $# -gt 0 ]; do
    case "$1" in --kind) kind=$2; shift 2 ;; --session) opt_session=$2; shift 2 ;; *) src=$1; shift ;; esac
  done
  S8=$(printf '%s' "${opt_session:-${BRAIN_SESSION:-manual}}" | cut -c1-8)
  d="$BRAIN/sources/inbox"; mkdir -p "$d"
  w=$(mktemp -d 2>/dev/null) || { w="${TMPDIR:-/tmp}/pbc.$$"; mkdir -p "$w"; }
  if [ -n "$src" ]; then
    src=$(pb_path "$src"); [ -f "$src" ] || pb_die "no such file: $src"
    base=$(basename -- "$src" | sed 's/[^A-Za-z0-9._-]/-/g')
    f="$d/$(pb_stamp)-$S8-$base"; k=1
    while [ -e "$f" ]; do k=$((k + 1)); f="$d/$(pb_stamp)-$S8-$k-$base"; done
    case "$base" in
      *.md|*.txt|*.eml|*.csv|*.vtt|*.srt|*.json|*.html|*.htm|*.yaml|*.yml)
        sh "$PB_ROOT/scripts/redact.sh" "$w/r" < "$src" > "$f" ;;
      *) cp "$src" "$f" ;;
    esac
  else
    cat > "$w/in"; [ -s "$w/in" ] || pb_die "nothing to capture (give a file, or text on stdin)"
    f="$d/$(pb_stamp)-$S8.md"; k=1
    while [ -e "$f" ]; do k=$((k + 1)); f="$d/$(pb_stamp)-$S8-$k.md"; done
    sh "$PB_ROOT/scripts/redact.sh" "$w/r" < "$w/in" > "$w/body"
    { echo "---"; echo "captured: $(pb_now)"; echo "session: $S8"; echo "detected: $kind"
      echo "redacted: $(awk '{ printf "%s%s x%s", s, $1, $2; s = ", " }' "$w/r")"; echo "---"; cat "$w/body"; } > "$f"
  fi
  red=$(awk '{ printf "%s%s x%s", s, $1, $2; s = ", " }' "$w/r" 2>/dev/null); rm -rf "$w"
  # never store the same bytes twice
  s=$(wc -c < "$f" | tr -d ' ')
  o=$(find "$BRAIN/sources" -type f -size "${s}c" ! -path "$f" 2>/dev/null | while IFS= read -r x; do cmp -s "$f" "$x" && { echo "${x#"$BRAIN"/}"; break; }; done)
  if [ -n "$o" ]; then rm -f "$f"; echo "already in the brain: .brain/$o"; return 0; fi
  rel=${f#"$BRAIN"/}
  printf 'Saved %s (%s%s). Filing: s:%s.\n' "$rel" "$kind" "${red:+; redacted: $red}" "$S8" | cmd_log --type capture --tag inbox --session "$S8" >/dev/null
  echo "saved: .brain/$rel${red:+ (credentials removed: $red)}"
}

# --- Catch-up and tidy reports -------------------------------------------------------------------

cmd_catchup() {
  need_brain; since=""
  while [ $# -gt 0 ]; do
    case "$1" in --since) since=$2; shift 2 ;; --session) opt_session=$2; shift 2 ;; *) shift ;; esac
  done
  S8=$(printf '%s' "${opt_session:-${BRAIN_SESSION:-}}" | cut -c1-8)
  sf="$BRAIN/sessions/$S8.md"
  [ -n "$since" ] || since=$(sed -n 's/^started: \([0-9-]*\).*/\1/p' "$sf" 2>/dev/null | head -n 1)
  [ -n "$since" ] || since=$(pb_today)
  echo "# Catch-up for s:${S8:-?} since $since"
  echo; echo "## Log entries by other sessions (oldest first)"
  for l in "$BRAIN"/log/*.md; do
    [ -f "$l" ] || continue
    d=$(basename -- "$l" .md); [ "$d" \< "$since" ] && continue
    awk -v me="s:$S8" -v f="log/$d.md" '
      /^### / { show = (index($0, " · " me " · ") == 0); if (show) print "\n" substr($0, 5) " [" f "]"; next }
      show && NF && !/^Append-only/ && !/^# Log/ { print "  " $0 }' "$l"
  done | awk 'NR <= 200 { print } NR == 201 { print "(cut at 200 lines: read .brain/log/ for the rest)" }'
  echo; echo "## Not yet filed (sources/inbox/)"
  ls "$BRAIN/sources/inbox" 2>/dev/null | sed 's/^/- sources\/inbox\//' | grep . || echo "- nothing"
  echo; echo "## Claims"
  cmd_claims | grep . || echo "- none"
  echo; echo "## Other live sessions"
  open_sessions | grep . || echo "- none"
  echo; echo "## Repos changed since the Freshness stamps"
  repo_drift | grep . || echo "- none"
  # the digest marker moves to now: this session has seen everything
  if [ -n "$S8" ] && [ -f "$sf" ]; then
    (cd "$BRAIN/log" && for l in *.md; do [ -f "$l" ] && printf '%s %s\n' "$l" "$(wc -l < "$l" | tr -d ' ')"; done) > "$BRAIN/sessions/$S8.seen"
  fi
  return 0
}

tokens() { echo $(( $(wc -c < "$1") / 4 )); }

cmd_tidy_report() {
  need_brain
  echo "# Tidy report for $(pb_map_meta "$MAP" project)"
  echo; echo "## Budget (auto tier, ~3k tokens)"; cmd_budget
  echo; echo "## Big files (over 2,000 tokens: consider a split)"
  pb_map_rows "$MAP" | awk -F'|' '$3 == "file" || $3 == "core" { print $1 "|" $2 }' | while IFS='|' read -r p t; do
    [ -f "$BRAIN/$p" ] || continue; n=$(tokens "$BRAIN/$p"); [ "$n" -gt 2000 ] && echo "- $p ($t): ~$n tokens"
  done | grep . || echo "- none"
  echo; echo "## Folders (files, ~tokens)"
  pb_map_rows "$MAP" | awk -F'|' '$3 == "dir" && $1 != "log/" && $1 != "archive/" { print $1 }' | while IFS= read -r p; do
    [ -d "$BRAIN/$p" ] || continue
    c=$(find "$BRAIN/$p" -type f | grep -c . || true); b=$(find "$BRAIN/$p" -type f -exec cat {} + 2>/dev/null | wc -c)
    echo "- $p: $c files, ~$((b / 4)) tokens"
  done
  echo; echo "## Untouched for 30+ days (retire?)"
  pb_map_rows "$MAP" | awk -F'|' '$3 == "file" { print $1 }' | while IFS= read -r p; do
    [ -n "$(find "$BRAIN/$p" -mtime +30 2>/dev/null)" ] && echo "- $p"
  done | grep . || echo "- none"
  echo; echo "## Still the empty starter (nothing written yet)"
  pb_map_rows "$MAP" | awk -F'|' '$3 == "file" { print $1 }' | while IFS= read -r p; do
    [ -f "$BRAIN/$p" ] || continue
    body=$(awk '/<!--/ { c = 1 } c { if (/-->/) c = 0; next } /^#/ || /^[[:space:]]*$/ { next } /^(In|Out):[[:space:]]*$/ { next } { print }' "$BRAIN/$p")
    [ -z "$body" ] && echo "- $p"
  done | grep . || echo "- none"
  echo; echo "## Possible overlaps (holds share words)"
  pb_map_rows "$MAP" | awk -F'|' '$3 != "core" { print $1 "|" tolower($4) }' | awk -F'|' '
    { p[NR] = $1; n = split($2, w, /[^a-z]+/); for (i = 1; i <= n; i++) if (length(w[i]) > 4) has[NR, w[i]] = 1; words[NR] = $2 }
    END { for (a = 1; a <= NR; a++) for (b = a + 1; b <= NR; b++) { c = 0; s = ""
            n = split(words[a], w, /[^a-z]+/); delete seen
            for (i = 1; i <= n; i++) if (length(w[i]) > 4 && has[b, w[i]] && !(w[i] in seen)) { c++; seen[w[i]] = 1; s = s " " w[i] }
            if (c >= 2) printf "- %s and %s:%s\n", p[a], p[b], s } }' | grep . || echo "- none"
  echo; echo "## Inbox (should be empty once filed)"
  find "$BRAIN/sources/inbox" -type f 2>/dev/null | sed "s|^$BRAIN/|- |" | grep . || echo "- empty"
  echo; echo "## Claims"; cmd_claims | grep . || echo "- none"
  echo; echo "## Sessions marked live but idle for 24 h+"
  for f in "$BRAIN"/sessions/*.md; do
    [ -f "$f" ] && grep -q '^status: live' "$f" && [ -z "$(find "$f" "${f%.md}.seen" -mmin -1440 2>/dev/null)" ] && echo "- $(basename -- "$f" .md)"
  done | grep . || echo "- none"
  echo; echo "## Broken references"; cmd_refs_check | grep . || echo "- none"
  echo; echo "## Map"; cmd_map_check 2>&1 | sed 's/^/- /'
  echo; echo "## Privacy"; cmd_privacy_check | sed 's/^/- /'
  return 0
}

# --- Format upgrades -----------------------------------------------------------------------------
# Step N lives in scripts/upgrades/N.sh and takes a brain from format N-1 to N. Its first comment
# line says what it does. It gets BRAIN and PB_ROOT in the environment.

cmd_upgrade() {
  need_brain; dry=0; [ "${1:-}" = --dry-run ] && dry=1
  dir=${PB_UPGRADES:-$PB_ROOT/scripts/upgrades}
  cur=$(pb_map_meta "$MAP" format); cur=${cur:-0}
  if [ "$cur" -eq "$PB_FORMAT" ]; then echo "up to date: brain format $cur"; return 0; fi
  if [ "$cur" -gt "$PB_FORMAT" ]; then echo "REFUSED: the brain (format $cur) is newer than this plugin (format $PB_FORMAT). Update the plugin; nothing was changed."; return 3; fi
  n=$((cur + 1)); while [ "$n" -le "$PB_FORMAT" ]; do
    [ -f "$dir/$n.sh" ] || pb_die "missing upgrade step $dir/$n.sh"
    echo "step $((n - 1)) → $n: $(sed -n '2s/^# *//p' "$dir/$n.sh")"; n=$((n + 1))
  done
  [ $dry = 1 ] && { echo "(dry run: nothing changed)"; return 0; }
  mkdir -p "$BRAIN/archive/backups"; cp "$MAP" "$BRAIN/archive/backups/MAP.md.$(pb_stamp).bak"
  n=$((cur + 1)); while [ "$n" -le "$PB_FORMAT" ]; do
    BRAIN=$BRAIN PB_ROOT=$PB_ROOT sh "$dir/$n.sh" || pb_die "upgrade step $n failed; MAP.md backup is in archive/backups/"
    awk -v n="$n" '/^```brain-map/ { inb = 1 } inb && /^format:/ { print "format: " n; next } { print }' "$MAP" | pb_replace "$MAP"
    S8=$(printf '%s' "${BRAIN_SESSION:-upgrade}" | cut -c1-8)
    struct_log "upgrade: brain format $((n - 1)) → $n: $(sed -n '2s/^# *//p' "$dir/$n.sh")"
    n=$((n + 1))
  done
  cmd_claude_block >/dev/null
  echo "upgraded to format $PB_FORMAT"; cmd_map_check
}

cmd_session_status() {   # session-status <live|handed-off|ended> [--session ID]
  need_brain; st=""
  while [ $# -gt 0 ]; do case "$1" in --session) opt_session=$2; shift 2 ;; *) st=$1; shift ;; esac; done
  case "$st" in live|handed-off|ended) ;; *) pb_die 'usage: session-status live|handed-off|ended [--session ID]' ;; esac
  my_session; f="$BRAIN/sessions/$S8.md"; [ -f "$f" ] || pb_die "no session file: sessions/$S8.md"
  awk -v st="$st $(pb_now)" '/^status:/ && !d { print "status: " st; d = 1; next } { print }' "$f" | pb_replace "$f"
  echo "session $S8: $st"
}

# ---------------------------------------------------------------------------------------------
cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  detect) cmd_detect "$@" ;;
  inventory) cmd_inventory "$@" ;;
  scaffold) cmd_scaffold "$@" ;;
  add) [ $# -eq 1 ] || pb_die 'usage: add "path|tier|kind|holds|read when"'; cmd_add "$1" ;;
  claude-block) cmd_claude_block "$@" ;;
  git-hide) cmd_git_hide ;;
  map-check) cmd_map_check ;;
  budget) cmd_budget ;;
  log) cmd_log "$@" ;;
  snapshot) cmd_snapshot "$@" ;;
  privacy-check) cmd_privacy_check ;;
  transcripts) cmd_transcripts "$@" ;;
  transcript) cmd_transcript "$@" ;;
  claim) cmd_claim "$@" ;;
  release) cmd_release "$@" ;;
  claims) cmd_claims "$@" ;;
  move) cmd_move "$@" ;;
  retire) cmd_retire "$@" ;;
  retier) cmd_retier "$@" ;;
  refs-check) cmd_refs_check ;;
  capture) cmd_capture "$@" ;;
  catchup) cmd_catchup "$@" ;;
  tidy-report) cmd_tidy_report ;;
  upgrade) cmd_upgrade "$@" ;;
  session-status) cmd_session_status "$@" ;;
  slug) pb_slug "$(CDPATH= cd -- "${1:-.}" && pwd)" ;;
  find) pb_find_brain ;;
  version) echo "project-brain $(pb_version), brain format $PB_FORMAT" ;;
  ''|-h|--help|help) usage ;;
  *) pb_die "unknown command: $cmd (run without arguments for help)" ;;
esac

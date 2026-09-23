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
  slug) pb_slug "$(CDPATH= cd -- "${1:-.}" && pwd)" ;;
  find) pb_find_brain ;;
  version) echo "project-brain $(pb_version), brain format $PB_FORMAT" ;;
  ''|-h|--help|help) usage ;;
  *) pb_die "unknown command: $cmd (run without arguments for help)" ;;
esac

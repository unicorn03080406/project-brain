# project-brain shared shell functions. POSIX sh: runs under bash, dash, zsh-as-sh and Git Bash.
# Source it; do not run it. Functions are prefixed pb_. Nothing here writes outside the brain
# except where a caller explicitly asks (CLAUDE.md block, .git/info/exclude).

PB_ROOT=${PB_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
PB_FORMAT=${PB_FORMAT_OVERRIDE:-1}   # brain format this plugin writes (override only in tests)
PB_AUTO_BUDGET=3000   # tokens, estimated as bytes/4

pb_version() {
  sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PB_ROOT/.claude-plugin/plugin.json" | head -n 1
}

pb_die() { printf 'project-brain: %s\n' "$*" >&2; exit 1; }
pb_warn() { printf 'project-brain: %s\n' "$*" >&2; }

# Local time with offset, for log headings. File-name stamps never contain ':' (Windows).
pb_now() { date +%Y-%m-%dT%H:%M:%S%z; }
pb_today() { date +%Y-%m-%d; }
pb_stamp() { date +%Y%m%d-%H%M%S; }
pb_epoch() { date +%s; }

# Normalise a path from Claude Code (may be C:\... on Windows) into a shell path.
pb_path() {
  case "$1" in
    *\\*|?:*) if command -v cygpath >/dev/null 2>&1; then cygpath -u "$1"; return; fi ;;
  esac
  printf '%s\n' "$1"
}

# Claude Code's folder name under ~/.claude/projects/: every non-alphanumeric char becomes '-'.
# On Windows it is computed from the native path (C:\Users\x -> C--Users-x).
pb_slug() {
  p=$1
  if command -v cygpath >/dev/null 2>&1; then p=$(cygpath -w "$p"); fi
  printf '%s\n' "$p" | sed 's/[^A-Za-z0-9]/-/g'
}

# Find the brain: $PB_BRAIN, then $CLAUDE_PROJECT_DIR, then walk up from $1 (default: cwd).
# Stops below $HOME so ~/.claude (user config) is never mistaken for a project.
pb_find_brain() {
  if [ -n "${PB_BRAIN:-}" ] && [ -f "$PB_BRAIN/MAP.md" ]; then printf '%s\n' "$PB_BRAIN"; return 0; fi
  if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    d=$(pb_path "$CLAUDE_PROJECT_DIR")
    if [ -f "$d/.brain/MAP.md" ]; then printf '%s\n' "$d/.brain"; return 0; fi
  fi
  d=$(CDPATH= cd -- "${1:-.}" 2>/dev/null && pwd -P) || return 1
  home=$(CDPATH= cd -- "$HOME" 2>/dev/null && pwd -P)
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$home" ]; do
    if [ -f "$d/.brain/MAP.md" ]; then printf '%s\n' "$d/.brain"; return 0; fi
    # Walk up with string operations. Stop if a step does not shorten the path, so a strange
    # value (seen when a shell ignores SIGPIPE) can never loop forever.
    p=${d%/*}; [ "$p" = "$d" ] && break; d=$p
  done
  return 1
}

pb_project_of() { dirname -- "$1"; }   # <project>/.brain -> <project>

# --- MAP.md parsing -------------------------------------------------------------------------
# The machine-readable part is the fenced block that starts with ```brain-map.

pb_map_block() {
  awk '/^```brain-map[[:space:]]*$/ {inb=1; next} inb && /^```/ {exit} inb {print}' "$1"
}

# Rows as "path|tier|kind|holds|when", trimmed, comments and meta lines dropped.
pb_map_rows() {
  pb_map_block "$1" | awk -F'|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    NF < 3 { next }
    {
      out = ""
      for (i = 1; i <= 5; i++) {
        f = (i <= NF) ? $i : ""
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
        out = out (i > 1 ? "|" : "") f
      }
      print out
    }'
}

pb_map_meta() {   # pb_map_meta MAP key
  pb_map_block "$1" | awk -v k="$2" -F': *' '$0 !~ /\|/ && $1 == k { sub(/^[^:]*: */, ""); print; exit }'
}

pb_map_has() {    # pb_map_has MAP path
  pb_map_rows "$1" | awk -F'|' -v p="$2" '$1 == p { f = 1 } END { exit !f }'
}

# --- Locks and appends ----------------------------------------------------------------------
# mkdir is atomic on every platform we support; flock is missing on macOS.

pb_lock() {       # pb_lock BRAIN name
  ld="$1/.locks/$2"
  [ -d "$1/.locks" ] || mkdir -p "$1/.locks"
  i=0
  while ! mkdir "$ld" 2>/dev/null; do
    i=$((i + 1))
    if [ $((i % 20)) -eq 0 ]; then   # about every second: break locks older than 10 s
      t=$(cat "$ld/t" 2>/dev/null || echo 0)
      if [ $(( $(pb_epoch) - ${t:-0} )) -gt 10 ]; then rm -rf "$ld"; continue; fi
    fi
    [ $i -gt 400 ] && return 1
    sleep 0.05 2>/dev/null || sleep 1
  done
  printf '%s\n' "${EPOCH:-$(pb_epoch)}" > "$ld/t"   # the hooks already know the time
}

pb_unlock() { rm -rf "$1/.locks/$2"; }

# Append stdin to a file as one locked write.
pb_append() {     # pb_append BRAIN file < text
  tmp="$1/.locks/.buf.$$"
  mkdir -p "$1/.locks"
  cat > "$tmp"
  pb_lock "$1" append || { rm -f "$tmp"; return 1; }
  cat "$tmp" >> "$2"
  rc=$?
  pb_unlock "$1" append
  rm -f "$tmp"
  return $rc
}

# Rewrite a file atomically: stdin -> temp in same dir -> mv.
pb_replace() {    # pb_replace file < content
  tmp="$1.pb-tmp.$$"
  cat > "$tmp" && mv -f "$tmp" "$1"
}

# --- Workspace scanning ---------------------------------------------------------------------
# Folders never worth reading when adopting a workspace.
PB_SKIP_DIRS='.git node_modules .venv venv __pycache__ .tox dist build target .next .cache .idea .vscode vendor'

pb_find_files() { # pb_find_files DIR [maxdepth]: workspace files, skipping junk and .brain
  set -- "$1" "${2:-8}"
  prune=""
  for s in $PB_SKIP_DIRS; do prune="$prune -name $s -o"; done
  # shellcheck disable=SC2086
  find "$1" -maxdepth "$2" \( -type d \( $prune -path "$1/.brain" \) \) -prune \
    -o -type f ! -name .DS_Store -print 2>/dev/null
}

# --- Shared by the hooks and brain.sh (need BRAIN, PROJ and S8 set) ----------------------------
# Few programs on purpose: these run at every session start (see the speed note in hook.sh).

# Other sessions marked live that were active in the last 24 h: one find, one awk.
open_sessions() {
  set -- "$BRAIN"/sessions/*.md
  [ -f "$1" ] || return 0
  recent=$(find "$BRAIN/sessions" -type f -mmin -1440 2>/dev/null)
  [ -n "$recent" ] || return 0
  PB_RECENT=$recent awk -v me="$S8" '
    BEGIN { n = split(ENVIRON["PB_RECENT"], r, "\n")
            for (i = 1; i <= n; i++) { b = r[i]; sub(/.*\//, "", b); sub(/\.[a-z]+$/, "", b); rec[b] = 1 } }
    function flush() { if (id != "" && id != me && live && (id in rec))
                         printf "- s:%s · %s%s\n", id, (goal != "" ? goal : "goal not set"), (cl ? " · " cl " claim(s)" : "") }
    FNR == 1 { flush(); id = FILENAME; sub(/.*\//, "", id); sub(/\.md$/, "", id); live = 0; goal = ""; cl = 0; sec = "" }
    /^status: live/ { live = 1 }
    /^## / { sec = substr($0, 4); next }
    sec == "Goal" && NF && goal == "" { goal = $0 }
    sec == "Claims" && /^- / { cl++ }
    END { flush() }' "$@"
}

# Commits in each repo since the Freshness stamp in NOW.md: one awk, then git only per repo.
repo_drift() {
  awk '/^## Freshness/ { f = 1; next } /^## / { f = 0 }
       f && match($0, /^- repo [^ ]+ · last seen [0-9a-f]+/) {
         s = substr($0, 8, RLENGTH - 7); split(s, a, " · last seen "); print a[1], a[2] }' "$BRAIN/NOW.md" |
  while read -r path hash; do
    case "$path" in /*) r=$path ;; *) r="$PROJ/$path" ;; esac
    n=$(git -C "$r" rev-list --count "$hash..HEAD" 2>/dev/null) || { echo "- $path: last-seen commit $hash not found"; continue; }
    [ "$n" -gt 0 ] && echo "- $path: $n new commit(s) since $hash ($(git -C "$r" log -1 --format='%h %ad' --date=short 2>/dev/null))"
  done
}

# --- Redaction -----------------------------------------------------------------------------------
# pb_redact <in> <out> [report]: copy <in> to <out> with credentials replaced by [REDACTED: <kind>].
# If a report file is given it gets one line per kind: "<kind> <count>". One sed pass; counting
# runs only when something was redacted. sed -E with intervals works in BSD, GNU and Git Bash sed.
pb_redact() {
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
    -e 's/(([Pp]ass(word|wd)|PASS(WORD|WD)|[Pp]wd|PWD|[Ss]ecret|SECRET|[Tt]oken|TOKEN|[Aa]pi[_-]?[Kk]ey|API[_-]?KEY|[Aa]ccess[_-]?[Kk]ey|ACCESS[_-]?KEY|[Cc]lient[_-]?[Ss]ecret|CLIENT[_-]?SECRET)["'"'"']?[[:space:]]*[:=][[:space:]]*)[^[:space:]\[][^[:space:]]*/\1[REDACTED: secret]/g' \
    "$1" > "$2"
  [ -n "${3:-}" ] || return 0
  : > "$3"
  grep -q 'REDACTED: ' "$2" 2>/dev/null || return 0
  grep -o '\[REDACTED: [a-z-]*\]' "$2" | sort | uniq -c | awk '{ k = $3; sub(/\]$/, "", k); print k, $1 }' > "$3"
}

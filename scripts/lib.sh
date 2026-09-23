# project-brain shared shell functions. POSIX sh: runs under bash, dash, zsh-as-sh and Git Bash.
# Source it; do not run it. Functions are prefixed pb_. Nothing here writes outside the brain
# except where a caller explicitly asks (CLAUDE.md block, .git/info/exclude).

PB_ROOT=${PB_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
PB_FORMAT=1
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
    d=$(dirname -- "$d")
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
  mkdir -p "$1/.locks"
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
  pb_epoch > "$ld/t"
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

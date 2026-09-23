#!/bin/sh
# project-brain end-to-end tests: real Claude Code sessions on synthetic projects.
# Slow (several minutes) and uses your Claude account, so it is not part of tests/run.sh or CI.
# Usage: sh tests/e2e.sh [scenario-filter]
# Needs the claude CLI: on PATH, or set CLAUDE_BIN (the VS Code extension bundles one, e.g.
# ~/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude).
# Every scenario runs in a fresh temp folder; your own projects and settings are not touched
# (init runs with --yes, which never edits ~/.claude/settings.json).
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
B="$ROOT/scripts/brain.sh"
FILTER=${1:-}
CL=${CLAUDE_BIN:-$(command -v claude 2>/dev/null)}
[ -n "$CL" ] && [ -x "$CL" ] || { echo "claude CLI not found: put it on PATH or set CLAUDE_BIN"; exit 2; }
W=$(mktemp -d 2>/dev/null || mktemp -d -t pbe2e)
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com
RES="$W/.results"; : > "$RES"

ok()  { echo ok >> "$RES"; printf '  ok    %s\n' "$1"; }
bad() { echo "FAIL $T: $1" >> "$RES"; printf '  FAIL  %s\n' "$1"; }
check() { if (eval "$2") >/dev/null 2>&1; then ok "$1"; else bad "$1"; fi; }
b() { sh "$B" "$@"; }
claude_run() {   # claude_run <prompt> [extra args]: one headless session in the current folder
  p=$1; shift
  "$CL" -p "$p" "$@" --plugin-dir "$ROOT" --permission-mode acceptEdits \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep,Skill" --output-format text < /dev/null 2>&1
}
scenario() {
  T=$1
  [ -n "$FILTER" ] && case "$T" in *"$FILTER"*) ;; *) return ;; esac
  echo "$T"; D="$W/$T"; mkdir -p "$D"
  ( cd "$D" && "e_$T" )
}

# --- NEW mode: two intakes, two different structures -------------------------------------------
new_project() {   # new_project <fixture>
  cp -R "$ROOT/tests/fixtures/$1" intake
  claude_run "/project-brain:init --yes --mode private" > init.out
}
rows() { sed -n '/^```brain-map/,/^```$/p' .brain/MAP.md | awk -F'|' 'NF >= 5 && $0 !~ /\| core \|/ { gsub(/ /, "", $1); print $1 }' | sort; }

e_new_research() {
  new_project intake-research
  check "brain created and map-check passes" 'b map-check'
  check "intake copied verbatim, originals untouched" 'diff -r "$ROOT/tests/fixtures/intake-research" .brain/sources/intake && diff -r "$ROOT/tests/fixtures/intake-research" intake'
  check "private: CLAUDE.local.md, no CLAUDE.md" '[ -f CLAUDE.local.md ] && [ ! -e CLAUDE.md ]'
  check "a research-shaped structure (experiments or findings)" 'rows | grep -qE "^(experiments/|findings.md)"'
  check "the S17/S22 decision is recorded with its source" 'grep -q "S17" .brain/decisions.md && grep -q "03-kickoff-transcript" .brain/decisions.md'
  check "auto tier within budget" '! b budget | grep -q OVER'
  rows > "$W/research.rows"
}

e_new_product() {
  new_project intake-product
  check "brain created and map-check passes" 'b map-check'
  check "a product-shaped structure (systems, roadmap or specs)" 'rows | grep -qE "^(systems.md|roadmap.md|specs/)"'
  check "the Expo decision is recorded" 'grep -qi "expo" .brain/decisions.md'
  rows > "$W/product.rows"
  [ -f "$W/research.rows" ] && check "the two NEW structures differ" '! cmp -s "$W/research.rows" "$W/product.rows"'
}

# --- ADOPT: shared (workspace is not a repo) and private (workspace is a client's git repo) -----
e_adopt_shared() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  cp CLAUDE.md "$W/claude.orig"; b snapshot . > "$W/adopt.before"
  claude_run "/project-brain:init --yes --mode shared" > "$W/adopt_shared.out"
  check "map-check passes" 'b map-check'
  check "every workspace file byte-identical except CLAUDE.md" 'b snapshot . | grep -v " ./CLAUDE.md\$" | cmp -s - "$(grep -v " ./CLAUDE.md\$" "$W/adopt.before" > "$W/b2"; echo "$W/b2")"'
  check "CLAUDE.md: original bytes kept on top, one block, backup made" '[ "$(head -c "$(wc -c < "$W/claude.orig")" CLAUDE.md | cksum)" = "$(cksum < "$W/claude.orig")" ] && [ "$(grep -c project-brain:begin CLAUDE.md)" = 1 ] && cmp -s "$W/claude.orig" .brain/archive/backups/CLAUDE.md.*.bak'
  check "workspace files linked, not copied" 'grep -q "^@ext:" .brain/MAP.md && [ ! -e .brain/notes ]'
  check "log backfilled from the dated meeting files" 'for d in 2026-07-14 2026-08-02 2026-09-10; do grep -q backfilled .brain/log/$d.md || exit 1; done'
  check "NOW.md marked inferred" 'grep -q "inferred" .brain/NOW.md'
  check "the go-live conflict is resolved to the newer date and listed" 'grep -q "2026-10-15" .brain/NOW.md && grep -q "2026-10-01" .brain/NOW.md'
  check "git repos untouched" '[ -z "$(git -C carrier-sync status --porcelain)" ] && [ -z "$(git -C wms-adapter status --porcelain)" ]'
}

e_adopt_private_git() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  rm -rf carrier-sync/.git wms-adapter/.git
  git init -q . && git add -A && git -c commit.gpgsign=false commit -qm "client repo"
  b snapshot . > "$W/priv.before"
  claude_run "/project-brain:init --yes --mode private" > "$W/adopt_private.out"
  check "map-check passes" 'b map-check'
  check "every workspace file byte-identical, CLAUDE.md included" 'b snapshot . | cmp -s - "$W/priv.before"'
  check "git status is clean: nothing to commit" '[ -z "$(git status --porcelain)" ]'
  check "hidden through .git/info/exclude, .gitignore untouched" 'grep -qx "/.brain/" .git/info/exclude && grep -qx "/CLAUDE.local.md" .git/info/exclude && [ ! -e .gitignore ]'
  check "privacy-check ok" 'b privacy-check | grep -q "privacy: ok"'
}

# --- Capture, filing and the digest across two sessions ------------------------------------------
e_capture() {
  b scaffold . --name "Harbor study" --mode private >/dev/null
  b add "decisions.md|demand|file|decisions: date, decision, who, why, source|before changing direction" >/dev/null
  b add "people.md|demand|file|who is involved|someone is named" >/dev/null
  b claude-block >/dev/null
  printf 'notes from the check-in, file them please\n\n<pasted_content id="t">\n%s\n</pasted_content>\n' "$(cat "$ROOT/tests/detector/context/teams-chat.txt" | sed '1,3d;$d')" > paste.txt
  claude_run "$(cat paste.txt)" > a.out
  check "the paste was filed out of the inbox" '[ -z "$(ls .brain/sources/inbox)" ] && [ -n "$(find .brain/sources -mindepth 2 -type f ! -path "*/inbox/*" ! -path "*/not-context/*")" ]'
  check "an INDEX.md line was added" '[ "$(grep -c "^- " .brain/sources/INDEX.md)" -ge 1 ]'
  check "the S31 decision reached decisions.md with a source" 'grep -q "S31" .brain/decisions.md && grep -q "sources/" .brain/decisions.md'
  check "capture and filing are logged" 'grep -q "capture · inbox" .brain/log/*.md'
  claude_run "In one line: did another session add anything to the project brain recently?" > b.out
  check "a second session knows about it" 'grep -qi "S31\|check-in\|Tomas\|Imani" b.out'
  check "map-check passes" 'b map-check'
}

# --- A split and a retire, done by Claude following the protocol ---------------------------------
e_split_retire() {
  b scaffold . --name "Split test" --mode shared >/dev/null
  b add "charter.md|auto|file|why and scope|always" >/dev/null
  b add "decisions.md|demand|file|all decisions|before changing direction" >/dev/null
  b add "old-notes.md|demand|file|notes from the 2025 pilot|history" >/dev/null
  echo "source" > .brain/sources/sow.md
  { echo "# Decisions"; echo; for y in 2025 2026; do m=1; while [ $m -le 9 ]; do echo "- $y-0$m-01 · decision $y-$m · Ana · why · sources/sow.md · [meeting]"; m=$((m + 1)); done; done; } > .brain/decisions.md
  printf '# Old notes\nPilot ran in 2025. See decisions.md.\n' > .brain/old-notes.md
  printf '\nSee decisions.md for decisions and old-notes.md for the pilot.\n' >> .brain/charter.md
  b claude-block >/dev/null
  n=$(grep -c '^- 20' .brain/decisions.md)
  claude_run "Two brain changes, following the project-brain protocol: 1) split .brain/decisions.md so the 2025 entries move to a new file .brain/decisions-2025.md; 2) retire .brain/old-notes.md, the pilot is over. Report briefly." > out
  check "no decision lost" '[ $(( $(grep -c "^- 20" .brain/decisions.md) + $(grep -c "^- 20" .brain/decisions-2025.md) )) = "$n" ]'
  check "2025 entries moved, 2026 stayed" '! grep -q "^- 2025" .brain/decisions.md && ! grep -q "^- 2026" .brain/decisions-2025.md'
  check "old-notes.md is in archive/, not deleted" '[ ! -e .brain/old-notes.md ] && [ -f .brain/archive/old-notes.md ]'
  check "MAP.md updated: new row, retired row gone" 'grep -q "^decisions-2025.md" .brain/MAP.md && ! grep -q "^old-notes.md" .brain/MAP.md'
  check "map-check and refs-check pass" 'b map-check && [ -z "$(b refs-check)" ]'
  check "both changes logged as structure entries" '[ "$(grep -c "· structure" .brain/log/*.md)" -ge 2 ]'
  check "no claim left behind" '[ -z "$(b claims)" ]'
}

scenario new_research; scenario new_product
scenario adopt_shared; scenario adopt_private_git
scenario capture; scenario split_retire

p=$(grep -c '^ok$' "$RES" || true); f=$(grep -c '^FAIL' "$RES" || true)
echo; echo "end-to-end passed: ${p:-0}  failed: ${f:-0}"
[ "${f:-0}" -gt 0 ] && { grep '^FAIL' "$RES" | sed 's/^/  /'; echo "(outputs kept in $W)"; } || rm -rf "$W"
[ "${f:-0}" -eq 0 ]

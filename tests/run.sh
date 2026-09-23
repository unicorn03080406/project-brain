#!/bin/sh
# project-brain test suite. Plain sh, no framework. Usage: sh tests/run.sh [name-filter]
# Runs with HOME pointed at a temp folder, so your real ~/.claude is never read or written.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
B="$ROOT/scripts/brain.sh"
FILTER=${1:-}
W=$(mktemp -d 2>/dev/null || mktemp -d -t pbtest)
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1
unset CLAUDE_PROJECT_DIR PB_BRAIN BRAIN_SESSION 2>/dev/null || true
check() { if eval "$2" >/dev/null 2>"$W/.err"; then ok "$1"; else bad "$1"; [ -n "${DEBUG:-}" ] && sed "s/^/        /" "$W/.err"; fi; }   # check "desc" "cmd"
b() { ${PB_SH:-sh} "$B" "$@"; }   # PB_SH=dash to test another shell
gitinit() { git init -q "$1" 2>/dev/null; git -C "$1" config commit.gpgsign false; }
run() {   # run <name>: call t_<name> in a fresh folder
  T=$1
  [ -n "$FILTER" ] && case "$T" in *"$FILTER"*) ;; *) return ;; esac
  echo "$T"
  D="$W/$T"; mkdir -p "$D"
  (cd "$D" && "t_$T")
  rc=$?
  [ $rc -ne 0 ] && bad "test crashed with exit code $rc"
}
# The subshell cannot update counters, so each test writes its results to a file.
ok()   { echo ok >> "$W/.results"; printf '  ok    %s\n' "$1"; }
bad()  { echo "FAIL $T: $1" >> "$W/.results"; printf '  FAIL  %s\n' "$1"; }

# ---------------------------------------------------------------------------------------------
t_json() {
  jd() { printf '%s\n' "$1" | LC_ALL=C awk "$(cat "$ROOT/scripts/json.awk")"' { printf "%s", jget($0, "'"$2"'") }'; }
  jt() { if [ "$(jd "$2" "$3")" = "$4" ]; then ok "$1"; else bad "$1 (got: $(jd "$2" "$3"))"; fi; }
  jt "plain value" '{"a":1,"prompt":"hello"}' prompt hello
  jt "escapes: newline, quote, backslash, tab" '{"p":"a\nb \"q\" c\\d\te"}' p "$(printf 'a\nb "q" c\\d\te')"
  jt "unicode escapes to UTF-8" '{"p":"caf\u00e9 \u20ac"}' p "café €"
  jt "surrogate pair (emoji)" '{"p":"\ud83d\ude00"}' p "😀"
  jt "raw UTF-8 passes through" '{"p":"naïve 日本"}' p "naïve 日本"
  jt "missing key gives empty" '{"a":"b"}' zzz ""
  jt "key that is only a value is skipped" '{"x":"prompt","prompt":"yes"}' prompt yes
  jt "spaces around the colon" '{"prompt" : "sp"}' prompt sp
}

t_scaffold() {
  b scaffold . --name "Test Co" --mode private >/dev/null
  for p in MAP.md NOW.md log sources/inbox sources/not-context sources/INDEX.md sessions archive; do
    check "core: $p" "[ -e .brain/$p ]"
  done
  check "format 1 in MAP.md" 'grep -qx "format: 1" .brain/MAP.md'
  check "refuses to overwrite an existing brain" '! b scaffold . --name X --mode private'
  check "rejects a bad mode" '! b scaffold "$W" --name X --mode public'
  check "map-check passes on a fresh brain" 'b claude-block && b map-check'
  check "brain found from a subfolder" 'mkdir -p deep/er && [ "$(cd deep/er && b find)" = "$(pwd -P)/.brain" ]'
}

t_add() {
  b scaffold . --name T --mode shared >/dev/null
  check "file row seeds from the starter file" 'b add "charter.md|auto|file|why and scope|always" && grep -q "## Success criteria" .brain/charter.md'
  check "unknown file gets a heading" 'b add "risks.md|demand|file|risks|planning" && [ "$(head -n 1 .brain/risks.md)" = "# risks" ]'
  check "dir row creates the folder, adds slash" 'b add "experiments|demand|dir|one per experiment|running one" && [ -d .brain/experiments ] && grep -q "^experiments/ " .brain/MAP.md'
  check "ext row links without creating" 'b add "docs/arch.md|demand|ext|architecture|touching infra" 2>/dev/null; grep -q "^@ext:docs/arch.md" .brain/MAP.md && [ ! -e docs ]'
  check "duplicate row is a no-op" 'b add "charter.md|auto|file|x|y" | grep -q already && [ "$(grep -c "^charter.md" .brain/MAP.md)" = 1 ]'
  check "bad tier rejected" '! b add "a.md|always|file|x|y"'
  check "core kind rejected" '! b add "b.md|demand|core|x|y"'
  check "wrong field count rejected" '! b add "c.md|demand|file"'
  check "escaping the brain rejected" '! b add "../x.md|demand|file|x|y"'
  check "rows stay inside the map block" '[ "$(awk "/^\`\`\`brain-map/{i=1;next} i&&/^\`\`\`/{exit} i" .brain/MAP.md | grep -c "risks.md")" = 1 ]'
}

t_mapcheck() {
  b scaffold . --name T --mode shared >/dev/null; b add "charter.md|auto|file|x|y" >/dev/null; b claude-block >/dev/null
  check "clean brain passes" 'b map-check'
  echo x > .brain/stray.md
  check "unmapped file is an error" 'b map-check | grep -q "not in MAP.md: stray.md"'
  mv .brain/stray.md .brain/archive/stray.md
  check "files inside a mapped folder are fine" 'b map-check'
  mv .brain/charter.md .brain/archive/charter.md
  check "mapped but missing is an error" 'b map-check | grep -q "mapped but missing: charter.md"'
  mv .brain/archive/charter.md .brain/charter.md
  b add "glossary.md|auto|file|terms|always" >/dev/null
  check "CLAUDE block out of date is an error" 'b map-check | grep -q "imports do not match"'
  b claude-block >/dev/null
  check "fixed after claude-block" 'b map-check'
  head -c 14000 /dev/zero | tr '\0' 'a' > .brain/glossary.md
  check "auto tier over budget is reported" 'b budget | tail -n 1 | grep -q OVER && ! b map-check'
}

t_claudeblock() {
  printf '# Client instructions\n\nKeep this exactly.\n' > CLAUDE.md
  cp CLAUDE.md orig.md
  b scaffold . --name T --mode shared >/dev/null
  b add "charter.md|auto|file|x|y" >/dev/null
  b claude-block >/dev/null
  check "original content kept byte-for-byte above the block" '[ "$(head -c "$(wc -c < orig.md)" CLAUDE.md | cksum)" = "$(cksum < orig.md)" ]'
  check "block imports MAP and charter" 'grep -qx "@.brain/MAP.md" CLAUDE.md && grep -qx "@.brain/charter.md" CLAUDE.md'
  check "backup of the original in archive/backups" 'cmp -s orig.md .brain/archive/backups/CLAUDE.md.*.bak'
  cp CLAUDE.md once.md; sleep 1; b claude-block >/dev/null
  check "running it again changes nothing" 'cmp -s once.md CLAUDE.md'
  check "exactly one block" '[ "$(grep -c "project-brain:begin" CLAUDE.md)" = 1 ]'
  sed '/project-brain:begin/,/project-brain:end/d' CLAUDE.md > stripped.md
  check "removing the block restores the original (plus spacing)" '[ "$(sed -e :a -e "/^\n*\$/{\$d;N;ba" -e "}" stripped.md | cksum)" = "$(cksum < orig.md)" ]'
  mkdir p2 && cd p2 && b scaffold . --name T --mode private >/dev/null && b claude-block >/dev/null
  check "private mode writes CLAUDE.local.md, not CLAUDE.md" '[ -f CLAUDE.local.md ] && [ ! -e CLAUDE.md ]'
}

t_githide() {
  gitinit repo; cd repo
  printf 'node_modules\n' > .gitignore; git add .gitignore; git commit -qm init
  cp .gitignore gi.orig
  b scaffold . --name T --mode private >/dev/null; b claude-block >/dev/null; b git-hide >/dev/null
  check "git status is clean (brain and CLAUDE.local.md hidden)" '[ -z "$(git status --porcelain | grep -v gi.orig)" ]'
  check ".gitignore untouched" 'cmp -s .gitignore gi.orig'
  check "exclude lines added once" 'b git-hide >/dev/null && [ "$(grep -c "^/.brain/\$" .git/info/exclude)" = 1 ]'
  check "privacy-check ok" 'b privacy-check | grep -q "privacy: ok"'
  git commit -q --allow-empty -m "feat: x

Co-Authored-By: Claude Opus <noreply@anthropic.com>"
  check "privacy-check flags an unpushed Claude credit" 'b privacy-check | grep -q "crediting Claude"'
  cd .. && gitinit mono && mkdir -p mono/clients/acme && cd mono/clients/acme
  b scaffold . --name T --mode private >/dev/null; b claude-block >/dev/null; b git-hide >/dev/null
  check "project in a repo subfolder: exclude path is anchored there" 'grep -qx "/clients/acme/.brain/" ../../.git/info/exclude && [ -z "$(git status --porcelain)" ]'
  cd ../.. && git add -f clients/acme/.brain/NOW.md && cd clients/acme
  check "already-tracked brain file is reported" 'b git-hide | grep -q "already tracked"'
}

t_log() {
  b scaffold . --name T --mode private >/dev/null
  echo "first entry" | b log --type status --session abcdef1234 >/dev/null
  f=.brain/log/$(date +%Y-%m-%d).md
  check "day file created with header" 'head -n 1 "$f" | grep -q "^# Log "'
  check "heading has session (8 chars) and type" 'grep -q "^### .* · s:abcdef12 · status\$" "$f"'
  echo "old" | b log --type meeting --date 2026-01-05 --time 09:30 >/dev/null
  check "backfilled entry goes to its own day and is marked" 'grep -q "^### 2026-01-05 09:30 · s:manual · meeting · backfilled\$" .brain/log/2026-01-05.md'
  check "empty text rejected" '! printf "" | b log --type status'
  check "bad date rejected" '! echo x | b log --type status --date 5/1/2026'
  # two writers, 40 entries each, at the same time: none lost, none interleaved
  ( i=0; while [ $i -lt 40 ]; do echo "A$i line1
A$i line2" | b log --type status --session aaaaaaaa >/dev/null; i=$((i+1)); done ) &
  ( i=0; while [ $i -lt 40 ]; do echo "B$i line1
B$i line2" | b log --type status --session bbbbbbbb >/dev/null; i=$((i+1)); done ) &
  wait
  check "80 concurrent entries, none lost" '[ "$(grep -c "^### " "$f")" = 81 ]'
  interleaved() { awk '/^### .*s:aaaaaaaa/ { w = "A" } /^### .*s:bbbbbbbb/ { w = "B" } /line[12]$/ && substr($1, 1, 1) != w { n++ } END { print n + 0 }' "$f"; }
  check "entries not interleaved" '[ "$(interleaved)" = 0 ]'
  check "no lock left behind" '[ -z "$(ls .brain/.locks 2>/dev/null)" ]'
}

t_detect() {
  mkdir -p fresh/intake && echo "job post" > fresh/intake/post.md
  check "near-empty workspace suggests NEW" 'b detect fresh | grep -q "suggested-mode: NEW"'
  check "intake folder is found" 'b detect fresh | grep -q "intake: .*fresh/intake (1 files)"'
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null
  check "workspace in progress suggests ADOPT" 'b detect ws | grep -q "suggested-mode: ADOPT"'
  check "nested repos counted" 'b detect ws | grep -q "nested-repos: 2"'
  check "existing CLAUDE.md reported" 'b detect ws | grep -q "found: CLAUDE.md"'
  check "detect always exits 0" 'b detect fresh && b detect ws'
  check "slug replaces every non-alphanumeric" '[ "$(b slug fresh | tail -c 7)" = "-fresh" ] && ! b slug fresh | grep -q "[^A-Za-z0-9-]"'
}

t_adopt() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null
  cp ws/CLAUDE.md claude.orig
  b snapshot ws > before.txt
  (cd ws && b inventory . >/dev/null)
  check "inventory is read-only" 'b snapshot ws | cmp -s - before.txt'
  check "inventory lists both repos and the dated notes" '(cd ws && b inventory .) | grep -q "### carrier-sync" && (cd ws && b inventory .) | grep -q "2026-07-14  notes/meetings/2026-07-14-kickoff.md"'
  cd ws
  b scaffold . --name Northwind --mode shared --adopt >/dev/null
  b add "carrier-sync/README.md|demand|ext|carrier-sync service overview|touching carrier-sync" >/dev/null
  b add "notes/meetings/|demand|ext|dated meeting notes|checking who said what" >/dev/null
  b add "charter.md|auto|file|why and scope|always" >/dev/null
  echo "Kickoff (notes/meetings/2026-07-14-kickoff.md)" | b log --type meeting --date 2026-07-14 >/dev/null
  b claude-block >/dev/null
  cd ..
  check "NOW.md labelled inferred" 'grep -q "inferred: reconstructed" ws/.brain/NOW.md'
  check "ext rows point at workspace files" 'grep -q "^@ext:notes/meetings/" ws/.brain/MAP.md'
  check "map-check passes" '(cd ws && b map-check)'
  b snapshot ws | grep -v " ./CLAUDE.md\$" > after.txt
  grep -v " ./CLAUDE.md\$" before.txt > before2.txt
  check "every workspace file byte-identical (except CLAUDE.md)" 'cmp -s before2.txt after.txt'
  check "CLAUDE.md: original kept, backup made" '[ "$(head -c "$(wc -c < claude.orig)" ws/CLAUDE.md | cksum)" = "$(cksum < claude.orig)" ] && cmp -s claude.orig ws/.brain/archive/backups/CLAUDE.md.*.bak'
  check "git repos untouched (clean status)" '[ -z "$(git -C ws/carrier-sync status --porcelain)" ] && [ -z "$(git -C ws/wms-adapter status --porcelain)" ]'
}

t_skill() {
  s="$ROOT/skills/init/SKILL.md"
  check "SKILL.md has frontmatter with name and description" 'head -n 1 "$s" | grep -qx -- "---" && grep -q "^name: init\$" "$s" && grep -q "^description: " "$s"'
  check "init is user-invoked only" 'grep -q "^disable-model-invocation: true\$" "$s"'
  check "every reference file named in the skill exists" 'for r in $(grep -o "reference/[a-z]*\.md" "$s" "$ROOT"/skills/init/reference/*.md | sed "s/.*reference/reference/" | sort -u); do [ -f "$ROOT/skills/init/$r" ] || exit 1; done'
  check "plugin.json is valid-looking and versioned" 'grep -q "\"name\": \"project-brain\"" "$ROOT/.claude-plugin/plugin.json" && grep -q "\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"" "$ROOT/.claude-plugin/plugin.json"'
  check "no script has CRLF line endings" '! grep -rl "$(printf "\r")" "$ROOT/scripts" "$ROOT/tests/run.sh"'
}

for t in json scaffold add mapcheck claudeblock githide log detect adopt skill; do run "$t"; done

PASS=$(grep -c '^ok$' "$W/.results" 2>/dev/null || true); FAIL=$(grep -c '^FAIL' "$W/.results" 2>/dev/null || true)
echo
echo "passed: ${PASS:-0}  failed: ${FAIL:-0}"
[ "${FAIL:-0}" -gt 0 ] && grep '^FAIL' "$W/.results" | sed 's/^/  /'
rm -rf "$W"
[ "${FAIL:-0}" -eq 0 ]

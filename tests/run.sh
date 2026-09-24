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
  check "every reference file named in the skill exists" '(for r in $(grep -o "reference/[a-z]*\.md" "$s" "$ROOT"/skills/init/reference/*.md | sed "s/.*reference/reference/" | sort -u); do [ -f "$ROOT/skills/init/$r" ] || exit 1; done)'
  check "plugin.json is valid-looking and versioned" 'grep -q "\"name\": \"project-brain\"" "$ROOT/.claude-plugin/plugin.json" && grep -q "\"version\": \"[0-9]*\.[0-9]*\.[0-9]*\"" "$ROOT/.claude-plugin/plugin.json"'
  check "no script has CRLF line endings" '! grep -rl "$(printf "\r")" "$ROOT/scripts" "$ROOT/tests/run.sh"'
}

# --- M2: SessionStart / SessionEnd hook -----------------------------------------------------------
H="$ROOT/scripts/hook.sh"
hk() {   # hk <event> <session id> <source> [cwd]: run the hook like Claude Code does
  printf '{"session_id":"%s","transcript_path":"/nowhere.jsonl","cwd":"%s","hook_event_name":"x","source":"%s"}' \
    "$2" "${4:-$(pwd)}" "$3" | ${PB_SH:-sh} "$H" "$1"
}
ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000' 2>/dev/null || echo $(( $(date +%s) * 1000 )); }

t_hookquiet() {
  mkdir plain && cd plain
  check "no brain: prints nothing" '[ -z "$(hk session-start s1 startup)" ]'
  check "no brain: creates nothing" 'hk session-start s1 startup >/dev/null; [ -z "$(ls -A)" ]'
  check "no brain: exit code 0" 'hk session-start s1 startup; hk session-end s1 other'
  check "garbage input: silent, exit 0" '[ -z "$(printf "not json" | sh "$H" session-start)" ]'
  check "empty input: silent, exit 0" '[ -z "$(sh "$H" session-start < /dev/null)" ]'
  check "unknown event: silent, exit 0" '[ -z "$(hk nonsense s1 startup)" ]'
}

t_hookstart() {
  b scaffold . --name "Hook Co" --mode private >/dev/null
  printf '## Focus\nShip the importer [meeting]\n' > focus.txt
  awk '/^## Focus/ { print; getline; print "Ship the importer [meeting] (sources/x.md)"; next } { print }' .brain/NOW.md > n && mv n .brain/NOW.md
  echo "decided X" | b log --type decision --session other111 >/dev/null
  export CLAUDE_ENV_FILE="$W/envfile"; : > "$CLAUDE_ENV_FILE"
  out=$(hk session-start abcdef1234567 startup)
  check "summary names the project" 'printf "%s" "$out" | grep -q "^# Project brain: Hook Co"'
  check "summary tells the session its id" 'printf "%s" "$out" | grep -q "You are session s:abcdef12"'
  check "summary includes NOW.md focus" 'printf "%s" "$out" | grep -q "Ship the importer"'
  check "summary skips empty NOW sections" '! printf "%s" "$out" | grep -q "^### Blockers"'
  check "summary includes today log tail" 'printf "%s" "$out" | grep -q "s:other111 · decision: decided X"'
  check "session file registered as live" 'grep -q "^status: live" .brain/sessions/abcdef12.md && grep -q "^last-start: .*(startup)" .brain/sessions/abcdef12.md'
  check "seen marker written" 'grep -q "^$(date +%Y-%m-%d).md [0-9]" .brain/sessions/abcdef12.seen'
  check "env file exports session and brain" 'grep -q "BRAIN_SESSION=.abcdef12" "$CLAUDE_ENV_FILE" && grep -q "PB_BRAIN=" "$CLAUDE_ENV_FILE"'
  check "map-check still passes (session files are mapped)" 'b claude-block >/dev/null && b map-check'
  out2=$(hk session-start 99999999aaaa startup)
  check "a second session sees the first as live" 'printf "%s" "$out2" | grep -q "^- s:abcdef12 · goal not set"'
  check "a session does not list itself" '! printf "%s" "$out2" | grep -q "^- s:99999999"'
  touch -t 202001010000 .brain/sessions/abcdef12.*
  check "sessions idle for over 24 h are not listed" '! hk session-start 77777777 startup | grep -q "s:abcdef12"'
  echo hi > q1.txt; hp abcdef1234567 q1.txt >/dev/null
  hk session-end abcdef1234567 other >/dev/null
  check "session end marks the file ended" 'grep -q "^status: ended " .brain/sessions/abcdef12.md'
  check "resume makes it live again" 'hk session-start abcdef1234567 resume >/dev/null; grep -q "^status: live" .brain/sessions/abcdef12.md && grep -q "(resume)" .brain/sessions/abcdef12.md'
  check "only one last-start line after several starts" '[ "$(grep -c "^last-start:" .brain/sessions/abcdef12.md)" = 1 ]'
  check "compact says the context was compacted" 'hk session-start abcdef1234567 compact | grep -q "Context was just compacted"'
  check "works when the hook runs from inside .brain/" '(cd .brain && hk session-start abcdef1234567 startup "$(pwd)") | grep -q "Hook Co"'
  check "inferred NOW.md is flagged" 'b scaffold "$W/hookstart2" --name X --mode shared --adopt >/dev/null 2>&1 || { mkdir -p "$W/hookstart2" && b scaffold "$W/hookstart2" --name X --mode shared --adopt >/dev/null; }; (cd "$W/hookstart2" && hk session-start s2 startup) | grep -q "still marked inferred"'
  unset CLAUDE_ENV_FILE
}

t_hookbudget() {
  b scaffold . --name Big --mode private >/dev/null
  i=0; while [ $i -lt 400 ]; do echo "- item $i with a fairly long description to fill the budget quickly · owner · open"; i=$((i+1)); done > items.txt
  awk -v f=items.txt '/^## Items/ { print; while ((getline l < f) > 0) print l; next } { print }' .brain/NOW.md > n && mv n .brain/NOW.md
  i=0; while [ $i -lt 60 ]; do echo "entry $i" | b log --type status >/dev/null; i=$((i+1)); done
  out=$(hk session-start bigbig12 startup)
  check "long sections are cut with a pointer" 'printf "%s" "$out" | grep -q "more lines in .brain/NOW.md"'
  check "whole summary stays under 8000 characters" '[ "$(printf "%s" "$out" | wc -c)" -le 8000 ]'
  check "today tail shows at most 8 entries" '[ "$(printf "%s" "$out" | grep -c "· status: entry")" -le 8 ]'
}

t_hookdrift() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  b scaffold . --name NW --mode shared --adopt >/dev/null
  h=$(git -C carrier-sync log -1 --format=%h)
  awk -v h="$h" '/^## Freshness/ { print; print "- repo carrier-sync · last seen " h " · 2026-09-15"; print "- repo gone-repo · last seen abc1234 · 2026-09-01"; next } { print }' .brain/NOW.md > n && mv n .brain/NOW.md
  check "no drift when nothing changed" '! hk session-start d1 startup | grep -q "carrier-sync: .* new commit"'
  (cd carrier-sync && echo x > new.py && git add new.py && git -c user.name=T -c user.email=t@e commit -qm "new work")
  check "new commits since the Freshness stamp are reported" 'hk session-start d1 startup | grep -q "carrier-sync: 1 new commit(s) since $h"'
  check "a missing repo is reported, not fatal" 'hk session-start d1 startup | grep -q "gone-repo: last-seen commit abc1234 not found"'
}

t_hookspeed() {
  export CLAUDE_PROJECT_DIR   # time the hooks the way Claude Code runs them
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  b scaffold . --name NW --mode private --adopt >/dev/null
  i=0; while [ $i -lt 30 ]; do echo "entry $i" | b log --type status --session s$i >/dev/null; i=$((i+1)); done
  CLAUDE_PROJECT_DIR=$(pwd)
  i=0; while [ $i -lt 6 ]; do hk session-start "sess$i" startup >/dev/null; i=$((i+1)); done
  t0=$(ms); i=0; while [ $i -lt 5 ]; do hk session-start speed123 startup >/dev/null; i=$((i+1)); done; t1=$(ms)
  avg=$(( (t1 - t0) / 5 ))
  echo "        session-start average: ${avg} ms"
  check "session-start under 1000 ms on average" '[ "$avg" -lt 1000 ]'
  cd "$W" && mkdir -p quiet && cd quiet
  CLAUDE_PROJECT_DIR=$(pwd)
  t0=$(ms); i=0; while [ $i -lt 5 ]; do hk session-start q startup >/dev/null; i=$((i+1)); done; t1=$(ms)
  avg=$(( (t1 - t0) / 5 )); echo "        no-brain exit average: ${avg} ms"
  check "no-brain exit under 150 ms on average" '[ "$avg" -lt 150 ]'
}

t_hooksjson() {
  j="$ROOT/hooks/hooks.json"
  check "hooks.json exists and names both events" 'grep -q "\"SessionStart\"" "$j" && grep -q "\"SessionEnd\"" "$j"'
  check "every hook command points at an existing script" '(for s in $(grep -o "scripts/[a-z.-]*\.sh" "$j" | sort -u); do [ -f "$ROOT/$s" ] || exit 1; done)'
  check "commands use CLAUDE_PLUGIN_ROOT and sh" '! grep "\"command\"" "$j" | grep -v "sh \\\\\"\${CLAUDE_PLUGIN_ROOT}/"'
  check "no probe hook left active" '! grep -q probe "$j"'
}

# --- M3: capture, redaction, digest, attachments ------------------------------------------------
hp() {   # hp <session> <prompt file> [scratchpad] [transcript]: run the prompt hook
  LC_ALL=C awk -v sid="$1" -v cwd="$(pwd)" -v sp="${3:-}" -v tp="${4:-}" '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); return s }
    { body = body (NR > 1 ? "\\n" : "") esc($0) }
    END { printf "{\"session_id\":\"%s\",\"transcript_path\":\"%s\",\"cwd\":\"%s\",\"scratchpad_dir\":\"%s\",\"prompt_id\":\"p-%s\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"%s\"}", sid, tp, cwd, sp, NR, body }' "$2" |
    ${PB_SH:-sh} "$H" prompt
}
hs() {   # hs <session> <transcript> [scratchpad]: run the Stop hook and wait for its background work
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","scratchpad_dir":"%s","hook_event_name":"Stop"}' "$1" "$2" "$(pwd)" "${3:-}" |
    ${PB_SH:-sh} "$H" stop
  i=0; while [ $i -lt 40 ]; do sleep 0.1; [ -s ".brain/sessions/$(printf %s "$1" | cut -c1-8).pending" ] && break; i=$((i+1)); done
}
DT="$ROOT/tests/detector"

t_detector() {
  total=0; right=0; wrong=""
  for d in context plain; do
    for f in "$DT/$d"/*.txt; do
      total=$((total + 1)); r=$(LC_ALL=C awk -f "$ROOT/scripts/detect.awk" < "$f")
      if [ "${r%% *}" = "$d" ]; then right=$((right + 1)); else wrong="$wrong $d/$(basename "$f")"; fi
    done
  done
  echo "        detector: $right of $total right${wrong:+; wrong:$wrong}"
  check "at least 20 samples of each kind" '[ "$(ls "$DT/context" | wc -l)" -ge 20 ] && [ "$(ls "$DT/plain" | wc -l)" -ge 20 ]'
  check "every sample classified correctly" '[ "$right" = "$total" ]'
  check "an empty prompt is plain" '[ "$(printf "" | awk -f "$ROOT/scripts/detect.awk")" = "plain short" ]'
}

t_redact() {
  cat > s.txt <<'EOF'
- password: Tr0ub4dor&3xample
- API key: sk-live-4f9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c
aws AKIAIOSFODNN7EXAMPLE and ghp_abcdefghijklmnopqrstuvwxyz0123456789
Authorization: Bearer abc.def-ghi_jkl.mno123456789
db: postgres://svc:hunter2pass@db.internal:5432/app
slack xoxb-123456789012-abcdefghijk
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA
-----END RSA PRIVATE KEY-----
The go-live is on 2026-10-15 and the token budget is fine.
EOF
  sh "$ROOT/scripts/redact.sh" rep.txt < s.txt > out.txt
  for s in Tr0ub4dor sk-live-4f9a AKIAIOSFODNN7 ghp_abcdef abc.def-ghi hunter2pass xoxb-1234 MIIEowIBAAKCAQEA; do
    check "removed: $s" '! grep -q "$s" out.txt'
  done
  check "normal text untouched" 'grep -qx "The go-live is on 2026-10-15 and the token budget is fine." out.txt'
  check "report lists the kinds" 'grep -q "^aws-key 1" rep.txt && grep -q "^private-key 1" rep.txt'
  check "clean text gives an empty report" 'echo "nothing secret here" | sh "$ROOT/scripts/redact.sh" rep2.txt >/dev/null && [ ! -s rep2.txt ]'
}

t_capture() {
  b scaffold . --name Cap --mode private >/dev/null
  hk session-start aaaaaaaa1111 startup >/dev/null
  out=$(hp aaaaaaaa1111 "$DT/context/zoom-transcript.txt")
  f=$(ls .brain/sources/inbox/*-aaaaaaaa.md 2>/dev/null | head -n 1)
  check "pasted transcript saved to the inbox" '[ -n "$f" ]'
  check "saved copy has the metadata" 'grep -q "^detected: transcript" "$f" && grep -q "^session: aaaaaaaa" "$f" && grep -q "^prompt_id: p-" "$f"'
  body() { awk 'NR == 1 && /^---$/ { f = 1; next } f && /^---$/ { f = 0; next } !f' "$1"; }
  check "saved text is verbatim" '[ "$(body "$f" | cksum)" = "$(cksum < "$DT/context/zoom-transcript.txt")" ]'
  check "hook tells the session what it saved" 'printf "%s" "$out" | grep -q "Saved the pasted transcript verbatim to .brain/sources/inbox/"'
  check "output is one line of JSON for UserPromptSubmit" '[ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 1 ] && printf "%s" "$out" | grep -q "^{\"hookSpecificOutput\":{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\".*\"}}\$"'
  check "a capture log entry is written" 'grep -q "· s:aaaaaaaa · capture · inbox" .brain/log/$(date +%Y-%m-%d).md'
  n=$(ls .brain/sources/inbox | wc -l)
  check "code is not captured, and nothing is said" '[ -z "$(hp aaaaaaaa1111 "$DT/plain/python-trace.txt")" ] && [ "$(ls .brain/sources/inbox | wc -l)" = "$n" ]'
  check "a short instruction is not captured" '[ -z "$(hp aaaaaaaa1111 "$DT/plain/instructions-short.txt")" ]'
  out=$(hp aaaaaaaa1111 "$DT/context/with-secret.txt")
  g=$(ls -t .brain/sources/inbox/*.md | head -n 1)
  check "secrets removed from the saved copy" '! grep -q "Tr0ub4dor" "$g" && ! grep -q "sk-live-4f9a" "$g" && grep -q "REDACTED" "$g"'
  check "the session is told credentials were removed" 'printf "%s" "$out" | grep -q "credentials removed"'
  check "prompts are counted" '[ "$(wc -l < .brain/sessions/aaaaaaaa.prompts | tr -d " ")" = 4 ]'
  check "map-check passes after captures" 'b claude-block >/dev/null && b map-check'
  check "no brain: prompt hook is silent" 'mkdir -p "$W/nobrain" && (cd "$W/nobrain" && [ -z "$(hp x1 "$DT/context/zoom-transcript.txt")" ] && [ -z "$(ls -A)" ])'
}

t_digest() {
  b scaffold . --name Dig --mode private >/dev/null
  hk session-start aaaaaaaa startup >/dev/null; hk session-start bbbbbbbb startup >/dev/null
  echo x > q.txt
  check "nothing new: no output" '[ -z "$(hp bbbbbbbb q.txt)" ]'
  echo "Priya confirmed weekend rota" | b log --type decision --session aaaaaaaa >/dev/null
  echo "my own note" | b log --type status --session bbbbbbbb >/dev/null
  echo "old meeting" | b log --type meeting --date 2026-01-02 --session aaaaaaaa >/dev/null
  out=$(hp bbbbbbbb q.txt)
  check "digest shows the other session's entry" 'printf "%s" "$out" | grep -q "s:aaaaaaaa decision: Priya confirmed weekend rota \[log/"'
  check "digest leaves out the session's own entries" '! printf "%s" "$out" | grep -q "my own note"'
  check "backfilled entries are only counted" 'printf "%s" "$out" | grep -q "+1 backfilled"'
  check "the same entries are not shown twice" '[ -z "$(hp bbbbbbbb q.txt)" ]'
  i=0; while [ $i -lt 9 ]; do echo "step $i" | b log --type status --session aaaaaaaa >/dev/null; i=$((i+1)); done
  out=$(hp bbbbbbbb q.txt)
  check "long digests keep the newest 6" 'printf "%s" "$out" | grep -q "+3 earlier entries" && printf "%s" "$out" | grep -q "step 8" && ! printf "%s" "$out" | grep -q "step 2 "'
  mkdir -p .brain/log && echo "structure note" | b log --type structure --session aaaaaaaa >/dev/null
  check "structure changes show up in the digest" 'hp bbbbbbbb q.txt | grep -q "s:aaaaaaaa structure: structure note"'
}

t_images() {
  b scaffold . --name Img --mode private >/dev/null
  sp="$W/images/sess1/scratchpad"; mkdir -p "$sp" "$W/images/sess1/images"
  printf 'old' > "$W/images/sess1/images/1.png"
  printf '{"session_id":"img11111","cwd":"%s","scratchpad_dir":"%s","source":"resume"}' "$(pwd)" "$sp" | sh "$H" session-start >/dev/null
  echo "probe 2" > q.txt
  check "images present before the session registered are not captured" '[ -z "$(hp img11111 q.txt "$sp")" ]'
  printf '\211PNG fake' > "$W/images/sess1/images/2.png"
  out=$(hp img11111 q.txt "$sp")
  check "a newly pasted image is copied to the inbox" 'ls .brain/sources/inbox/*-img11111-img-2.png >/dev/null 2>&1'
  check "the copy is byte-identical" 'cmp -s "$W/images/sess1/images/2.png" .brain/sources/inbox/*-img11111-img-2.png'
  check "the session is told" 'printf "%s" "$out" | grep -q "Saved the pasted image(s)"'
  check "the same image is not copied twice" '[ -z "$(hp img11111 q.txt "$sp")" ] && [ "$(ls .brain/sources/inbox | grep -c img-2.png)" = 1 ]'
  cp "$W/images/sess1/images/2.png" "$W/images/sess1/images/3.png"
  check "an identical image pasted again is not stored twice" 'hp img11111 q.txt "$sp" | grep -q "already in the brain, not saved again" && [ -z "$(ls .brain/sources/inbox | grep img-3.png)" ]'
}

t_attach() {
  b scaffold . --name Att --mode private >/dev/null
  printf '%%PDF-1.4 fake pdf bytes \001\002\003 end' > memo.pdf
  b64=$(base64 < memo.pdf | tr -d '\n')
  tp="$W/attach.jsonl"
  echo '{"type":"summary","x":1}' > "$tp"
  printf '{"type":"user","message":{"role":"user","content":[{"type":"document","source":{"type":"base64","media_type":"application/pdf","data":"%s"},"title":"probe memo.pdf"},{"type":"document","source":{"type":"text","media_type":"text/plain","data":"line one\\nsecret: hunter2\\n"},"title":"notes.txt"},{"type":"text","text":"probe 3"}]},"origin":{"kind":"human"}}\n' "$b64" > line.json
  printf '{"session_id":"att11111","cwd":"%s","transcript_path":"%s","source":"startup"}' "$(pwd)" "$tp" | sh "$H" session-start >/dev/null
  cat line.json >> "$tp"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}\n' >> "$tp"
  hs att11111 "$tp"
  pdf=$(ls .brain/sources/inbox/*-att11111-probe-memo.pdf 2>/dev/null | head -n 1)
  check "PDF from the transcript saved under its own name" '[ -n "$pdf" ]'
  check "PDF bytes identical to the original" 'cmp -s memo.pdf "$pdf"'
  check "text attachment saved, with secrets removed" 'txt=$(ls .brain/sources/inbox/*-notes.txt) && grep -q "line one" "$txt" && ! grep -q hunter2 "$txt"'
  check "the next prompt is told about them" 'echo hi > q.txt; hp att11111 q.txt | grep -q "Attachments from your previous message: saved: .brain/sources/inbox/"'
  check "the notice is given only once" '[ -z "$(hp att11111 q.txt)" ]'
  n=$(ls .brain/sources/inbox | wc -l)
  hs att11111 "$tp"; sleep 0.5
  check "a second Stop does not save them again" '[ "$(ls .brain/sources/inbox | wc -l)" = "$n" ]'
  check "attachments in lines before registration are ignored" 'printf "{\"session_id\":\"att22222\",\"cwd\":\"%s\",\"transcript_path\":\"%s\",\"source\":\"resume\"}" "$(pwd)" "$tp" | sh "$H" session-start >/dev/null; hs att22222 "$tp"; sleep 0.5; [ -z "$(ls .brain/sources/inbox | grep att22222)" ]'
  cat line.json >> "$tp"; hs att11111 "$tp"
  check "the same file attached again is not stored twice" '[ "$(ls .brain/sources/inbox | grep -c probe-memo.pdf)" = 1 ]'
  check "the session is told where the existing copy is" 'hp att11111 q.txt | grep -q "already in the brain, not saved again: .brain/sources/inbox/.*probe-memo.pdf"'
  check "tool results (not typed by a person) are ignored" 'printf "{\"type\":\"user\",\"message\":{\"content\":[{\"tool_use_id\":\"t1\",\"type\":\"tool_result\",\"content\":[{\"type\":\"document\",\"source\":{\"type\":\"text\",\"media_type\":\"text/plain\",\"data\":\"tool\"},\"title\":\"tool.txt\"}]}]}}\n" >> "$tp"; hs att22222 "$tp"; sleep 0.5; [ -z "$(ls .brain/sources/inbox | grep tool.txt)" ]'
}

t_phantom() {
  b scaffold . --name Ph --mode private >/dev/null
  hk session-start ghost123 startup >/dev/null; hk session-end ghost123 other >/dev/null
  check "a session with no prompt leaves no files" '[ -z "$(ls .brain/sessions | grep ghost123)" ]'
  hk session-start real1234 startup >/dev/null; echo hi > q.txt; hp real1234 q.txt >/dev/null; hk session-end real1234 other >/dev/null
  check "a session with a prompt is kept and marked ended" 'grep -q "^status: ended" .brain/sessions/real1234.md'
}

t_promptspeed() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  export CLAUDE_PROJECT_DIR=$(pwd)   # time the hooks the way Claude Code runs them
  b scaffold . --name NW --mode private --adopt >/dev/null
  hk session-start sp111111 startup >/dev/null; hk session-start sp222222 startup >/dev/null
  echo "what next?" > q.txt
  t0=$(ms); i=0; while [ $i -lt 10 ]; do hp sp111111 q.txt >/dev/null; i=$((i+1)); done; t1=$(ms)
  a=$(( (t1 - t0) / 10 )); echo "        prompt hook, plain prompt: ${a} ms"
  check "plain prompt under 200 ms" '[ "$a" -lt 200 ]'
  t0=$(ms); i=0; while [ $i -lt 10 ]; do echo "entry $i" | b log --type status --session sp222222 >/dev/null; hp sp111111 "$DT/context/meeting-notes.txt" >/dev/null; i=$((i+1)); done; t1=$(ms)
  # subtract the time of the log calls, measured separately
  l0=$(ms); i=0; while [ $i -lt 10 ]; do echo "entry $i" | b log --type status --session sp222222 >/dev/null; i=$((i+1)); done; l1=$(ms)
  a=$(( (t1 - t0 - (l1 - l0)) / 10 )); echo "        prompt hook, capture + digest: ${a} ms"
  check "capture and digest under 200 ms" '[ "$a" -lt 200 ]'
}

# --- M4: claims, structure changes, capture, catch-up, tidy, upgrade, skills --------------------
brain4() {   # a small brain with a few files and references, in the current folder
  b scaffold . --name Four --mode shared >/dev/null
  b add "charter.md|auto|file|why and scope|always" >/dev/null
  b add "decisions.md|demand|file|decisions log|before changing direction" >/dev/null
  b add "specs|demand|dir|feature specs|building a feature" >/dev/null
  b add "notes/todo.txt|demand|ext|owner todo list|planning" >/dev/null 2>&1
  echo "spec" > .brain/specs/login.md
  printf '\nSee decisions.md and .brain/decisions.md, specs/login.md; not mydecisions.md or decisions.md.bak.\n' >> .brain/charter.md
  b claude-block >/dev/null
}

t_claims() {
  brain4
  check "claim works" 'b claim "split decisions.md" --session aaaa1111 | grep -q "^claimed: split decisions.md"'
  check "claim shows in NOW.md and the session file" 'grep -q "^- \[claim\] split decisions.md · s:aaaa1111" .brain/NOW.md && grep -q "\[claim\] split decisions.md" .brain/sessions/aaaa1111.md'
  check "an overlapping claim by another session is refused" '! b claim "merge decisions.md into charter.md" --session bbbb2222 >/dev/null'
  check "a whole-brain structure claim conflicts with any claim" '! b claim "structure" --session bbbb2222 >/dev/null'
  check "an unrelated claim is fine" 'b claim "update the NOW items" --session bbbb2222 >/dev/null'
  check "the same session may add overlapping claims" 'b claim "retire decisions.md" --session aaaa1111 >/dev/null'
  check "claims lists them as active" '[ "$(b claims | grep -c "^active")" = 3 ]'
  check "release one claim" 'b release "split decisions.md" --session aaaa1111 | grep -q "released: 1" && ! grep -q "split decisions.md" .brain/NOW.md'
  check "release --all clears only this session" 'b release --all --session aaaa1111 >/dev/null && ! grep -q "s:aaaa1111" .brain/NOW.md && grep -q "s:bbbb2222" .brain/NOW.md'
  check "no session id: refused with a hint" '! b claim "x.md" 2>/dev/null'
  b claim "retier charter.md" --hours 0 --session cccc3333 >/dev/null
  sleep 1
  check "expired claims are listed as expired" 'b claims | grep -q "^EXPIRED .*retier charter.md"'
  check "the start summary warns about expired claims" 'hk session-start zzzz9999 startup | grep -q "1 expired claim"'
  check "an expired claim does not block others" 'b claim "retier charter.md" --session dddd4444 >/dev/null'
  check "claims --expire removes expired ones" 'b claim "x/y.md" --hours 0 --session eeee5555 >/dev/null; sleep 1; b claims --expire | grep -q "expired:" && ! grep -q "s:eeee5555" .brain/NOW.md'
  check "other NOW.md sections are untouched by claims" 'grep -q "^## Focus" .brain/NOW.md && grep -q "^## Freshness" .brain/NOW.md'
}

t_move() {
  brain4
  check "move needs a claim" '! b move decisions.md choices.md --session aaaa1111 --why x 2>/dev/null && [ -f .brain/decisions.md ]'
  b claim "rename decisions.md" --session aaaa1111 >/dev/null
  check "move with a claim works" 'b move decisions.md choices.md --session aaaa1111 --why "clearer name" | grep -q "moved: decisions.md → choices.md"'
  check "the file moved" '[ -f .brain/choices.md ] && [ ! -e .brain/decisions.md ]'
  check "the MAP row moved, tier and holds kept" 'grep -q "^choices.md *| demand | file | decisions log" .brain/MAP.md && ! grep -q "^decisions.md" .brain/MAP.md'
  check "references rewritten (plain and .brain/ forms)" 'grep -q "See choices.md and .brain/choices.md" .brain/charter.md'
  check "look-alike names untouched" 'grep -q "not mydecisions.md or decisions.md.bak" .brain/charter.md'
  check "claim lines are never rewritten" 'grep -q "\[claim\] rename decisions.md" .brain/NOW.md'
  check "a structure entry is logged with old → new" 'grep -q "move: decisions.md → choices.md. Why: clearer name" .brain/log/$(date +%Y-%m-%d).md'
  check "map-check and refs-check pass" 'b map-check && [ -z "$(b refs-check)" ]'
  b claim "rename charter.md" --session aaaa1111 >/dev/null
  check "moving an auto file updates the CLAUDE block" 'b move charter.md project-charter.md --session aaaa1111 --why x >/dev/null && grep -qx "@.brain/project-charter.md" CLAUDE.md && b map-check'
  check "moving a folder" 'b claim "rename specs" --session aaaa1111 >/dev/null && b move specs features --session aaaa1111 --why x >/dev/null && [ -f .brain/features/login.md ] && grep -q "features/login.md" .brain/project-charter.md && b map-check'
  check "the fixed core cannot be moved" 'b claim "structure" --session aaaa1111 >/dev/null 2>&1; ! b move NOW.md now2.md --session aaaa1111 --why x 2>/dev/null'
  check "a workspace link cannot be moved" '! b move "@ext:notes/todo.txt" x.txt --session aaaa1111 --why x 2>/dev/null'
}

t_retire() {
  brain4
  b claim "retire specs" --session aaaa1111 >/dev/null
  check "retire a folder" 'b retire specs --session aaaa1111 --why "unused" | grep -q "retired: specs/ → archive/specs/"'
  check "moved to archive, never deleted" '[ -f .brain/archive/specs/login.md ] && [ ! -e .brain/specs ]'
  check "the MAP row is gone" '! grep -q "^specs/" .brain/MAP.md'
  check "references point to the archive" 'grep -q "archive/specs/login.md" .brain/charter.md'
  check "retire needs a claim" '! b retire decisions.md --session bbbb2222 --why x 2>/dev/null'
  b claim "merge decisions.md" --session aaaa1111 >/dev/null
  check "retire after a merge: references point to the kept file" 'b retire decisions.md --refs-to charter.md --session aaaa1111 --why "merged" >/dev/null && grep -q "See charter.md and .brain/charter.md" .brain/charter.md && grep -q "(merged into charter.md)" .brain/log/$(date +%Y-%m-%d).md'
  b claim "retire @ext:notes/todo.txt" --session aaaa1111 >/dev/null
  mkdir -p notes && echo keep > notes/todo.txt
  check "retiring a link drops the row and leaves the workspace file" 'b retire "@ext:notes/todo.txt" --session aaaa1111 --why x >/dev/null && ! grep -q "notes/todo.txt" .brain/MAP.md && [ "$(cat notes/todo.txt)" = keep ]'
  echo x > .brain/archive/decisions.md.x
  b add "decisions.md|demand|file|decisions again|x" >/dev/null; b claim "retire decisions.md" --session aaaa1111 >/dev/null
  check "a second retire of the same name gets a dated archive name" 'b retire decisions.md --session aaaa1111 --why x | grep -q "archive/$(date +%Y-%m-%d)-decisions.md"'
  check "the fixed core cannot be retired" '! b retire log --session aaaa1111 --why x 2>/dev/null'
  check "map-check and refs-check pass" 'b map-check && [ -z "$(b refs-check)" ]'
}

t_retier() {
  brain4
  check "retier to auto adds the import" 'b retier decisions.md auto | grep -q "retiered: decisions.md demand → auto" && grep -qx "@.brain/decisions.md" CLAUDE.md'
  check "retier back to demand removes it" 'b retier decisions.md demand >/dev/null && ! grep -q "@.brain/decisions.md" CLAUDE.md && b map-check'
  check "bad tier rejected" '! b retier decisions.md always 2>/dev/null'
  check "the fixed core cannot be retiered" '! b retier NOW.md auto 2>/dev/null'
}

t_refs() {
  brain4
  check "clean brain: no broken references" '[ -z "$(b refs-check)" ]'
  echo "Details in sources/meetings/2026-01-01-gone.md and .brain/specs/nope.md" >> .brain/charter.md
  check "broken brain paths are reported" 'b refs-check | grep -q "BROKEN: charter.md mentions sources/meetings/2026-01-01-gone.md" && b refs-check | grep -q "specs/nope.md"'
  echo "The client repo has notes/meetings/x.md and src/app.py" >> .brain/charter.md
  check "workspace paths are not reported" '! b refs-check | grep -q "src/app.py"'
}

t_capturecmd() {
  brain4
  printf 'x%%PDF bytes' > memo.pdf
  check "capture a file from disk" 'b capture memo.pdf --session aaaa1111 | grep -q "saved: .brain/sources/inbox/.*-aaaa1111-memo.pdf" && cmp -s memo.pdf .brain/sources/inbox/*-memo.pdf'
  check "the workspace file stays" '[ -f memo.pdf ]'
  check "the same file twice is not stored twice" 'b capture memo.pdf --session aaaa1111 | grep -q "already in the brain" && [ "$(ls .brain/sources/inbox | grep -c memo.pdf)" = 1 ]'
  printf 'Call notes\npassword: abc123\n' > notes.txt
  check "text files are redacted" 'b capture notes.txt --session aaaa1111 | grep -q "credentials removed" && ! grep -q abc123 .brain/sources/inbox/*-notes.txt'
  check "text on stdin gets metadata" 'echo "Kofi approved the budget" | b capture --kind note --session aaaa1111 >/dev/null && grep -q "^detected: note" .brain/sources/inbox/*-aaaa1111.md'
  check "a capture is logged" 'grep -q "capture · inbox" .brain/log/$(date +%Y-%m-%d).md'
  check "empty stdin is refused" '! printf "" | b capture --session aaaa1111 2>/dev/null'
}

t_catchup() {
  brain4
  hk session-start aaaa1111 startup >/dev/null; hk session-start bbbb2222 startup >/dev/null
  echo "A decided the thing" | b log --type decision --session aaaa1111 >/dev/null
  echo "B own note" | b log --type status --session bbbb2222 >/dev/null
  echo x > .brain/sources/inbox/20260101-000000-aaaa1111.md
  out=$(b catchup --session bbbb2222)
  check "shows other sessions' entries in full" 'printf "%s" "$out" | grep -q "s:aaaa1111 · decision" && printf "%s" "$out" | grep -q "A decided the thing"'
  check "leaves out its own entries" '! printf "%s" "$out" | grep -q "B own note"'
  check "lists unfiled captures" 'printf "%s" "$out" | grep -q "sources/inbox/20260101-000000-aaaa1111.md"'
  check "lists other live sessions" 'printf "%s" "$out" | grep -q "s:aaaa1111"'
  echo q > q.txt
  check "the digest does not repeat what catchup showed" '! hp bbbb2222 q.txt | grep -q "A decided the thing"'
}

t_tidy() {
  brain4
  head -c 12000 /dev/zero | tr '\0' 'x' | fold -w 80 > .brain/decisions.md
  b add "glossary.md|demand|file|terms and names from feature specs|x" >/dev/null
  touch -t 202001010000 .brain/charter.md
  echo x > .brain/sources/inbox/leftover.md
  out=$(b tidy-report)
  check "big files are flagged" 'printf "%s" "$out" | grep -q "decisions.md (demand): ~3[0-9]* tokens"'
  check "stale files are flagged" 'printf "%s" "$out" | sed -n "/Untouched/,/^\$/p" | grep -q charter.md'
  check "empty starters are flagged" 'printf "%s" "$out" | sed -n "/empty starter/,/^\$/p" | grep -q glossary.md'
  check "possible overlaps are listed" 'printf "%s" "$out" | sed -n "/overlaps/,/^\$/p" | grep -q "glossary.md"'
  check "unfiled captures are listed" 'printf "%s" "$out" | grep -q "sources/inbox/leftover.md"'
  check "map and privacy sections are there" 'printf "%s" "$out" | grep -q "^## Map" && printf "%s" "$out" | grep -q "^## Privacy"'
  check "the report changes nothing" 'sums() { find . -type f | LC_ALL=C sort | while read -r f; do cksum "$f"; done; }; sums > "$W/tidy1"; b tidy-report >/dev/null; sums | cmp -s - "$W/tidy1"'
}

t_upgrade() {
  brain4
  mkdir -p up
  printf '#!/bin/sh\n# add a risks.md file and its MAP row\nsh "$PB_ROOT/scripts/brain.sh" add "risks.md|demand|file|risks|planning" >/dev/null\n' > up/2.sh
  check "same format: up to date" 'b upgrade | grep -q "up to date: brain format 1"'
  check "the start summary warns when the brain is older" 'PB_FORMAT_OVERRIDE=2 hk session-start up111111 startup | grep -q "older than the plugin"'
  cp .brain/charter.md charter.before
  check "dry run lists the steps and changes nothing" 'PB_FORMAT_OVERRIDE=2 PB_UPGRADES="$(pwd)/up" b upgrade --dry-run | grep -q "step 1 → 2: add a risks.md file" && [ ! -e .brain/risks.md ]'
  check "upgrade applies the step" 'PB_FORMAT_OVERRIDE=2 PB_UPGRADES="$(pwd)/up" b upgrade | grep -q "upgraded to format 2" && [ -f .brain/risks.md ] && grep -qx "format: 2" .brain/MAP.md'
  check "MAP.md backed up first" 'ls .brain/archive/backups/MAP.md.*.bak >/dev/null 2>&1 && grep -qx "format: 1" .brain/archive/backups/MAP.md.*.bak'
  check "content untouched" 'cmp -s charter.before .brain/charter.md'
  check "the upgrade is logged" 'grep -q "upgrade: brain format 1 → 2" .brain/log/$(date +%Y-%m-%d).md'
  check "an older plugin refuses a newer brain" '! b upgrade >/dev/null && b upgrade | grep -q "REFUSED"'
  check "the start summary says to update the plugin" 'hk session-start up222222 startup | grep -q "newer than this plugin"'
  check "a missing step is an error, nothing changed" 'PB_FORMAT_OVERRIDE=3 PB_UPGRADES="$(pwd)/up" b upgrade 2>&1 | grep -q "missing upgrade step" && grep -qx "format: 2" .brain/MAP.md'
}

t_sessionstatus() {
  brain4
  hk session-start aaaa1111 startup >/dev/null
  check "mark handed off" 'b session-status handed-off --session aaaa1111 >/dev/null && grep -q "^status: handed-off" .brain/sessions/aaaa1111.md'
  check "a handed-off session is not listed as live" '! hk session-start bbbb2222 startup | grep -q "s:aaaa1111 ·"'
  check "session end keeps the handed-off status" 'echo hi > q.txt; hp aaaa1111 q.txt >/dev/null; b session-status handed-off --session aaaa1111 >/dev/null; hk session-end aaaa1111 other >/dev/null; grep -q "^status: handed-off" .brain/sessions/aaaa1111.md'
  hk session-start cccc3333 startup >/dev/null; hp cccc3333 q.txt >/dev/null; b claim "the S31 question" --session cccc3333 >/dev/null
  check "closing a chat releases its claims and logs it" 'hk session-end cccc3333 other >/dev/null; ! grep -q "s:cccc3333" .brain/NOW.md && grep -q "Session closed: released 1 claim" .brain/log/$(date +%Y-%m-%d).md'
  check "bad state rejected" '! b session-status sleeping --session aaaa1111 2>/dev/null'
}

t_skills() {
  for s in init protocol catchup handoff tidy capture; do
    f="$ROOT/skills/$s/SKILL.md"
    check "$s: frontmatter with name and description" '[ "$(head -n 1 "$f")" = "---" ] && grep -q "^name: $s\$" "$f" && grep -q "^description: ." "$f"'
    check "$s: helper path points at brain.sh" 'grep -q "\${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" "$f"'
  done
  check "protocol is model-only; init, handoff, tidy, capture are user-only" '(grep -q "^user-invocable: false" "$ROOT/skills/protocol/SKILL.md" && for s in init handoff tidy capture; do grep -q "^disable-model-invocation: true" "$ROOT/skills/$s/SKILL.md" || exit 1; done)'
  check "every brain.sh command a skill uses exists" '(for c in $(grep -ho "B [a-z-]*" "$ROOT"/skills/*/SKILL.md "$ROOT"/skills/init/reference/*.md | awk "{print \$2}" | sort -u); do case "$c" in in|is|and|or|below|to|log|a) continue;; esac; sh "$B" 2>&1 | grep -q "^  $c" || { echo "missing: $c" >&2; exit 1; }; done)'
  needs_perm() { for f in "$ROOT"/skills/*/SKILL.md; do grep -q '^```!' "$f" || continue; sed -n '1,/^---$/p' "$f" | grep -q '^allowed-tools: Bash(sh:\*)' || { echo "$f" >&2; return 1; }; done; }
  check "skills that run a command up front declare Bash permission for it" needs_perm
  check "dynamic context blocks call commands that exist" '(grep -h "brain.sh\" [a-z-]*" "$ROOT"/skills/*/SKILL.md | grep -o "brain.sh\" [a-z-]*" | awk "{print \$2}" | sort -u | while read -r c; do sh "$B" 2>&1 | grep -q "^  $c" || exit 1; done)'
}

# --- M5: concurrency, split, sizes ----------------------------------------------------------------

# Two sessions working at the same moment: logs, captures, claims and digests, 25 rounds each.
t_concurrent() {
  b scaffold . --name Busy --mode private >/dev/null
  hk session-start aaaa1111 startup >/dev/null; hk session-start bbbb2222 startup >/dev/null
  worker() {   # worker <session> <letter>
    i=0
    while [ $i -lt 25 ]; do
      printf 'Call %s%s\n\n<pasted_content id="x">\nAnna Berg: round %s%s, we ship the importer on Friday if the tests pass tonight.\nBen Ode: agreed, and we freeze the branch on Thursday so there is time to review.\nAnna Berg: decision: freeze Thursday noon.\n</pasted_content>\n' \
        "$2" $i "$2" $i > "p-$2-$i.txt"
      hp "$1" "p-$2-$i.txt" > "out-$2-$i.txt"
      printf '%s%s line one\n%s%s line two\n' "$2" $i "$2" $i | b log --type status --session "$1" >/dev/null
      b claim "item-$2-$i.md" --hours 1 --session "$1" >/dev/null
      i=$((i + 1))
    done
  }
  worker aaaa1111 A & worker bbbb2222 B & wait
  f=.brain/log/$(date +%Y-%m-%d).md
  check "all 100 log entries are there (50 status, 50 capture)" '[ "$(grep -c "· status\$" "$f")" = 50 ] && [ "$(grep -c "· capture · inbox\$" "$f")" = 50 ]'
  check "no log entry is interleaved with another" '[ "$(awk "/^### .*s:aaaa1111/{w=\"A\"} /^### .*s:bbbb2222/{w=\"B\"} /line (one|two)\$/ && substr(\$1,1,1)!=w {n++} END{print n+0}" "$f")" = 0 ]'
  check "all 50 pasted calls were saved" '[ "$(ls .brain/sources/inbox/*.md | wc -l | tr -d " ")" = 50 ]'
  check "every saved call is complete" '(for g in .brain/sources/inbox/*.md; do grep -q "decision: freeze Thursday noon" "$g" || exit 1; done)'
  check "all 50 claims are in NOW.md" '[ "$(grep -c "^- \[claim\] item-" .brain/NOW.md)" = 50 ]'
  check "NOW.md kept all its sections" '(for s in Status Focus Items Claims Blockers "Open questions" Checkpoints Freshness; do grep -q "^## $s" .brain/NOW.md || exit 1; done)'
  check "each session saw the other in its digests" 'cat out-A-*.txt | grep -q "s:bbbb2222" && cat out-B-*.txt | grep -q "s:aaaa1111"'
  check "no session saw its own entries in a digest" '! cat out-A-*.txt | grep -q "s:aaaa1111 status" && ! cat out-B-*.txt | grep -q "s:bbbb2222 status"'
  check "no lock left behind" '[ -z "$(ls .brain/.locks 2>/dev/null)" ]'
  check "map-check passes" 'b claude-block >/dev/null && b map-check'
}

# A split done with the helper commands, the way the protocol skill describes it.
t_split() {
  b scaffold . --name Split --mode shared >/dev/null
  b add "charter.md|auto|file|why and scope|always" >/dev/null
  b add "decisions.md|demand|file|all decisions|before changing direction" >/dev/null
  echo "source" > .brain/sources/x.md
  { echo "# Decisions"; echo; for y in 2025 2026; do m=1; while [ $m -le 9 ]; do echo "- $y-0$m-01 · decision $y-$m · Ana · why · sources/x.md · [meeting]"; m=$((m + 1)); done; done; } > .brain/decisions.md
  echo "Past decisions: see decisions.md and .brain/decisions.md." >> .brain/charter.md
  b claude-block >/dev/null
  before=$(grep -c "^- 20" .brain/decisions.md)
  b claim "split decisions.md" --session aaaa1111 >/dev/null
  b add "decisions-2025.md|demand|file|decisions made in 2025|looking up an old decision" >/dev/null
  { echo "# Decisions 2025"; echo; grep "^- 2025" .brain/decisions.md; } > .brain/decisions-2025.md
  grep -v "^- 2025" .brain/decisions.md > d.tmp && mv d.tmp .brain/decisions.md
  echo "split decisions.md: 2025 entries → decisions-2025.md, because the file mixed two years" | b log --type structure --session aaaa1111 >/dev/null
  b release --all --session aaaa1111 >/dev/null
  check "no decision lost in the split" '[ $(( $(grep -c "^- 20" .brain/decisions.md) + $(grep -c "^- 20" .brain/decisions-2025.md) )) = "$before" ]'
  check "map-check and refs-check pass after the split" 'b map-check && [ -z "$(b refs-check)" ]'
  check "the split is logged as a structure change" 'grep -q "split decisions.md: 2025 entries → decisions-2025.md" .brain/log/$(date +%Y-%m-%d).md'
  b claim "retire decisions-2025.md" --session aaaa1111 >/dev/null
  b retire decisions-2025.md --session aaaa1111 --why "2025 is closed" >/dev/null
  check "retire after the split keeps map and references right" 'b map-check && [ -z "$(b refs-check)" ] && [ -f .brain/archive/decisions-2025.md ]'
}

# Sizes the owner cares about: the start injection and the per-prompt digest.
t_sizes() {
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  b scaffold . --name Northwind --mode private --adopt >/dev/null
  b add "charter.md|auto|file|why and scope|always" >/dev/null
  b add "glossary.md|auto|file|terms|always" >/dev/null
  i=0; while [ $i -lt 30 ]; do echo "- item $i · Dana · due 2026-10-15 · open · [meeting] (notes/todo.txt)"; i=$((i + 1)); done > items
  awk -v f=items '/^## Items/ { print; while ((getline l < f) > 0) print l; next } { print }' .brain/NOW.md > n && mv n .brain/NOW.md
  b claude-block >/dev/null
  hk session-start aaaa1111 startup >/dev/null
  i=0; while [ $i -lt 20 ]; do echo "entry $i with some words to make it realistic" | b log --type status --session bbbb2222 >/dev/null; i=$((i + 1)); done
  s=$(hk session-start cccc3333 startup | wc -c | tr -d ' ')
  echo q > q.txt; d=$(hp aaaa1111 q.txt | wc -c | tr -d ' ')
  a=$(b budget | tail -n 1 | awk '{ print $1 }')
  echo "        start injection: $s chars (~$((s / 4)) tokens); digest after 20 entries: $d chars; auto tier: ~$a tokens"
  check "start injection within ~2k tokens" '[ "$s" -le 8000 ]'
  check "per-prompt digest stays a few lines (under 1,500 chars)" '[ "$d" -le 1500 ]'
  check "auto tier within ~3k tokens" '[ "$a" -le 3000 ]'
}

# How many programs a hook starts. Each costs ~1 ms on macOS/Linux but 15-30 ms in Git Bash, so
# this is the number that decides speed on Windows. Wrappers in front of PATH count every start.
t_procs() {
  bin="$W/countbin"; mkdir -p "$bin"; CNT="$W/count"
  for c in awk sed grep find date cat rm mv wc tr mkdir cut sort head tail cp cmp base64 git touch ls dirname basename mktemp printf; do
    real=$(command -v "$c" 2>/dev/null) || continue
    case "$real" in /*) ;; *) continue ;; esac     # shell built-ins are free
    printf '#!/bin/sh\necho %s >> "%s"\nexec %s "$@"\n' "$c" "$CNT" "$real" > "$bin/$c"; chmod +x "$bin/$c"
  done
  counted() { : > "$CNT"; PATH="$bin:$PATH" "$@" >/dev/null 2>&1; wc -l < "$CNT" | tr -d ' '; }
  b scaffold . --name Procs --mode private >/dev/null
  hk session-start aaaa1111 startup >/dev/null; hk session-start bbbb2222 startup >/dev/null
  echo "what next?" > q.txt
  hp aaaa1111 q.txt >/dev/null
  mkdir -p "$W/procs-none"
  n0=$(cd "$W/procs-none" && CLAUDE_PROJECT_DIR="$W/procs-none" counted sh -c "printf '{}' | sh '$H' prompt")
  n1=$(CLAUDE_PROJECT_DIR=$(pwd) counted sh -c "LC_ALL=C awk -v sid=aaaa1111 -v cwd=\"$(pwd)\" 'END{printf \"{\\\"session_id\\\":\\\"%s\\\",\\\"cwd\\\":\\\"%s\\\",\\\"prompt\\\":\\\"what next?\\\"}\", sid, cwd}' /dev/null | sh '$H' prompt")
  echo "entry" | b log --type status --session bbbb2222 >/dev/null
  n2=$(CLAUDE_PROJECT_DIR=$(pwd) counted sh -c "printf '{\"session_id\":\"aaaa1111\",\"cwd\":\"%s\",\"prompt\":\"hi\"}' \"$(pwd)\" | sh '$H' prompt")
  n3=$(CLAUDE_PROJECT_DIR=$(pwd) counted sh -c "printf '{\"session_id\":\"cccc3333\",\"cwd\":\"%s\",\"source\":\"startup\"}' \"$(pwd)\" | sh '$H' session-start")
  echo "        programs started: no brain $n0; plain prompt $((n1 - 1)); prompt + digest $n2; session start $n3"
  check "no brain: the prompt hook starts no programs" '[ "$n0" -eq 0 ]'
  check "plain prompt: at most 2 programs" '[ $((n1 - 1)) -le 2 ]'
  check "prompt with a digest: at most 5 programs" '[ "$n2" -le 5 ]'
  check "session start: at most 20 programs" '[ "$n3" -le 20 ]'
}

for t in json scaffold add mapcheck claudeblock githide log detect adopt skill \
         hookquiet hookstart hookbudget hookdrift hookspeed hooksjson \
         detector redact capture digest images attach phantom promptspeed \
         claims move retire retier refs capturecmd catchup tidy upgrade sessionstatus skills \
         concurrent split sizes procs; do run "$t"; done

PASS=$(grep -c '^ok$' "$W/.results" 2>/dev/null || true); FAIL=$(grep -c '^FAIL' "$W/.results" 2>/dev/null || true)
echo
echo "passed: ${PASS:-0}  failed: ${FAIL:-0}"
[ "${FAIL:-0}" -gt 0 ] && grep '^FAIL' "$W/.results" | sed 's/^/  /'
rm -rf "$W"
[ "${FAIL:-0}" -eq 0 ]

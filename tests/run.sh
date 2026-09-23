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
  touch -t 202001010000 .brain/sessions/abcdef12.seen .brain/sessions/abcdef12.md
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
  sh "$ROOT/tests/fixtures/make-adopt-ws.sh" ws >/dev/null; cd ws
  b scaffold . --name NW --mode private --adopt >/dev/null
  i=0; while [ $i -lt 30 ]; do echo "entry $i" | b log --type status --session s$i >/dev/null; i=$((i+1)); done
  i=0; while [ $i -lt 6 ]; do hk session-start "sess$i" startup >/dev/null; i=$((i+1)); done
  t0=$(ms); i=0; while [ $i -lt 5 ]; do hk session-start speed123 startup >/dev/null; i=$((i+1)); done; t1=$(ms)
  avg=$(( (t1 - t0) / 5 ))
  echo "        session-start average: ${avg} ms"
  check "session-start under 1000 ms on average" '[ "$avg" -lt 1000 ]'
  cd "$W" && mkdir -p quiet && cd quiet
  t0=$(ms); i=0; while [ $i -lt 5 ]; do hk session-start q startup >/dev/null; i=$((i+1)); done; t1=$(ms)
  avg=$(( (t1 - t0) / 5 )); echo "        no-brain exit average: ${avg} ms"
  check "no-brain exit under 150 ms on average" '[ "$avg" -lt 150 ]'
}

t_hooksjson() {
  j="$ROOT/hooks/hooks.json"
  check "hooks.json exists and names both events" 'grep -q "\"SessionStart\"" "$j" && grep -q "\"SessionEnd\"" "$j"'
  check "every hook command points at an existing script" 'for s in $(grep -o "scripts/[a-z.-]*\.sh" "$j" | sort -u); do [ -f "$ROOT/$s" ] || exit 1; done'
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
  check "prompts are counted in the session file" 'grep -q "^prompts: 4" .brain/sessions/aaaaaaaa.md'
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

for t in json scaffold add mapcheck claudeblock githide log detect adopt skill \
         hookquiet hookstart hookbudget hookdrift hookspeed hooksjson \
         detector redact capture digest images attach phantom promptspeed; do run "$t"; done

PASS=$(grep -c '^ok$' "$W/.results" 2>/dev/null || true); FAIL=$(grep -c '^FAIL' "$W/.results" 2>/dev/null || true)
echo
echo "passed: ${PASS:-0}  failed: ${FAIL:-0}"
[ "${FAIL:-0}" -gt 0 ] && grep '^FAIL' "$W/.results" | sed 's/^/  /'
rm -rf "$W"
[ "${FAIL:-0}" -eq 0 ]

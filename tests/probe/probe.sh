#!/bin/sh
# Probe hook (developer tool, not active): records what Claude Code passes to hooks.
# To use: wire it into hooks/hooks.json for each event, open a session under ~/pb-test, then
# read ~/pb-test/.probe/. Re-run it after a Claude Code upgrade to check the hook inputs.
# Records only inside ~/pb-test or a scratchpad folder, into ~/pb-test/.probe/.
ev=${1:-unknown}
in=$(cat)
case "$PWD" in "$HOME"/pb-test*|*/scratchpad/*) ;; *) exit 0 ;; esac
d="$HOME/pb-test/.probe"; mkdir -p "$d"
f="$d/$(date +%Y%m%d-%H%M%S)-$$-$ev.txt"
{
  echo "event: $ev"; echo "time: $(date +%Y-%m-%dT%H:%M:%S%z)"; echo "pwd: $PWD"; echo "shell: $0 ($(ps -p $$ -o comm= 2>/dev/null))"
  echo "uname: $(uname -a)"
  echo "--- env (CLAUDE*, PB*)"; env | grep -E '^(CLAUDE|PB_)' | sort
  echo "--- stdin (${#in} bytes)"; printf '%s\n' "$in"
} > "$f"
sid=$(printf '%s' "$in" | sed -n 's/.*"session_id" *: *"\([^"]*\)".*/\1/p' | head -n 1)
tp=$(printf '%s' "$in" | sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p' | head -n 1)
if [ "$ev" = UserPromptSubmit ]; then
  {
    echo "--- transcript at hook time"
    if [ -f "$tp" ]; then
      echo "lines: $(wc -l < "$tp")"
      echo "last line types:"; tail -n 5 "$tp" | grep -o '"type":"[a-z_-]*"' | head -n 12 | tr '\n' ' '; echo
      echo "image/document blocks in last 5 lines: $(tail -n 5 "$tp" | grep -o '"type":"\(image\|document\)"' | grep -c .)"
    else echo "transcript file missing: $tp"; fi
    echo "--- session images dirs"
    ls -la /private/tmp/claude-*/*/"$sid"/images /tmp/claude-*/*/"$sid"/images 2>/dev/null
    ls -d "${TMPDIR:-/tmp}"/claude-*/*/"$sid" 2>/dev/null
    echo "--- paste cache (newest 3)"; ls -t "$HOME/.claude/paste-cache" 2>/dev/null | head -n 3
  } >> "$f"
  # Check again after the hook returns, when the prompt may have been written.
  ( sleep 3; { echo "--- transcript 3s later"; [ -f "$tp" ] && { echo "lines: $(wc -l < "$tp")"; echo "image/document blocks in last 5 lines: $(tail -n 5 "$tp" | grep -o '"type":"\(image\|document\)"' | grep -c .)"; }; } >> "$f" ) >/dev/null 2>&1 &
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"PROBE-UPS-CONTEXT: if you can read this line, say PROBE-UPS-SEEN."}}\n'
elif [ "$ev" = SessionStart ]; then
  [ -n "${CLAUDE_ENV_FILE:-}" ] && echo "export PB_PROBE_SESSION=$sid" >> "$CLAUDE_ENV_FILE"
  echo "PROBE-SESSIONSTART-CONTEXT: if you can read this line, say PROBE-START-SEEN."
fi
exit 0

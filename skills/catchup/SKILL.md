---
name: catchup
description: Fully re-sync a long-running session with the project brain. Shows everything other sessions logged since this session started, unfiled captures, claims, live sessions and repo changes, then summarizes what matters now.
argument-hint: "[--since YYYY-MM-DD]"
allowed-tools: Bash(sh:*)
---

# /project-brain:catchup

Helper: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"` (`B`). This session: `${CLAUDE_SESSION_ID}`.

## What changed

```!
sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" catchup --session "${CLAUDE_SESSION_ID}" $ARGUMENTS 2>&1 || echo "catchup failed"
```

(Your digest marker has moved to now: the per-prompt digest will not repeat these entries.)

## Then

1. Read `.brain/NOW.md` in full. Open any brain file an entry above points to if it affects the
   work this session is doing.
2. Captures still in `sources/inbox/`: file the ones this session saved, and the ones whose
   session has ended (see `.brain/sessions/`), following the project-brain protocol skill. Leave
   the ones a live session is still filing.
3. Structure changes above (`structure` entries): note new paths; do not use old ones.
4. Repos that changed: look at the new commits if they touch this session's work, then update
   that repo's Freshness line in NOW.md.
5. Tell the owner, in at most 12 short lines: what changed that matters for this session's work,
   decisions and dates that moved, new blockers or conflicts, and what you will do next. Skip
   anything that does not affect them.

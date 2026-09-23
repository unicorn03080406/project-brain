---
name: handoff
description: Close this session cleanly. Files anything still in the inbox, brings NOW.md up to date, writes this session's handoff, releases its claims and logs it, so the next session starts from an accurate brain.
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

# /project-brain:handoff

Helper: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"` (`B`). This session: `${CLAUDE_SESSION_ID}`
(its file is `.brain/sessions/<first 8 characters>.md`).

## Where things stand

```!
sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" claims 2>&1; ls "$(sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" find 2>/dev/null)/sources/inbox" 2>/dev/null | sed 's/^/inbox: /'
```

## Steps

1. **File what this session captured** that is still in `sources/inbox/` (the file names end with
   this session's id), following the project-brain protocol skill.
2. **NOW.md**, one section at a time, only what this session changed or learned:
   Focus, Items (status, owner, due date), Blockers, Open questions, Checkpoints, Freshness (repos
   you looked at). Label and source every fact. Remove items that are done only if they are
   recorded elsewhere (log or decisions); otherwise mark them done.
3. **Decisions** made in this session that are not yet in decisions.md: add them (append-only).
4. **Your session file** (`.brain/sessions/<id>.md`), yours alone:
   - `## Goal`: one line on what this session was for.
   - `## Handoff`: what was done (with paths), what is half-done and exactly where it stands,
     what the next session should do first, open threads and who is waiting on what.
     Write it for someone with none of this session's context.
5. **Release claims**: `B release --all --session ${CLAUDE_SESSION_ID}`
6. **Log it**: `echo "<3 lines: done, open, next>" | B log --type handoff --session ${CLAUDE_SESSION_ID}`
7. **Mark the session**: `B session-status handed-off --session ${CLAUDE_SESSION_ID}`
8. Run `B map-check`. Then tell the owner in a few lines: what is recorded, what is open, and
   what the next session will see first.

---
name: capture
description: Manually save material into the project brain and file it - a document or image from disk, a folder of files, or text - when it was not pasted or attached in chat. Pasted and attached material is captured automatically; use this for everything else.
argument-hint: "<file, folder or text>"
disable-model-invocation: true
---

# /project-brain:capture

Helper: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"` (`B`). This session: `${CLAUDE_SESSION_ID}`.
What to capture: `$ARGUMENTS`

1. **Save it** to `sources/inbox/` (secrets are removed from text files; identical files are
   never stored twice):
   - a file: `B capture "<path>" --session ${CLAUDE_SESSION_ID}`
   - a folder: run it for each file that is project material (ask first if there are more than 10)
   - text: `echo "<text>" | B capture --kind note --session ${CLAUDE_SESSION_ID}`
   - nothing given: ask the owner what to capture.
   The workspace's own files are never moved or changed: capture copies them. If the owner wants
   a workspace file *linked* rather than copied (it will keep changing), use
   `B add "<path>|demand|ext|<what it holds>|<when to read it>"` instead.
2. **File it** following the project-brain protocol skill: move it to the right `sources/`
   folder, add an INDEX.md line (and a `.md` note for PDFs and images), update the brain files
   MAP.md names for its information, label and source every fact, log it.
3. Tell the owner in a few lines where it went and what changed in the brain. If `B capture`
   said credentials were removed, say so.

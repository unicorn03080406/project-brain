---
name: init
description: Set up the project brain for this workspace. NEW mode builds it from an intake (job post, proposal, contract, kickoff notes). ADOPT mode builds it from a workspace already in progress without changing any of its files. On a workspace that already has a brain, it offers to refresh it from new material or upgrade its structure.
argument-hint: "[intake folder] [--yes]"
disable-model-invocation: true
---

# /project-brain:init

You are setting up the project brain: a shared knowledge base in `.brain/` that every
Claude Code session in this project reads and keeps current. Work carefully: the owner is a
contractor, the material is often a client's, and nothing may be lost, leaked or overwritten.

Helper script (use exactly this path; call it `B` in your head):
`sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"`

This session's id, for log entries: `${CLAUDE_SESSION_ID}`

Arguments: `$ARGUMENTS`
- A folder path means "the intake is here".
- `--yes` means unattended (used by tests): do not ask questions; take the recommended option
  at every step, write your assumptions into NOW.md under Open questions, and never touch
  `~/.claude/settings.json`.

## What is here now

```!
sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" detect "${CLAUDE_PROJECT_DIR}" 2>&1 || echo "detect failed"
```

## Hard rules

1. **Never overwrite a brain.** If `brain:` above is not `none`, go to "Existing brain" below.
2. **Never change the workspace's own files.** Nothing outside `.brain/` is created, edited,
   moved or deleted, except: the delimited block in `CLAUDE.md` (shared mode) or
   `CLAUDE.local.md` (private mode), and `.git/info/exclude` (private mode). `B claude-block`
   backs up the file before touching it.
3. **Label every fact** in brain files: `[verified]` (checked in code or data), `[meeting]`
   (someone said or wrote it), `[inferred]` (your reading). Cite the source path.
4. **No secrets.** If any input contains passwords, tokens, API keys or private keys, do not copy
   them. In copies under `sources/`, replace them with `[REDACTED: <kind>]`, and tell the owner.
5. **Paths:** brain files are always referred to with their explicit path. Search tools skip
   hidden folders, so pass `.brain/...` explicitly.
6. **Ask little.** Infer what you can. At most 3 questions about the project itself, in one go.
7. Every question that has a recommended answer: put it first and say "(recommended)". Use the
   AskUserQuestion tool when you have it.

## Step 1: pick the mode and confirm it

- `suggested-mode: NEW` (empty or near-empty workspace) → NEW.
- `suggested-mode: ADOPT` (existing repos, notes, docs) → ADOPT.
- Tell the owner which mode you picked and why in one line, and confirm. They may override.

## Step 2: private or shared (ask every time)

Ask, even in an obvious case, and explain in one short line each:
- **Private** (recommended when the workspace is a client's git repo): the brain and the file that
  loads it (`CLAUDE.local.md`) are kept out of git through `.git/info/exclude`, which is never
  committed or pushed. The client's `CLAUDE.md` and `.gitignore` are not touched.
- **Shared**: the block goes into `CLAUDE.md`; the brain may be committed. For the owner's own
  projects, or teams that want it.
If `git: not a repo` and `nested-repos: 0`, say that nothing needs hiding from git either way.
If the workspace is not a repo but contains repos, say the brain sits outside them, so it cannot
reach their remotes either way.

## Step 3: build

- NEW: follow `reference/new.md`.
- ADOPT: follow `reference/adopt.md`.

Both use the same helper commands:
- `B scaffold "<project dir>" --name "<Project name>" --mode private|shared [--adopt]`
- `B add "path|tier|kind|holds|read when"` for each file or folder you add (kind `file`, `dir` or
  `ext`). It updates MAP.md and seeds the file from the starter kit if one exists.
- Then write the content of each file with your normal file tools.
- `B claude-block` (shared → CLAUDE.md, private → CLAUDE.local.md), then `B git-hide` in private mode.
- `echo "<text>" | B log --type <type> --session ${CLAUDE_SESSION_ID}` for log entries.
  Types: `structure`, `capture`, `decision`, `status`, `handoff`. Add `--date YYYY-MM-DD` for
  backfilled entries (they are marked `backfilled`).
- `B map-check` and `B budget` at the end. Fix every ERROR before you finish.

Starter kits and seed files: `${CLAUDE_SKILL_DIR}/../../templates/kits.md`. They are
suggestions: fit the structure to this project.

## Step 4: machine setup (once per machine, never with --yes)

If `claude-credit-in-commits: default`, offer once: "Claude Code adds a 'Co-Authored-By: Claude'
line to commits and 'Generated with Claude Code' to pull requests. Turn that off for all your
projects?" If yes, add this to `~/.claude/settings.json` (merge with what is there; keep the rest
of the file exactly as it is; create the file if missing):
`"attribution": { "commit": "", "pr": "" }`

## Step 5: report

Finish with a short report in plain words:
- Mode, private or shared, and where the block went.
- The structure: each file and folder with one line on what it holds and its tier.
- What you could not fill (empty sections, unknown dates, missing people).
- Inferred facts waiting for confirmation, and any conflicts between sources (ADOPT).
- The output of `B map-check`, `B budget` and, in private mode, `B privacy-check`.
- Next steps: "Open NOW.md and confirm or correct it. Paste or attach anything new in any
  session; it is filed automatically."

## Existing brain

If a brain exists, never rebuild it. Read `reference/refresh.md` and offer:
1. **Refresh** from new material (a folder, new notes, new commits since the Freshness stamps).
2. **Upgrade** the structure if `brain-format` is lower than the plugin's format.
3. **Nothing**: just show `B map-check` and `B privacy-check`.

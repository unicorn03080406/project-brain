# Changelog

Versions follow `MAJOR.MINOR.PATCH`:
- **PATCH** (1.0.0 → 1.0.1): fixes only. Nothing to do.
- **MINOR** (1.0 → 1.1): new features; the brain format is unchanged. Nothing to do.
- **MAJOR** (1.x → 2.0): the brain format changes. The first chat in each project says so; run
  `/project-brain:init` there to upgrade (dry run first, backup, nothing lost).

Each entry names the brain format it writes.

## 1.0.2 (2026-09-23), brain format 1

- Fixed: a hang when the plugin runs in a process that ignores the broken-pipe signal (GitHub
  Actions macOS runners do this; some editors may too). Finding the brain can no longer loop.
- Faster saving of pasted material on Windows: about 14 programs instead of 30+ (redaction is one
  sed pass, log appends need no temp files).
- Redaction no longer depends on sed's case-insensitive flag.
- CI: a 20-minute limit per job, and a Linux run with the broken-pipe signal ignored.

## 1.0.1 (2026-09-23), brain format 1

- Faster hooks, above all on Windows, where Git Bash starts programs slowly. In a folder
  without a brain the prompt hook now starts no programs at all. A plain prompt starts one,
  a prompt with news from other chats about five, and a session start about 20.
  `tests/run.sh` counts them so this cannot quietly get worse.
- Session start no longer runs the full map check (`/project-brain:tidy` still does).

## 1.0.0 (2026-09-23), brain format 1

First release.

- `/project-brain:init`: NEW mode from an intake, ADOPT mode from a workspace in progress (dry
  run, links instead of copies, backfilled log, NOW.md marked inferred, conflicts listed). Private
  or shared mode. Offers to turn off the Claude credit in commits and pull requests.
- Hooks: a start summary for every chat (NOW.md, live chats, today's log, repo changes,
  warnings); pasted project material saved verbatim with credentials removed; pasted images,
  attached PDFs and files saved; a per-prompt digest of what other chats added; session
  registration; claims released when a chat closes.
- Skills: protocol (Claude's filing and structure rules), catchup, handoff, tidy, capture.
- Claims, and structure changes (add, split, merge, move, retire, retier) that keep MAP.md, the
  CLAUDE.md block and references in step.
- Runs on macOS, Linux and Windows (Git Bash). Needs only sh, awk and git.

# Changelog

Versions follow `MAJOR.MINOR.PATCH`:
- **PATCH** (1.0.0 → 1.0.1): fixes only. Nothing to do.
- **MINOR** (1.0 → 1.1): new features; the brain format is unchanged. Nothing to do.
- **MAJOR** (1.x → 2.0): the brain format changes. The first chat in each project says so; run
  `/project-brain:init` there to upgrade (dry run first, backup, nothing lost).

Each entry names the brain format it writes.

## 1.1.0 (2026-09-25), brain format 1

- New: your message voice. Messages Claude drafts for you to send (Slack replies, client updates,
  notes) follow your guide in `~/.project-brain/voice.md` (created on first use; edit it freely)
  and match the person you're writing to. Only the wording changes, never when a draft is offered.
  Brain projects only.
- Claude learns your voice from messages you wrote yourself: style notes in your personal file
  (style only, never project content), your messages verbatim in the project's
  `.brain/voice-examples.md`, and each person's style in `people.md`.
- `brain.sh voice`, `voice-example`, `voice-note`.

## 1.0.5 (2026-09-25), brain format 1

- Filing never replaces Claude's normal reply. When you paste a transcript, chat or email with no
  request, Claude answers as it would without the plugin (key points, decisions, action items,
  next steps) and mentions the filing in a line or two at the end.

## 1.0.4 (2026-09-25), brain format 1

- Protocol: attached PDFs and files are saved after the reply and announced at the next prompt;
  Claude no longer says they were not captured.

## 1.0.3 (2026-09-25), brain format 1

- Fixed on Windows: when the plugin was started with the Windows PATH order (from cmd, or by a
  program that does so), `find` and `sort` were Windows' own find.exe and sort.exe. Live
  sessions, duplicate detection, claims, structure changes and tidy then misbehaved. Under Git
  Bash the scripts now put Git's tools first. Nothing changes on macOS and Linux.

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

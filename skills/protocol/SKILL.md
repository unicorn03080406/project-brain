---
name: protocol
description: The project-brain rules for keeping a project's shared knowledge base (.brain/) current. Use it whenever you work in a project that has a .brain/ folder and the owner shares project information (pasted notes, emails, chats, files, screenshots, or a one-liner such as "Anna decided we drop the EU region"), when a [project-brain] notice says something was saved or other sessions added entries, when a task changes the project's state (a decision, a finished item, a new blocker, new commits looked at), before changing the brain's structure (add, split, merge, rename, retire, retier), and when claiming or releasing work.
user-invocable: false
---

# Project-brain protocol

The brain in `.brain/` is shared by every Claude Code session on this project, now and later.
Keep it true, small and easy to find things in. The owner is a contractor; the material is
often a client's. Nothing may be lost, leaked or overwritten.

Helper: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"` (called `B` below). Run it from
anywhere in the project. Your session id is in the start summary ("You are session s:…") and in
`$BRAIN_SESSION`; pass `--session <id>` when a command asks for it.

## 1. Where things live

`.brain/MAP.md` is the schema: every file and folder, what it holds, when to read it, its tier.
Read it before filing or restructuring. Never assume a file exists because another project has
it. Search tools skip hidden folders: always give `.brain/...` paths explicitly.

- `auto` files are already in your context (through CLAUDE.md). `inject` files are summarized
  by the hooks. `demand` files you read when the task needs them.
- `sources/` holds raw inputs, verbatim. Any subfolder by kind is fine (`meetings/`, `emails/`,
  `chats/`, `documents/`, `images/`, …): `sources/` is core, so its subfolders need no MAP row.
  `sources/INDEX.md` lists every source. `sources/not-context/` holds captures that turned out
  not to be project material.

## 2. Filing what was captured

A `[project-brain]` notice says what the hooks saved to `sources/inbox/`. Filing comes on top
of your normal work, never instead of it:
- The owner asked for something (a summary, next steps, a feature from a Slack thread): do that
  first, exactly as you would without a brain.
- The owner pasted material without saying what to do: respond as you would without a brain.
  For a transcript, notes, a chat or an email, lead with the key points, the decisions, the
  action items and your suggested next steps, or do the task it obviously calls for.
- Filing is extra work, not the answer. Mention it in one or two short lines at the end of your
  reply (where it went, what brain files changed), never as the body of the reply.
Then file it, in the same turn:

1. Read the saved file. Decide: project material, or not (code help, personal, another project)?
   Not project material → move it to `sources/not-context/`, log one line, done.
2. Move it from `sources/inbox/` to the right `sources/<kind>/` folder with a clear name
   (`meetings/2026-09-24-checkin.md`). Never change its text.
3. Add one line to `sources/INDEX.md`:
   `- <date of the content> · <kind> · sources/<path> · <one-line summary> · <topics>`
4. Images and PDFs: write `<file>.md` next to them: what it is, the key facts (with page
   numbers), and which brain files you filed them into. Describe images in words; that note is
   what future sessions search.
5. Update the brain files MAP.md names for each kind of information in it (decisions, people,
   dates, items, terms, findings…). Each fact gets a label and its source path, for example
   `Go-live 2026-10-15 [meeting] (sources/meetings/2026-09-10-status.md)`.
6. Log it: `echo "Filed <source> → <where>. Updated: <files>." | B log --type capture --tag filed --session <id>`
7. Conflicts: the newer source wins in the brain file; keep the old value visible
   ("was 2026-10-01 in the kickoff"); add the conflict to NOW.md Open questions.
8. Unsure where something belongs, or what it means? Ask one short question and leave the file
   in the inbox until you know.

Attached PDFs and files arrive later than pasted text and images: Claude Code only records them
after your reply, so the hooks save them then and announce them at the owner's next prompt
("Attachments from your previous message: …"). If the owner attached a file and no notice has
come yet, do not say it was not captured; say it will be saved after this reply and filed next
turn (or read it from the conversation now if the task needs it).

Material too short for the hook (a one-liner like "Kofi approved the budget"): save it yourself
with `echo "<the words, as said>" | B capture --kind note --session <id>`, then file it as above.
Files from disk: `B capture <path>`.

## 3. Labels, sources and secrets

- Every fact: `[verified]` (checked in code or data), `[meeting]` (someone said or wrote it) or
  `[inferred]` (your reading). Plus the source path. No unsourced facts.
- No secrets in the brain, ever: no passwords, keys, tokens, private keys. The hooks redact
  saved copies; you must not write secrets into brain files either. Note *where* access lives
  ("in 1Password, 'FreshLeaf sandbox'"), never the value. If you see one, tell the owner.

## 4. Writing to shared files (parallel sessions)

Several sessions may be writing at once:
- `log/` and `decisions.md` are append-only. Log only through `B log` (one locked append).
  Add a decision as one new line at the end; a reversal is a new line that points back.
- NOW.md: edit **one section at a time** with small exact replacements (the Edit tool). Never
  rewrite the file. If an edit fails because the file changed, re-read that section and retry.
- `sessions/`: write only your own file (`sessions/<your id>.md`). Set its Goal when you start
  real work.
- Never edit files in `sources/`. Never delete anything in the brain: retire it to `archive/`.
- After you look at a repo, update its Freshness line in NOW.md
  (`- repo <path> · last seen <short hash> · <date>`).

## 5. Claims

Before taking on work that another session could also pick up (a NOW.md item, a structure
change), claim it: `B claim "<what>" --session <id>` (default 4 hours; `--hours N`). If it is
refused, another session holds an overlapping claim: pick something else, or tell the owner.
Release when done: `B release "<what>"` or `B release --all`. Expired claims may be cleared by
anyone: `B claims --expire`.

## 6. Changing the structure

You may reshape the brain without asking when it makes it easier to use. The fixed core
(MAP.md, NOW.md, log/, sources/, sessions/, archive/) is off limits.

| Change | When | How |
|---|---|---|
| add | a recurring kind of information has no good home | `B add "path\|tier\|kind\|holds\|read when"`, then write it. No claim needed. |
| split | a file is too big (see `B tidy-report`) or mixes topics | claim; `B add` the new files; move the text section by section; if the old file is empty, `B retire` it, else keep it for what remains |
| merge | two files overlap | claim both; move the content into one; `B retire <other> --refs-to <kept>` |
| rename | a name misleads | claim; `B move <old> <new> --why "…"` |
| retire | a file is stale or unused | claim; `B retire <path> --why "…"` (moves to archive/) |
| retier | the auto tier is over ~3k tokens, or a file is needed more or less often | `B retier <path> auto\|inject\|demand` |

The helper keeps MAP.md, the CLAUDE.md block and references in step, and logs a `structure`
entry. For splits and merges also log what you did and why:
`echo "split decisions.md into decisions.md (2026) and archive … because …" | B log --type structure --session <id>`.
Then run `B map-check` and `B refs-check`, fix anything they report, and release the claim.
Other sessions see every structure change in their next digest.

## 7. When you finish a piece of work

Update the NOW.md sections it touched (item status, blockers, checkpoints), log a `status` or
`decision` entry, and release claims. At the end of a session the owner may run
`/project-brain:handoff`; if they close without it, the brain should already be current.

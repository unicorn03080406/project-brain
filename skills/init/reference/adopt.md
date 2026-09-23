# ADOPT mode: a workspace already in progress

The workspace's own files are **read-only** for the whole of this mode. You link to them from
MAP.md; you do not copy, move, rename or edit them.

## 0. Take a snapshot

Before anything else: `B snapshot "<project dir>" > "<scratch or temp file>"`. Keep it outside the
workspace (your scratchpad or the system temp folder). You compare against it at the end.

## 1. Inventory (read-only, in passes)

1. `B inventory "<project dir>"`: repos, commit history, instruction files, auto-memory, dated
   files, documents, and an estimate of how much text there is.
2. **Ask permission** before reading past session transcripts ("I found N past sessions for this
   folder. May I read them to recover decisions and context?"). With `--yes`: do not read them.
   If yes: `B transcripts "<project dir>"` lists them; `B transcript <id> --max 600` shows what
   the owner asked (add `--all` for replies). Read the newest and largest first.
3. Read in passes, within a budget. Pass 1 (always): READMEs, CLAUDE.md, AGENTS.md, auto-memory,
   the 10 newest dated notes, the docs folder index. Pass 2 (if the pass-1 total stayed under
   about 40k tokens): older notes, remaining docs, transcripts if allowed. If there is more than
   about 100k tokens of material, stop after pass 1 and tell the owner what you skipped; offer to
   continue in a later refresh.
4. Never read secrets files (`.env`, `*.pem`, `id_rsa*`, `credentials*`, `*secret*`). Mention that
   they exist only if it matters (for example "access lives in a .env file in carrier-sync").

## 2. Dry run: show before writing anything

Show the owner this, in plain words, and wait for their go-ahead (with --yes, continue):

```
Found
- <repos: name, commits, date range, main authors>
- <notes and docs: folders, counts, date range>
- <instruction files, auto-memory, transcripts read or not>

Proposed structure (tier · holds)
- <brain files you will create>

Will write into the brain
- <what goes into charter, people, decisions, NOW.md, ...>
- Log backfill: <n> entries from <meeting files>, <commit days>

Will only link (not copy)
- <workspace files that become ext rows in MAP.md>

Not sure about
- <facts you inferred, gaps>

Conflicts (newest source wins)
- <fact>: <old value> (<source, date>) → <new value> (<source, date>)

Outside the brain
- <CLAUDE.md block, with backup | CLAUDE.local.md + .git/info/exclude>
```

## 3. Build

1. `B scaffold "<project dir>" --name "<name>" --mode <private|shared> --adopt`
   (NOW.md starts labelled "inferred, not yet confirmed by the owner").
2. **Link, don't copy.** For each workspace file or folder the brain should point to:
   `B add "<path relative to the project>|demand|ext|<what it holds>|<when to read it>"`.
   Good candidates: READMEs, architecture docs, the meetings folder, a todo list, the existing
   CLAUDE.md. A whole folder can be one ext row.
3. Brain files (charter, people, decisions, systems, ...) are written **from** what you read,
   each fact labelled and citing its source path. Facts from auto-memory cite
   `auto-memory: <file>`; facts from transcripts cite `transcript <id> <date>`.
4. **Conflicts:** when two sources disagree, the newer one wins in the brain file. Keep the old
   value visible: `Go-live 2026-10-15 [meeting] (notes/meetings/2026-09-10-status.md; was
   2026-10-01 in the 2026-07-14 kickoff)`. List every conflict in NOW.md under Open questions.
5. **Backfill the log** from dated material, oldest first, one entry each:
   - each dated meeting file: `echo "<2-4 line summary> (notes/meetings/<file>)" | B log --type meeting --date <date> --session <id>`
   - commits: one entry per repo per active day, summarising the subjects:
     `echo "carrier-sync: <subjects> (git log)" | B log --type status --tag repo --date <date> --session <id>`
   Backfilled entries are marked automatically. Keep each entry short.
6. **NOW.md, reconstructed:** Focus, Items (from todo lists, open threads, recent commits),
   Blockers, Open questions (gaps, conflicts, things to confirm), Checkpoints (future dates),
   Freshness (for each repo: `- repo <path> · last seen <short hash> · <date>`, from
   `git -C <repo> log -1 --format='%h %ad' --date=short`). Everything here is `[inferred]` unless
   a source states it.
7. Log: `echo "Brain created (ADOPT mode): <files>. Linked: <n> workspace paths. Backfilled: <n> entries." | B log --type structure --session <id>`
8. `B claude-block` (an existing CLAUDE.md is backed up to archive/backups/ and gets only the
   delimited block), then `B git-hide` if private.

## 4. Prove nothing changed

`B snapshot "<project dir>"` again and compare with the first snapshot (`diff`). The only allowed
difference is `CLAUDE.md` in shared mode, and only inside the project-brain block. Report the
result. If anything else changed, say so plainly and stop.

Then `B map-check`, `B budget`, and `B privacy-check` in private mode.

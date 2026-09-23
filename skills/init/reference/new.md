# NEW mode: a project that is just starting

## 1. Find and read the intake

- A folder given as an argument, else `sources/intake/` or `intake/` in the workspace, else ask
  the owner where the material is (with `--yes`: use whatever `detect` lists; if nothing, build
  the minimal structure and say so).
- Read everything in it: job post, proposal, contract or SOW, kickoff transcript, emails, notes.
  Read PDFs and images too.

## 2. Work out what you can

From the intake alone, draft: project name, client, why, scope in and out, deliverables with
dates, the owner's role, success criteria, terms (payment, confidentiality, data rules), people
and their roles, decisions already made, open questions, next checkpoints, project words.

Then ask the owner **only what you could not infer and that matters for the structure or the
first week of work**: at most 3 questions in one message. Typical: "Is Kofi the one who approves
deliverables?", "Is the 26 Nov demo a hard deadline?". Never ask what the intake already says.

## 3. Propose a structure

Start from the kit that fits (`templates/kits.md`): minimal, product, research, integration,
consulting, sales, or a mix. Then fit it:
- Drop files the intake gives no reason for.
- Add what this project clearly needs, in its own words (for example `experiments/` and
  `findings.md` for a study; `specs/` for a product build).
- Keep `auto` small: MAP.md, charter.md and at most one more short file (usually glossary.md).
  Everything else is `demand`.

Show it as a short list: `path · tier · what it holds`. Confirm with the owner (skip with --yes).

## 4. Write it

1. `B scaffold "<project dir>" --name "<name>" --mode <private|shared>`
2. Copy the intake files **verbatim** into `.brain/sources/intake/` (the originals stay
   where they are). If a file contains credentials, redact them in the copy only. Add one line
   per file to `.brain/sources/INDEX.md`:
   `- YYYY-MM-DD · kind · sources/intake/<file> · one-line summary · topics`
   For PDFs and images, also write `<file>.md` next to the copy: what it is, key facts with page
   numbers, and which brain files you filed them into.
3. `B add "..."` for each file or folder in the structure, then write their content. Every fact
   gets a label and a source, e.g. `Final report due 2026-12-18 [meeting] (sources/intake/02-contract-summary.md)`.
   - decisions.md: one line per decision found in the intake.
   - people.md: everyone named, with role and how they matter.
4. NOW.md: fill **Focus**, **Items** (owner, due date, status), **Open questions** (including
   what you could not fill), **Checkpoints** (every dated milestone). Edit section by section.
5. Log: `echo "Brain created (NEW mode, <kit>): <files>. Intake: <n> files in sources/intake/." | B log --type structure --session <id>`.
   Add one `decision` entry per decision found in the intake, with its source.
6. `B claude-block`, then `B git-hide` if private.
7. `B map-check` and `B budget`. Fix every ERROR.

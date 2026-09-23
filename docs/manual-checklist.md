# Manual checklist

Run these by hand before a release. Each milestone adds a section. Use scratch folders, never a
real client workspace. `PB` below is the path to your clone of this repo.

## Loading the plugin from this folder

- VS Code extension: type `/plugins` in the chat box. In **Marketplaces**, add the path to this
  repo. In **Plugins**, click **Install** on project-brain. Start a new chat to load it.
- Terminal CLI: `/plugin marketplace add <path to this repo>`, then
  `/plugin install project-brain@project-brain`, or `claude --plugin-dir "$PB"` for one session.
- Claude Code copies the plugin into its cache at install, by version. Hooks and the skills Claude
  can call read this folder live, but the slash commands you type come from the copy. After
  changing skills: raise "version" in .claude-plugin/plugin.json, then in /plugins refresh the
  marketplace and update the plugin (CLI: `claude plugin marketplace update project-brain` and
  `claude plugin update project-brain@project-brain`), then reload the VS Code window.
- The steps below say `claude --plugin-dir "$PB"`; in VS Code, open the folder instead and start
  a new Claude Code chat there. Run the `sh ...` lines in VS Code's terminal.
- VS Code: check that typing `/` lists `/project-brain:init`, and that init's reply starts from
  the "What is here now" facts (project, brain, git, suggested mode).

## 0. Automated tests (all platforms)

```sh
sh tests/run.sh               # macOS, Linux, WSL
bash tests/run.sh             # Windows: in Git Bash
PB_SH=dash dash tests/run.sh  # stricter shell, where dash exists
```
Expect `failed: 0`.

## M1. init

### NEW mode, research project
```sh
mkdir -p ~/pb-test/research && cp -R "$PB/tests/fixtures/intake-research" ~/pb-test/research/intake
cd ~/pb-test/research && claude --plugin-dir "$PB"
```
In Claude Code: `/project-brain:init`
- [ ] It says NEW mode and asks you to confirm.
- [ ] It asks private or shared, even though this folder is not a git repo, and says nothing needs hiding.
- [ ] It asks at most 3 questions about the project, and none the intake already answers.
- [ ] It proposes a research-shaped structure (for example experiments/, findings.md) and waits for your OK.
- [ ] `.brain/sources/intake/` holds verbatim copies; `intake/` is unchanged.
- [ ] charter.md has the dates D1–D3 and the 2 cm / 95% threshold, labelled and with sources.
- [ ] decisions.md has "exclude S17 and S22" with who, when and the transcript path.
- [ ] NOW.md lists the checkpoints and what it could not fill.
- [ ] The final report shows `map ok` and the auto tier under budget.
- [ ] It offers once to turn off the Claude credit in commits. Say no for this test, then check
      `~/.claude/settings.json` is unchanged.

### NEW mode, product build
Same steps with `tests/fixtures/intake-product` in `~/pb-test/product`.
- [ ] The structure differs from the research one (for example systems.md, specs/, roadmap.md).
- [ ] The Expo and FreshLeaf decisions are in decisions.md; "per household or per user" is an open question.
- [ ] glossary.md has plan / pantry / staple.

### ADOPT mode
```sh
sh "$PB/tests/fixtures/make-adopt-ws.sh" ~/pb-test/northwind
sh "$PB/scripts/brain.sh" snapshot ~/pb-test/northwind > ~/pb-test/northwind.before
cd ~/pb-test/northwind && claude --plugin-dir "$PB"
```
In Claude Code: `/project-brain:init`
- [ ] It says ADOPT mode. It shows the dry run (found / proposed / import / link only / unsure /
      conflicts) and writes nothing until you agree.
- [ ] The dry run lists the go-live conflict: 2026-10-01 (kickoff) → 2026-10-15 (status call).
- [ ] Pick **shared**: CLAUDE.md keeps its 5 original lines at the top and gains one delimited
      block; the backup is in `.brain/archive/backups/`.
- [ ] MAP.md has `@ext:` rows for the READMEs, notes/meetings/ and docs/architecture.md.
- [ ] `log/2026-07-14.md`, `log/2026-08-02.md`, `log/2026-09-10.md` exist, entries marked `backfilled`.
- [ ] NOW.md says "inferred" and has Freshness lines with a commit hash per repo.
- [ ] Nothing else changed:
      `sh "$PB/scripts/brain.sh" snapshot ~/pb-test/northwind | diff ~/pb-test/northwind.before -`
      shows only `./CLAUDE.md`.

### ADOPT, private mode inside a git repo
```sh
mkdir ~/pb-test/client && cd ~/pb-test/client && git init && echo "# client" > README.md && git add . && git commit -m init
claude --plugin-dir "$PB"     # then /project-brain:init, pick private
```
- [ ] `git status` is clean afterwards. No CLAUDE.md is created; CLAUDE.local.md exists.
- [ ] `.git/info/exclude` has the project-brain lines; `.gitignore` does not exist or is unchanged.
- [ ] A new session in this folder loads the brain (ask "what is this project?").

### Re-running init
- [ ] In any folder above, run `/project-brain:init` again: it does not rebuild. It offers
      refresh, upgrade (says "up to date") or nothing.

### Windows (Git Bash installed)
- [ ] `bash tests/run.sh` passes in Git Bash.
- [ ] The NEW research test above works from a Claude Code session on Windows.

## M2. Session start

Use the brains from the M1 tests (`~/pb-test/northwind`, `~/pb-test/research`).

- [ ] Open `~/pb-test/northwind` and start a new chat. Ask: "What do you know about this project
      so far? Don't read any files." It should answer from the start summary: go-live 2026-10-15,
      open items, and that NOW.md is still marked inferred.
- [ ] `.brain/sessions/` has a file for this chat with `status: live`.
- [ ] Start a **second** chat in the same folder (keep the first open). Ask: "Are other sessions
      live on this project?" It should name the first chat's `s:` id.
- [ ] Ask the second chat: "Run `echo $BRAIN_SESSION`." It prints its own short id.
- [ ] Close a chat (or quit VS Code): its session file changes to `status: ended ...`.
- [ ] Add a commit in `carrier-sync` (any small change), start a new chat: the summary reports
      "carrier-sync: 1 new commit(s) since 802ad20".
- [ ] Type `/compact` in a long chat: afterwards it still knows the project (the summary is
      injected again after compaction).
- [ ] Open a folder with no `.brain/` (any other project): nothing about the project brain
      appears, and nothing is created there.
- [ ] Windows: the same first two checks in a Claude Code session on Windows with Git Bash.

## M3. Capture and spread

Use `~/pb-test/research`. Keep two chats open side by side: **A** and **B**.

- [ ] In A, paste project notes (for example the text of `tests/detector/context/teams-chat.txt`,
      which belongs to the research project; product notes would rightly go to not-context)
      with a one-line request. Before or with its answer, A says the notes were saved; afterwards
      they sit in a `sources/` subfolder, with a line in `sources/INDEX.md`, a log entry, and the
      decisions in decisions.md.
- [ ] In B, send any short prompt ("what's new?"). B's answer mentions what A added (the digest),
      with log paths.
- [ ] Send B the same prompt again: nothing is repeated.
- [ ] In A, paste a stack trace or a code block: nothing is saved, nothing is said about it.
- [ ] In A, paste a screenshot with a short line: the image is copied to `sources/inbox/` (then filed).
- [ ] In A, attach `~/pb-test/probe-memo.pdf`: after A's reply the PDF is in `sources/inbox/`; on
      A's next prompt, A is told and files it (with a `<file>.md` note).
- [ ] Attach the same PDF again: no second copy; A is told where the existing one is.
- [ ] Paste notes containing `password: hunter2`: the saved copy says `[REDACTED: secret]` and the
      session tells you credentials were removed.
- [ ] Close a chat that never got a prompt: no file for it stays in `.brain/sessions/`.
- [ ] In a folder with no `.brain/`, paste meeting notes: nothing is saved anywhere.
- [ ] Windows: the first two checks in a Claude Code session on Windows with Git Bash.

## M4. Skills

Use `~/pb-test/research` (or `~/pb-test/northwind`).

- [ ] **Protocol, one-liner**: tell a chat "Imani decided the briefing is slides, 20 min + 10 min Q&A".
      It records it without being asked: a verbatim note in `sources/`, a line in decisions.md,
      a log entry.
- [ ] **Claims**: in chat A say "claim the S31 open question". In chat B ask it to take the same
      item: B sees A's claim (NOW.md Claims) and does not take it.
- [ ] **/project-brain:catchup** in a chat that has been open a while: a short summary of what
      other chats did; the next prompt's digest does not repeat it.
- [ ] **/project-brain:tidy**: a report with proposals; nothing changes until you choose.
      Make decisions.md very long first (paste a lot into it) to see a split proposed.
- [ ] Accept a split or a retire: afterwards `sh "$PB/scripts/brain.sh" map-check` and
      `refs-check` are clean, the old file is in `archive/`, and the log has a `structure` entry.
- [ ] **/project-brain:capture ~/pb-test/probe-memo.pdf**: says it is already in the brain (same bytes).
      Capture any other file: it lands in `sources/`, indexed, with a note.
- [ ] **/project-brain:handoff**: the session file gets a Goal and a Handoff a stranger could follow;
      claims released; status `handed-off` (it stays so after the chat closes).
- [ ] The next new chat's start summary reflects the handoff (NOW.md, today's log).
- [ ] Close a chat that holds a claim, without a handoff: the claim is released and logged.

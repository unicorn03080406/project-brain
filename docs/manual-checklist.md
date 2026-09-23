# Manual checklist

Run these by hand before a release. Each milestone adds a section. Use scratch folders, never a
real client workspace. `PB` below is the path to your clone of this repo.

## Loading the plugin from this folder

- VS Code extension: type `/plugins` in the chat box. In **Marketplaces**, add the path to this
  repo. In **Plugins**, click **Install** on project-brain. Start a new chat to load it.
- Terminal CLI: `/plugin marketplace add <path to this repo>`, then
  `/plugin install project-brain@project-brain`, or `claude --plugin-dir "$PB"` for one session.
- A folder marketplace is used in place, so edits to this repo apply from the next session.
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

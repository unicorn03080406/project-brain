# project-brain

A Claude Code plugin that gives each project a shared knowledge base in `.brain/`. Every chat on
the project, running now or started later, works from the same up-to-date picture: what the
project is, who is involved, what was decided, and what is happening now.

- **It builds itself.** `/project-brain:init` builds the brain from a project's first documents,
  or from a workspace that is already in progress.
- **It stays current.** Paste meeting notes, emails or chats, or attach a PDF or a screenshot,
  in any chat. It is saved and filed, and your other chats hear about it on their next prompt.
- **It fits each project.** The files are shaped to the project and change as it does.
- **It stays out of client repos.** In private mode, nothing reaches the client's git repository.

## Install (once per machine)

Needs Claude Code (VS Code extension or CLI) and git. On Windows, install
[Git for Windows](https://gitforwindows.org) first: the plugin's scripts run in Git Bash.

The repo is private, so the machine must be able to reach it with git. On Windows, Git for Windows
asks you to log in the first time. On macOS or Linux, run `gh auth login` once.

- **VS Code:** type `/plugins`. Under **Marketplaces**, add `unicorn03080406/project-brain`.
  Under **Plugins**, click **Install** on project-brain, then **Install for you**.
- **CLI:** `/plugin marketplace add unicorn03080406/project-brain`, then
  `/plugin install project-brain@project-brain`.

Then reload VS Code (Cmd/Ctrl+Shift+P → "Developer: Reload Window"), or restart the CLI.

## Start a new project

1. Create the project folder. Put what you have in `intake/`: job post, proposal, contract,
   kickoff notes. PDFs are fine.
2. Open the folder, start a chat, run `/project-brain:init`.
3. Answer a few questions, including private or shared (see Privacy below). Check the proposed
   structure, and it writes the brain. Then open `.brain/NOW.md` to see where things stand.

## Adopt a project already in progress

Open the workspace and run `/project-brain:init`. It reads the repos, notes, docs, your existing
`CLAUDE.md` and Claude's memory for the folder. It reads past chats only if you allow it. First
it shows you a dry run of what it found and what it will do.

Your files are never moved, changed or copied: the brain links to them. The log is rebuilt from
dated notes and commits. NOW.md is marked *inferred* until you confirm it.

## Day to day

Mostly nothing to do. Every chat starts with a short summary of the project. Paste or attach
project material anywhere and it is filed. Mention a decision in passing ("Anna approved the
budget") and it is recorded. Ask "what did we agree on X?" and the answer comes from the brain,
with its source.

| Command | When |
|---|---|
| `/project-brain:handoff` | Before closing a chat you worked in: updates NOW.md, releases claims, writes a handoff |
| `/project-brain:catchup` | A chat has been open for hours and should re-sync |
| `/project-brain:tidy` | Every week or two: finds big, stale or overlapping files and proposes fixes |
| `/project-brain:capture <file>` | Add a document from disk |
| `/project-brain:init` (again) | Refresh from new material, or upgrade after a plugin update |

Your part: confirm anything marked `[inferred]` when asked, and glance at `.brain/NOW.md` now and
then.

## Privacy

- **Private mode** (for client repos): the brain and the file that loads it (`CLAUDE.local.md`)
  are listed in `.git/info/exclude`, git's private ignore list, which is never committed or
  pushed. The client's `CLAUDE.md` and `.gitignore` are not touched. The start summary warns you
  if a brain file ever gets tracked, or if a commit you haven't pushed yet credits Claude.
- Init offers once to turn off Claude Code's "Co-Authored-By: Claude" line in commits and its
  "Generated with Claude Code" line in pull requests.
- Passwords, keys and tokens are removed from anything saved to the brain. They remain in the chat
  itself and in Claude Code's local chat history (`~/.claude/projects/`), which the plugin cannot
  change. Keep secrets in a password manager.

## Updating

When the plugin changes: in `/plugins`, refresh the marketplace and update project-brain (CLI:
`claude plugin marketplace update project-brain` and
`claude plugin update project-brain@project-brain`), then reload. Every project uses the new
version from its next chat. If a release changes the brain's format, the first chat in each
project says so; run `/project-brain:init` there to upgrade. You see a dry run first, and nothing
in the brain is lost. See [CHANGELOG.md](CHANGELOG.md).

## More

- [docs/manual-checklist.md](docs/manual-checklist.md): hands-on tests, including Windows
- [docs/development.md](docs/development.md): how the plugin works, tests, releasing a version

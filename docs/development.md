# Development

## Layout

```
.claude-plugin/plugin.json      name, version (the version drives updates)
.claude-plugin/marketplace.json this repo is its own marketplace (source "./")
hooks/hooks.json                SessionStart, UserPromptSubmit, Stop, SessionEnd → scripts/hook.sh
scripts/hook.sh                 the hooks: start summary, capture, digest, attachments, session end
scripts/brain.sh                helper CLI used by skills and hooks (run it with no arguments for help)
scripts/lib.sh                  shared shell functions (find the brain, parse MAP.md, locks)
scripts/detect.awk              capture detector: project material or not
scripts/redact.sh               removes credentials before anything is saved
scripts/json.awk, attach.awk    JSON and transcript reading without jq
scripts/upgrades/N.sh           brain format upgrade steps (none yet: format 1)
skills/<name>/SKILL.md          init, protocol, catchup, handoff, tidy, capture
templates/                      core files, starter files, kits.md
tests/run.sh                    fast suite, no Claude needed (CI runs it on 3 systems)
tests/e2e.sh                    real Claude Code sessions (slow, uses your account)
tests/detector/                 detector samples: context/ must be captured, plain/ must not
tests/fixtures/                 synthetic intakes and the in-progress workspace builder
tests/probe/probe.sh            developer tool: records what Claude Code passes to hooks
```

## Rules the code keeps

- POSIX `sh` + `awk` + `git` only. No jq, no Python, no Node. No regex intervals in awk (mawk).
  No `:` in file names (Windows). LF line endings (`.gitattributes`).
- A hook never blocks or clutters a chat: it exits 0, prints nothing without a `.brain/`, and
  writes its errors to `$CLAUDE_PLUGIN_DATA/project-brain-errors.log`.
- The UserPromptSubmit hook stays under 200 ms (currently ~25 ms plain, ~80 ms with a capture).
- Only synthetic, fictional data in this repo. Never real project material.
- The brain lives in `.brain/`, not `.claude/`: Claude Code refuses file edits under `.claude/`,
  whatever the permission rules say.

## Testing

```sh
sh tests/run.sh                  # fast suite; add a name to run one group: sh tests/run.sh claims
PB_SH=dash dash tests/run.sh     # the same under dash (Ubuntu's sh)
DEBUG=1 sh tests/run.sh capture  # show the error output of failing checks
CLAUDE_BIN=/path/to/claude sh tests/e2e.sh   # end-to-end, several minutes
```

When the detector gets something wrong in real use, add the (made-up equivalent) text to
`tests/detector/context/` or `plain/` and fix `detect.awk` until all samples pass.

## Releasing a version

1. Run both suites.
2. Raise `version` in `.claude-plugin/plugin.json` (see CHANGELOG.md for which number) and add a
   CHANGELOG entry. **Installed copies only update when the version changes.** Claude Code copies
   the plugin into its cache per version, and the slash commands come from that copy.
3. If the brain format changes: raise `PB_FORMAT` in `scripts/lib.sh`, add
   `scripts/upgrades/<new format>.sh` (its second line says what it does), describe it in
   `skills/init/reference/upgrades.md`, and make it a MAJOR version.
4. Commit, push, check CI. Machines pick it up with the plugin update in the README.

## Things that are easy to get wrong

- A SKILL.md with a ```` ```! ```` block must declare `allowed-tools: Bash(sh:*)`. Otherwise
  Claude Code silently skips the whole skill when Bash isn't pre-approved. `tests/run.sh`
  checks this.
- Hook input: use the `cwd` from the JSON, never `$PWD`. The hook's working folder follows the
  chat's shell, which may have moved into `.brain/`.
- Attachments: a pasted image is in the session's `images/` folder before the prompt hook runs.
  An attached PDF or file only appears in the transcript after it, so the Stop hook saves those.
- Re-run `tests/probe/probe.sh` (see its header) after a Claude Code upgrade, to check the hook
  inputs haven't changed.

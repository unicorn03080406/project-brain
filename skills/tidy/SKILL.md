---
name: tidy
description: Review the project brain's structure and health (oversized files, overlaps, stale or empty files, tier budget, unfiled captures, expired claims, broken references, privacy) and propose or apply fixes under the protocol's rules.
argument-hint: "[--apply]"
disable-model-invocation: true
allowed-tools: Bash(sh:*)
---

# /project-brain:tidy

Helper: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh"` (`B`). This session: `${CLAUDE_SESSION_ID}`.
Arguments: `$ARGUMENTS` (`--apply`: apply the safe fixes without asking; ask about the rest).

## Report

```!
sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" tidy-report 2>&1 || echo "tidy-report failed"
```

## Then

1. Read MAP.md and look at the files the report points to. The report is a starting point:
   judge overlaps and staleness by content, not only by the numbers.
2. Propose changes in plain words, grouped:
   - **Must fix**: map errors, broken references, privacy warnings, expired claims.
   - **Budget**: if the auto tier is over ~3k tokens, what to retier or shorten.
   - **Structure**: splits (big or mixed files), merges (overlaps), retires (stale, or still the
     empty starter after a week or more), renames, new homes for recurring information.
   - **Housekeeping**: captures left in the inbox, idle sessions still marked live.
   For each: what, why, and the old → new paths.
3. Ask the owner which to apply ("all", pick, or none). With `--apply`, apply "Must fix" and
   "Housekeeping" at once and ask only about Budget and Structure.
4. Apply under the protocol skill's rules: claim (`B claim "structure" --session ${CLAUDE_SESSION_ID}`
   for several changes at once), use `B add` / `B move` / `B retire` / `B retier`, move text
   section by section for splits and merges, never touch the fixed core, never delete (retire).
   Clear expired claims with `B claims --expire`.
5. Finish with `B map-check`, `B refs-check` and `B budget`, release the claim, and log one
   `structure` entry that sums up the tidy. Report what changed.

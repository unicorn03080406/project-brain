# Existing brain: refresh or upgrade

Never rebuild or overwrite. Every change follows the protocol's structure rules (claim first for
split, merge, rename or retire; update MAP.md and the CLAUDE block in the same step; log a
`structure` entry).

## Refresh from new material

1. Ask what is new, or look: a folder the owner names, files newer than the brain's last log
   entry, commits after each repo's Freshness stamp in NOW.md.
2. File each item as the protocol skill describes for captures: raw copy into `sources/` (for
   material handed to you) or an ext link (for workspace files), log entry, update the files
   MAP.md names for that kind of information.
3. Update the Freshness stamps.

## Upgrade the structure

1. Compare `brain-format` in MAP.md with the plugin's format (`B version`).
2. Same format: say the brain is up to date.
3. Lower format: apply each step in `upgrades.md` in order, starting from the brain's format.
   Show the dry run first, back up MAP.md to `archive/backups/`, then apply, then set
   `format:` in MAP.md, then `B claude-block` and `B map-check`.
4. Higher format than the plugin: the plugin is older than the brain. Do not write anything; ask
   the owner to update the plugin.

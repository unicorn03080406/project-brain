# Brain map: {{PROJECT}}

This file is the schema of this project's brain. It lists every file and folder in
`.brain/`, what goes in it, when to read it, and how it is loaded. Hooks and skills
read the block below to find things. Nothing else hard-codes paths.

Load tiers:
- `auto`: loaded in every session through CLAUDE.md (or CLAUDE.local.md). Small and stable. About 3k tokens in total.
- `inject`: summarized into the session by the hooks.
- `demand`: read or searched when needed. Always use the explicit path: search tools skip hidden folders.

Kinds: `core` (fixed, never removed or renamed), `file`, `dir`, `ext` (a workspace file the brain links to instead of copying; path is relative to the project folder).

Rules: update this map in the same step as any structural change. Retire to `archive/`, never delete.

```brain-map
format: 1
project: {{PROJECT}}
mode: {{MODE}}
created: {{DATE}}
plugin: {{VERSION}}

# path              | tier   | kind | holds                                                          | read when
MAP.md              | auto   | core | this schema                                                    | always loaded
NOW.md              | inject | core | focus, items, claims, blockers, open questions, checkpoints     | summary injected at start; read before planning work
log/                | inject | core | daily timeline, one stamped block per event, append-only        | new entries injected as a digest
sources/            | demand | core | raw inputs, verbatim, never edited; INDEX.md lists them all      | need the original wording, a file or an attachment
sessions/           | demand | core | one file per live session: goal, claims, marker, handoff         | catchup, handoff, checking who is doing what
archive/            | demand | core | retired files, moved here, never deleted                         | history only
```

## Notes

Conventions this project has adopted go here.

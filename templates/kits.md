# Starter kits

Kits are suggestions. Init mixes and trims them to fit the project, and the structure keeps
evolving after init. Seed files live in `templates/files/`. Folders start empty.

Every kit adds to the fixed core (MAP.md, NOW.md, log/, sources/, sessions/, archive/).
Keep the `auto` tier under about 3k tokens in total: usually MAP.md plus charter.md, maybe glossary.md.

## minimal: small or short projects
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| charter.md | auto | file | why, scope, deliverables, dates, my role, success criteria, terms | always loaded |
| people.md | demand | file | who is involved, their role, how they matter | someone is named or needs contacting |
| decisions.md | demand | file | append-only: date · decision · who · why · source | before changing direction; when asked what was agreed |

## product: building an app, service or feature
minimal, plus:
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| systems.md | demand | file | repos, services, environments, tools, where access lives | touching code, deploys or infra |
| glossary.md | auto | file | project terms and names | always loaded (keep short) |
| roadmap.md | demand | file | milestones, target dates, status | planning or reporting progress |
| specs/ | demand | dir | one file per feature or component spec | designing or building that feature |

## research: studies, experiments, analysis contracts
minimal, plus:
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| glossary.md | auto | file | terms, datasets, metrics and their exact meanings | always loaded (keep short) |
| experiments/ | demand | dir | one file per experiment: question, setup, data, result | planning, running or reviewing an experiment |
| findings.md | demand | file | what we now believe, with evidence and confidence | writing up results; before claiming a result |
| literature/ | demand | dir | notes on papers and prior work, one file each | citing or comparing with prior work |

## integration: connecting systems, APIs, data pipelines
minimal, plus:
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| systems.md | demand | file | the systems on each side, endpoints, environments, owners | touching any integration code or config |
| access.md | demand | file | where access lives and who grants it (never credentials) | blocked on access; onboarding |
| glossary.md | auto | file | field names, entity names, mappings | always loaded (keep short) |

## consulting: advice, audits, workshops, reports
minimal, plus:
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| stakeholders.md | demand | file | who cares about what, and how to keep them informed | preparing a meeting or a report |
| meetings/ | demand | dir | one summary per meeting, linking its source | preparing a follow-up; checking who said what |
| deliverables/ | demand | dir | one file per deliverable: status, outline, feedback | working on a deliverable |

## sales: pre-sales, pipeline, account work
minimal, plus:
| path | tier | kind | holds | read when |
|---|---|---|---|---|
| customers/ | demand | dir | one file per account: context, contacts, history | before any contact with that account |
| pipeline.md | demand | file | accounts by stage, next step, owner, date | planning the week; reporting |

## Fitting a kit
- Drop what the intake gives no reason for. An empty file is noise.
- Add what the intake clearly needs (for example `risks.md` for a regulated project, `data/` notes for a data-heavy one).
- Name things in the project's own words.

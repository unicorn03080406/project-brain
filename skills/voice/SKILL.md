---
name: voice
description: The owner's own voice for any message you write for them to send - a Slack, Teams, WhatsApp or Signal reply, an email, a client update after a fix, test run or PR, a note to a teammate - in a project that has a .brain/ folder. Also use it when the owner shares messages they wrote themselves or rewrites one of your drafts, so their voice can be learned. It changes only how the message reads, never whether you offer one.
user-invocable: false
allowed-tools: Bash(sh:*)
---

# The owner's message voice

Only in projects with a `.brain/` folder. Elsewhere, ignore this skill.

## What this does and does not change

- **Does not change when you write messages.** Offer a draft exactly when you would without this
  skill: the owner asks, a pasted thread calls for a reply, finished work (a fix, a test run, a PR)
  is worth telling the client about. Never add drafts because this skill exists, never drop them.
- **Changes only the wording of the message itself**: voice, tone, style. Your explanation to the
  owner around the draft stays as you would normally write it.

## Before you write the message

```!
sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" voice 2>&1 || echo "(no project brain here: write as you normally would)"
```

1. Read the owner's guide and learned notes above. The guide sets the intent; the learned notes
   and the owner's real messages outrank it where they differ, because they are how the owner
   actually writes.
2. Find the recipient in `.brain/people.md` and match how that person and the owner talk to each
   other (familiar and casual, new and more formal, their shorthand). The situation matters as
   much as the person: a win, a routine update, a delay, a mistake or a payment talk each sound
   different.
3. Keep every fact, commitment and boundary exactly as it is. The voice never adds progress,
   promises, availability, agreement or enthusiasm the owner did not give you.

## Writing it

- Write it as the owner would type it to this person right now: chat messages read like chat,
  not like an email or a document.
- Check it against the guide's "things to avoid" before you show it: no em dashes, no email
  openings or sign-offs in chat, no support or corporate phrasing, no headings or bullet lists in
  a short chat message, no stacked exclamation marks or emojis.
- Put the message in its own block so the owner can copy it as is. For longer messages, one
  draft is better than options; offer an alternative only if the right tone is genuinely unclear.

## Learning the owner's voice

The owner will sometimes write messages themselves. Learn from those, not from your own drafts:

- **Pasted threads** (Slack, Teams, email, WhatsApp) that contain messages the owner sent: the
  owner is the `Me:` line in `.brain/people.md` (ask once which name is theirs if it is missing,
  then add `- Me: <name> (<handles>) · <role>` to people.md).
- **"I sent this" / "I wrote this instead"**, or a rewrite of one of your drafts.

For each such message:
1. Save it verbatim: `echo "<the message>" | sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" voice-example --to "<recipient>" --source "<sources/... path if filed>"`
2. When a pattern is clear (it shows up more than once, or the owner changed your draft in a
   clear direction), note it in the owner's personal file, **style only, never names, facts or
   project content**: `sh "${CLAUDE_SKILL_DIR}/../../scripts/brain.sh" voice-note "<pattern>"`
   Good: "starts messages lowercase", "says 'sounds good', rarely 'works for me'", "no
   exclamation marks with new clients", "signs off updates with just 'lmk'". Bad: anything that
   names a client or says what the project is about.
3. When you learn how a specific person communicates, or how the owner talks to them, add or
   update a short style note on that person's line in `.brain/people.md` (for example
   "casual, emoji-friendly; owner keeps it short with her").

Mention learning in at most one short line to the owner ("Saved your reply as a voice example").

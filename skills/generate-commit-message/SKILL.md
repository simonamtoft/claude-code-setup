---
name: generate-commit-message
description: Use when the user asks for a commit message for staged changes — "commit message?", "what's a good commit message", "propose a short commit message". If nothing is staged, offers to stage unstaged/untracked files first. Produces one focused line in the repo's existing style. Never runs `git commit`.
---

# Generate a commit message

Read what's actually staged, match the repo's commit-message style, and produce a single line the user can paste. Don't commit anything.

## When this triggers

- "commit message?"
- "What's a good commit message?"
- "Propose a small commit message"
- "Short commit message?"
- "Can you give me a short commit message"

## Procedure (in this order)

1. **Inspect what's staged.** Run `git diff --staged --stat` and `git diff --staged`.
   - If the staged set is **non-empty**, continue to step 2.
   - If the staged set is **empty**, run `git status --short` to show unstaged and untracked files. Present the list and ask the user which files to stage — offer "all", specific files, or "none / cancel". Wait for their answer before continuing.
     - If they choose files: run `git add <files>` for each, then continue to step 2.
     - If they choose none or cancel: stop here.
2. **Match the repo's style.** Run `~/.claude/skills/generate-commit-message/scripts/detect_commit_style.sh`. It outputs one of `conventional`, `ticket-prefixed`, or `plain`. Mirror that convention. Don't introduce a new one.
3. **Pick up any ticket reference from the branch name.** Run `~/.claude/skills/_shared/scripts/git_ticket_key.sh`. If it returns a key and the detected style is `ticket-prefixed`, prepend it to the message. Otherwise drop it.
4. **Write one line.** Imperative mood ("Add", "Fix", "Refactor"), ≤72 characters, no trailing period, no emoji, no `Co-Authored-By`, no `🤖`. Describe the **what** at the level of the diff — not the why, not the implementation detail.
5. **If the diff spans unrelated changes,** don't write a portmanteau. Say so and suggest a split (e.g. "this looks like two changes — A and B — consider `git restore --staged` for one of them"). Only continue if the user confirms they want a single message anyway.
6. **Output as a single fenced block** so the user can copy-paste. No preamble, no surrounding commentary.

## Rules

- **Never run `git commit`** — produce the message only.
- **No Co-Authored-By trailer** unless the user explicitly asks.
- **Don't pad.** No "this PR", no "we now", no "various changes". If the diff is genuinely a one-liner, the message is one short clause.
- **Read the diff before writing.** Don't infer from filenames alone — variable renames and behavior changes look the same from outside.
- **Don't restate file paths** the reader can see in `git show` — say what changed at the behavior level.

## Done means

A single commit-message line is on screen in a fenced block, matching the repo's existing convention. Files may have been staged at the user's explicit request. Nothing has been committed.

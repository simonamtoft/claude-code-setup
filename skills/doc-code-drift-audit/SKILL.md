---
name: doc-code-drift-audit
description: This skill should be used when the user asks whether documentation is still accurate, requests a documentation review, asks "are README/AGENTS/docs aligned with the code", or wants to know what's stale in the docs. Read-only by default — surfaces drift as a categorised list, does not auto-edit doc files.
---

# Documentation vs. code drift audit

Walk one or more documentation surfaces and flag where they no longer match the current code. Do not rewrite the docs.

## When this triggers

- "Is the documentation still accurate?"
- "Review the docs in <directory>"
- "Are README / AGENTS.md / CLAUDE.md aligned with the code?"
- "What's stale in <doc file>?"
- Pre-PR doc check

## Procedure

1. **Pick a scope.** Confirm with the user which doc(s) to audit — single file, a `docs/` directory, or all top-level markdown. Don't audit "everything" without a bounded list.
2. **Read each doc file once, in full.** Note every concrete claim it makes that can be verified against the code: paths, commands, file/function names, behaviours, env vars, supported versions.
3. **Verify each claim.** Cheapest verification first: `ls` a path, `grep` for a symbol, run `--help`, read the actual function. Don't speculate.
4. **Categorise drift.** Each drift item gets a tag:
   - **stale-path** — referenced file/directory no longer exists or moved
   - **stale-command** — command no longer works as written
   - **removed-feature** — doc describes something that's gone
   - **undocumented-new** — code has a feature/option the docs don't mention
   - **semantic-drift** — same name, behaviour changed
5. **Output a categorised list.** Group by file, tag each item, give the exact line or location in the doc.

## Rules

- **Read-only by default.** Do not edit doc files. The output is a list the user triages. If the user explicitly asks "fix the drift", confirm scope (which items, which files) before editing — and respect any out-of-scope path rules in CLAUDE.md or memory.
- **One pass per doc file.** Don't try to read-and-rewrite on the same turn; that conflates "audit" and "fix".
- **Don't flag what you didn't verify.** Every item in the output must have a concrete check behind it. "Probably stale" is not allowed.
- **Don't flag style/wording.** This audit is about factual drift vs. code, not prose quality.

## Done means

- A list grouped by doc file, with every item tagged by category.
- Every flagged item has a verifiable check (a path that doesn't exist, a command that errors, a symbol that's gone).
- No doc files modified.

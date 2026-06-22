---
name: review-pr
description: Use when the user wants a comprehensive, multi-lens PR review before opening or finalizing a pull request — covering tests, error handling, comments, type design, general quality, and simplification. Distinct from /code-review (bugs + cleanups) and /review. Dispatches the specialist review agents and aggregates one prioritized summary. Advisory — never edits code.
argument-hint: "[aspects: comments tests errors types code simplify | all] [parallel]"
---

# Comprehensive PR review

Run a multi-lens PR review by dispatching specialist review agents — each focused on one aspect of code quality — then aggregate their findings into a single prioritized summary. This is the *specialist* review; it complements (does not replace) `/code-review` (bug + cleanup pass) and `/review` (PR review).

**Advisory only.** This skill reports findings. It does not edit code. Offer to apply fixes only if the user explicitly asks.

## 1. Determine scope

- Resolve the diff base: `~/.claude/skills/_shared/scripts/git_base_branch.sh` (falls back through open PR → upstream → main/master/develop; if it exits non-zero, ask the user for the base).
- List changed files: `git diff --name-only "$(base)"...HEAD` (and include unstaged work with `git diff --name-only` when reviewing pre-commit). If a PR exists, `gh pr view` for context.
- Parse `$ARGUMENTS` for requested aspects. Tokens: `comments tests errors types code simplify all parallel`. Default when none given: `all`.

## 2. Map aspects → agents

Pick the applicable agents based on the requested aspects and what actually changed:

| Aspect   | Agent                  | Applies when |
|----------|------------------------|--------------|
| code     | `code-reviewer`        | Always (general quality / guideline compliance) |
| tests    | `pr-test-analyzer`     | Test files changed, or new logic lacks tests |
| errors   | `silent-failure-hunter`| Error handling / catch blocks / fallbacks changed |
| comments | `comment-analyzer`     | Comments or docs added/modified |
| types    | `type-design-analyzer` | New or modified types/data models |
| simplify | `code-simplifier`      | Run last — polish after the substantive reviews |

When the user names specific aspects, run only those (still gated by what changed). `all` runs every applicable agent.

## 3. Dispatch the agents

Spawn each applicable agent via the Agent tool, using its `subagent_type` (e.g. `code-reviewer`, `silent-failure-hunter`). In each agent's prompt, state the review scope explicitly: the base branch, the changed files, and that it should focus on the diff (not the whole codebase).

- **Sequential (default):** one agent at a time — easier to read and act on. Run `code-simplifier` last.
- **Parallel (`parallel` arg):** issue all agent calls in a single message so they run concurrently; results return together.

## 4. Aggregate the findings

Combine all agent reports into one summary. Tag every finding with its source agent and a `file:line` reference:

```markdown
# PR Review Summary

## Critical Issues (X found)
- [agent-name] Issue description [file:line]

## Important Issues (X found)
- [agent-name] Issue description [file:line]

## Suggestions (X found)
- [agent-name] Suggestion [file:line]

## Strengths
- What this PR does well

## Recommended Action
1. Fix critical issues first
2. Address important issues
3. Consider suggestions
4. Re-run review after fixes
```

Order severity by the agents' own scoring (code-reviewer 91-100 = critical / 80-89 = important; silent-failure-hunter CRITICAL/HIGH/MEDIUM; pr-test-analyzer and type-design-analyzer numeric ratings). If no agent finds high-confidence issues, say so plainly.

## 5. Stay advisory

End with the summary. Do not modify code. If the user then asks to fix items, address the critical issues first and re-run the relevant aspect to verify.

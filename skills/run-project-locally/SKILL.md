---
name: run-project-locally
description: This skill should be used when the user has just pulled a repository and wants to run it locally, asks for help with first-time local setup, hits build or run errors during initial setup, or asks "how do I run this". Provides a stack-agnostic recipe for getting a project running while respecting the user's preference to review commands before executing them.
---

# Run a project locally

Help the user get a freshly cloned project running on their machine, without executing setup commands on their behalf.

## When this triggers

- "I just pulled this repo, help me run it locally"
- "How do I get this running"
- First-time setup failures (missing tool, wrong port, auth error)
- Questions about ports, env vars, or local dev dependencies

## Procedure

1. **Read docs first.** Open every plausible setup doc: `README.md`, `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `docs/setup*`, `docs/local*`. Don't guess the stack — read what the project says.
2. **Identify the stack.** Run `~/.claude/skills/run-project-locally/scripts/detect_stack.sh`. Each output line is a detected stack label (`node`, `python`, `rust`, `go`, `dotnet`, `ruby`, `java`, `docker`). Multiple lines = multi-service project; treat each separately.
3. **Enumerate the chain** in this order:
   - Tooling check (Node version, .NET SDK, Python version, etc.)
   - Dependency install
   - Database / migrations / seed (if any)
   - Env vars / auth (gcloud, aws, tokens — note where these come from)
   - Build
   - Run
   - Health check (curl, browser URL, log line to grep for)
4. **Present commands as a numbered list** the user can paste step by step. Annotate each with what success looks like.
5. **On failure**, diagnose before retrying. Run through the failure-mode checklist below.

## Rules

- **Print commands, do not execute them.** Only read-only lookups (`ls`, `cat`, `git status`, `which X`, `--version`) are exempt. This is a hard preference of the user.
- **Ask before destructive setup.** `rm -rf`, dropping databases, tearing down containers, resetting auth, force-pushing — confirm in plain language before suggesting the command.
- **Don't loop.** If a command fails twice with the same root cause, stop and surface the cause; don't keep retrying variants.

## Failure-mode checklist

When a setup command fails, check these before changing the command:

- Tool not on PATH (`command -v X`)
- Wrong version (compare `--version` output to docs)
- Port already in use (`lsof -i :<port>`)
- Env var not set or pointing at the wrong environment
- Auth token expired or pointing at the wrong project
- Missing local service (database, broker, mock backend)
- Working directory wrong (some commands need to run from a specific subdir)

## Done means

- A numbered command list the user can paste.
- At least one smoke check that proves the service actually responds (not just "build succeeded").
- Any non-obvious gotchas captured in a short "watch out for" list at the end.

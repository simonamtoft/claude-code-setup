---
name: orient-codebase
description: This skill should be used when the user opens a new repository or subproject and asks for an overview, exploration, structure summary, or "what is this codebase". Enforces a fixed first-pass shape so exploration sessions don't sprawl into unbounded file dumps.
---

# Orient in a new codebase

Give the user a useful mental model of an unfamiliar codebase in a few minutes — not an exhaustive tour.

## When this triggers

- "Explore this repo"
- "What is this codebase / project / subproject"
- "Give me an overview of <directory>"
- User opens a new repo and asks where things live
- First session in a project after a long gap

## Procedure (in this order)

1. **Top-level layout.** List the top-level directories and any conspicuous files (README, AGENTS.md, CLAUDE.md, *.sln, package.json, pyproject.toml, etc.). 5-10 lines max.
2. **Read the docs.** README, AGENTS.md, CLAUDE.md, and any obvious architecture doc. If they exist, trust them as the primary source.
3. **Find entrypoints.** `main.*`, `Program.cs`, `index.ts`, `app.py`, `cmd/*/main.go`, CLI scripts, server bootstraps. Note one or two sentences about each.
4. **One-paragraph architecture summary** in your own words: what this project does, the main components, how data flows. ≤10 lines.
5. **Ask what to drill into.** Don't keep reading on your own — the user knows where they want to go next.

## Rules

- **Output shape is short.** An architecture sketch, not a file dump. If you find yourself listing more than ~10 files, you've gone too deep for the first pass.
- **Depth cap.** No more than ~15 read operations before stopping to summarise and ask. Exploration sessions otherwise sprawl into 100-tool-call rabbit holes.
- **Trust the docs first.** If README explains the architecture, lead with that and verify spot-checks against the code. Don't re-derive what's already written.
- **Don't classify things you didn't read.** If you only saw a filename, don't make claims about what it contains.

## Done means

- The user has a 1-paragraph mental model of the codebase.
- A short list of entrypoints with one-line descriptions.
- A drill-down target chosen by the user, ready for the next turn.

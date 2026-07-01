# Claude Code hooks

User-global hooks that enforce a readonly-Bash guardrail, a per-project edit scope, an end-of-turn verifier, and a secret-file read guard. The first two policies were surfaced by the May 2026 Cursor audit (`~/projects/harness-audit/cursor_audit_out/summary.md`); the secret-file guard reinstates protection the enterprise managed policy silently disabled (see `check-read.sh`).

## Hooks

### `check-bash.sh` — readonly Bash policy

Blocks any `Bash` tool call whose command is not in the readonly allowlist, or that contains compound shell operators (`&&`, `||`, `;`, `|`) with any non-readonly segment.

On the allow path the hook emits a PreToolUse `permissionDecision: "allow"` JSON envelope, so Claude skips its own permission prompt for recognized readonly commands. On the deny path the agent is expected to print the command in a fenced ```bash block and wait for the user to run it.

The hook is the gate: a PreToolUse `exit 2` hard-blocks the tool call regardless of what's in `~/.claude/settings.json permissions.allow`. Entries in `permissions.allow` only take effect for commands the hook itself allows (or for sessions started with `CLAUDE_HOOK_DISABLE=1`). Both single commands and each segment of a compound pipeline are validated against the same allowlist below.

Allowlist:
- Filesystem read/create: `ls`, `pwd`, `cat`, `head`, `tail`, `wc`, `file`, `stat`, `tree`, `find` (rejects `-delete` / `-exec`), `mkdir`
- Search: `grep`, `rg`, `ripgrep`
- Text/data: `jq`, `yq`, `xmllint`, `awk`, `cut`, `sort`, `uniq`, `column`, `echo`, `printf`
- Identity/env: `which`, `type`, `command -v`, `date`, `whoami`, `hostname`, `uname`, `env`
- Git read: `git status|diff|log|show|branch|remote|stash|rev-parse|config|ls-files|blame`
- GitHub CLI read: `gh pr view|diff|list|checks`, `gh run view|list|view-log`, `gh issue view|list`
- Package runners: `bunx`, `npx` (auto-allowed as tok1 — note these fetch and execute arbitrary remote code without a prompt)
- `/tmp` scratchpad writes: `cp`, `mv`, `tee`, `touch`, `ln`, `chmod`, `chown` — allowed only when every required path resolves under `/tmp`. For `cp`/`mv`/`ln` the destination (last positional or `-t DIR`) must be in `/tmp`; for `tee`/`touch` every path argument must be in `/tmp`; for `chmod`/`chown` every path after the mode/owner spec must be in `/tmp`.

**Secret-path guard.** Independent of the allowlist, any segment whose path-like tokens resolve to a protected secret (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.azure`, `~/.kube`, gcloud config, `~/Library/Keychains`, `~/.netrc`/`~/.npmrc`/`~/.pypirc`, `~/.docker/config.json`, `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, `credentials.json`, `service-account*.json`) is blocked — so `cat ~/.ssh/id_rsa` and `cp ~/.aws/credentials /tmp/x` are denied even though `cat`/`cp`-to-`/tmp` are otherwise permitted. The list lives in `lib-secret-paths.sh`. See `check-read.sh` below for why this is enforced in hooks rather than `permissions.deny`.

### `check-read.sh` — secret-file read guard

Blocks the `Read` tool from reading the same protected secret paths (shared matcher in `lib-secret-paths.sh`). Default-allow for everything else.

**Why this is a hook and not a `permissions.deny` rule:** the enterprise managed policy sets `allowManagedPermissionRulesOnly: true`, which makes *all* user-level `permissions.allow`/`deny` rules inert — only managed rules apply. The old `~/.ssh`/`~/.aws`/`*.pem` deny globs in `settings.json` therefore no longer block anything, and `cat`/`head` being on the readonly allowlist meant `cat ~/.ssh/id_rsa` was getting auto-*allowed*. User hooks still run under the managed policy (they aren't permission rules), so they're the only user-controlled enforcement layer left — hence the read guard plus the `check-bash.sh` secret guard above. Note: a user hook can *tighten* but never override a managed `deny`/`ask`.

### `check-edit-scope.sh` — per-project edit allowlist

Blocks `Edit` / `Write` / `MultiEdit` / `NotebookEdit` calls whose `file_path` falls outside the project's declared scope.

- Always blocks writes under `~/Desktop` (specific anti-pattern from the audit).
- Looks for `${CLAUDE_PROJECT_DIR}/.claude/scope.allow`. **If absent, default-allow** — unrelated repos are not affected.
- File format: one path-prefix per line. Relative paths resolve against the project root. Absolute paths are honored as-is. `#` comments and blank lines are ignored.

Example `scope.allow`:

```
# whole repo
.

# also let edits reach user-level Claude config (only for repos where this is intended)
/Users/siap/.claude
```

### `verify-turn.sh` — end-of-turn verification feedback loop

A `Stop` hook that closes the loop with an *external* checker instead of letting the model self-assess correctness. When a turn completes it runs the project's verifier once; if the verifier fails, the hook relays the diagnostics on stderr and `exit 2`, so Claude sees the concrete errors and fixes them before finishing. (Motivated by arXiv 2511.00592 / CompPilot: feedback-grounded loops beat open-loop, and an external ground-truth checker beats LLM self-verification.)

It runs at the natural "I'm done" boundary — **not after every edit** — so intermediate multi-edit states aren't flagged. **Bounded retries** replace the old one-shot behavior: a per-session counter (`$TMPDIR/claude-verify-<session_id>`) allows up to `MAX_ROUNDS` (default 3) verify→fix rounds, so a *wrong* fix doesn't slip through after a single pass. On the final round the message tells Claude to summarize the remaining failure for the user instead of looping; past the cap the hook stops trapping the turn (exits 0) so it can never spin forever. A passing verifier clears the counter. Cost note: a failing turn re-runs the verifier up to `MAX_ROUNDS`+1 times, so keep the verifier reasonably fast.

Verifier resolution is **optional and per-project**, in precedence order:

1. `${CLAUDE_PROJECT_DIR}/.claude/verify.sh` — run as `verify.sh` (from the project root).
2. else a `verify` task in `Taskfile.yml` / `Taskfile.yaml` at the project root (when the `task` CLI is installed and `task --list-all` shows a `verify` task) — run as `task verify`.

**If neither is present, the hook is a no-op** (default-noop, like `check-edit-scope.sh`'s default-allow), so unrelated repos are unaffected. Because it runs once per turn, a project-wide check (lint + typecheck) is fine here.

Example `.claude/verify.sh`:

```bash
#!/usr/bin/env bash
# non-zero exit = something to fix before finishing.
npx tsc --noEmit && npx eslint .
```

Example `Taskfile.yml` task:

```yaml
tasks:
  verify:
    cmds:
      - npx tsc --noEmit
      - npx eslint .
```

### `claude-md-refcheck.py` — CLAUDE.md package-map drift check

A second `Stop` hook (runs alongside `verify-turn.sh`) that catches *documentation* drift: `CLAUDE.md` files name files in backticks to describe a directory's layout (``routes/me.py``, ``VerdictBar.tsx``), and those maps rot when files are renamed or deleted. The hook scans every `CLAUDE.md` at/below the scan root (`CLAUDE_PROJECT_DIR`, else cwd; or an explicit path argument), extracts backticked filename tokens, and on any that no longer resolve to a real file relays them on stderr and `exit 2` — so Claude sees the concrete broken refs and can fix the doc before finishing.

**Deterministic half only.** It catches "named file doesn't exist" (the class that deleted-but-still-documented `VerdictBar.tsx` falls into). Stale *prose* ("step 6 in progress" after step 6 landed) is not mechanically checkable and is left to a per-project CI audit (e.g. im-proposal's `.github/workflows/doc-drift.yml`, which runs the same idea through its model gateway).

**Conservative by construction** — false positives train you to ignore it:
- placeholder tokens (`step_N.py`, globs, `<...>` ranges) are skipped;
- a token resolves if it exists at the path OR its basename exists anywhere under the root, so a doc that names a file by basename never false-flags.

**Fires at most once per session** (a sentinel at `$TMPDIR/claude-md-refcheck-<session_id>`), so an unaddressed or intentional drift doesn't nag every turn. **No-op** when there's no `CLAUDE.md` under the root, so unrelated repos are unaffected. Honors `CLAUDE_HOOK_DISABLE=1`. Requires `python3` on `PATH` (invoked as `python3 …/claude-md-refcheck.py`, so the exec bit is irrelevant).

## Bypass

For an exceptional session where you genuinely want the agent to run commands or edit anywhere, start Claude Code with:

```bash
CLAUDE_HOOK_DISABLE=1 claude
```

All of these *user* hooks short-circuit when this env var is `1`. No in-conversation bypass exists by design — the whole point is to avoid the "I'll just run it" failure mode the audit caught repeatedly.

**Caveat under managed policy:** `CLAUDE_HOOK_DISABLE=1` only disables these user hooks. The enterprise-managed PreToolUse hooks (e.g. the OneDrive/SharePoint block) and managed `permissions.deny` rules are enforced by the client from the managed settings and are **not** affected — so this is not an "edit/run anything" escape hatch, only a way to drop the user-defined guardrails.

## Wiring

`~/.claude/settings.json` has a `hooks.PreToolUse` block matching `Bash` → `check-bash.sh`, `Read` → `check-read.sh`, and `Edit|Write|MultiEdit|NotebookEdit` → `check-edit-scope.sh`, and a `hooks.Stop` block with two hooks → `verify-turn.sh` then `python3 …/claude-md-refcheck.py`. Edit those blocks to disable temporarily; delete them to remove. (`check-read.sh` is invoked as `bash …/check-read.sh` so it doesn't depend on the execute bit; `claude-md-refcheck.py` is invoked as `python3 …` for the same reason.)

## Dependencies

`jq` (Apple-shipped at `/usr/bin/jq` on recent macOS, or `brew install jq`). Both hooks block fail-closed if `jq` is missing.

## Testing

Smoke-test each hook by feeding a JSON payload on stdin:

```bash
echo '{"tool_input":{"command":"git status"}}'      | ~/.claude/hooks/check-bash.sh; echo $?   # 0
echo '{"tool_input":{"command":"npm install foo"}}' | ~/.claude/hooks/check-bash.sh; echo $?   # 2
echo '{"tool_input":{"command":"bunx foo"}}'                 | ~/.claude/hooks/check-bash.sh; echo $?   # 0
echo '{"tool_input":{"command":"npx nx test myapp"}}'        | ~/.claude/hooks/check-bash.sh; echo $?   # 0
echo '{"tool_input":{"command":"npx nx run-many -t test,lint"}}' | ~/.claude/hooks/check-bash.sh; echo $?   # 0
echo '{"tool_input":{"command":"nx test myapp"}}'            | ~/.claude/hooks/check-bash.sh; echo $?   # 2
echo '{"tool_input":{"command":"bunx $(echo foo)"}}'         | ~/.claude/hooks/check-bash.sh; echo $?   # 2  (cmd substitution always blocked)
CLAUDE_PROJECT_DIR=/some/repo echo '{"tool_input":{"file_path":"/tmp/x"}}' \
  | ~/.claude/hooks/check-edit-scope.sh; echo $?

# verify-turn.sh: no verifier in the project -> no-op (0)
CLAUDE_PROJECT_DIR=/tmp/none echo '{"stop_hook_active":false}' \
  | ~/.claude/hooks/verify-turn.sh; echo $?   # 0

# claude-md-refcheck.py: pass a scan root as arg (clean repo -> 0)
python3 ~/.claude/hooks/claude-md-refcheck.py /path/to/clean/repo </dev/null; echo $?   # 0
# a repo whose CLAUDE.md names a deleted file -> 2 + report on stderr
```

# Claude Code hooks

User-global `PreToolUse` hooks that enforce two policies surfaced by the May 2026 Cursor audit (`~/projects/harness-audit/cursor_audit_out/summary.md`).

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

## Bypass

For an exceptional session where you genuinely want the agent to run commands or edit anywhere, start Claude Code with:

```bash
CLAUDE_HOOK_DISABLE=1 claude
```

Both hooks short-circuit when this env var is `1`. No in-conversation bypass exists by design — the whole point is to avoid the "I'll just run it" failure mode the audit caught repeatedly.

## Wiring

`~/.claude/settings.json` has a `hooks.PreToolUse` block matching `Bash` → `check-bash.sh` and `Edit|Write|MultiEdit|NotebookEdit` → `check-edit-scope.sh`. Edit that block to disable temporarily; delete it to remove.

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
```

#!/usr/bin/env bash
# Stop hook: run the project's verifier once when a turn completes, and feed any
# failure back so Claude fixes it before handing control back (the CompPilot
# feedback-loop idea from arXiv 2511.00592 — close the loop with an *external*
# ground-truth checker rather than the model's self-assessment).
#
# Runs at the natural "I'm done" boundary, not after every edit, so intermediate
# multi-edit states aren't flagged.
#
# Verifier resolution (per-project, optional), in precedence order:
#   1. ${CLAUDE_PROJECT_DIR}/.claude/verify.sh  -> verify.sh
#   2. a `verify` task in Taskfile.yml/.yaml    -> task verify
# Neither present (or `task` not installed) -> no-op. Default-noop mirrors
# check-edit-scope.sh's default-allow: unrelated repos are unaffected.

set -uo pipefail

if [[ "${CLAUDE_HOOK_DISABLE:-}" == "1" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

input=$(cat)

# If we already blocked once this turn and Claude is continuing because of it,
# let the turn end to avoid an infinite verify->fix->verify loop.
if [[ "$(echo "$input" | jq -r '.stop_hook_active // false')" == "true" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$project_dir" ]]; then
  exit 0
fi

# 1. Explicit per-project script wins.
verify_sh="${project_dir}/.claude/verify.sh"
if [[ -x "$verify_sh" ]]; then
  if ! out=$(cd "$project_dir" && "$verify_sh" 2>&1); then
    echo "Hook: verification failed (.claude/verify.sh). Fix before finishing:" >&2
    echo "$out" >&2
    exit 2
  fi
  exit 0
fi

# 2. Else a `verify` task in a Taskfile at the project root.
if command -v task >/dev/null 2>&1; then
  taskfile=""
  [[ -f "${project_dir}/Taskfile.yml" ]] && taskfile="${project_dir}/Taskfile.yml"
  [[ -z "$taskfile" && -f "${project_dir}/Taskfile.yaml" ]] && taskfile="${project_dir}/Taskfile.yaml"
  if [[ -n "$taskfile" ]] && task --taskfile "$taskfile" --list-all 2>/dev/null | grep -qE '^\* verify:'; then
    if ! out=$(cd "$project_dir" && task verify 2>&1); then
      echo "Hook: verification failed (task verify). Fix before finishing:" >&2
      echo "$out" >&2
      exit 2
    fi
  fi
fi

exit 0

#!/usr/bin/env bash
# PostToolUse hook for Edit / Write / MultiEdit.
# Closes the edit loop with an external ground-truth checker (the CompPilot
# feedback-loop idea from arXiv 2511.00592): after an edit, run the project's
# verifier on the changed file and feed concrete diagnostics back to Claude.
#
# Verifier resolution (per-project, optional), in precedence order:
#   1. ${CLAUDE_PROJECT_DIR}/.claude/verify.sh  -> verify.sh "<file>"
#   2. a `verify` task in Taskfile.yml/.yaml    -> task verify -- "<file>"
# Neither present (or `task` not installed) -> no-op. Default-noop mirrors
# check-edit-scope.sh's default-allow: unrelated repos are unaffected.

set -uo pipefail

if [[ "${CLAUDE_HOOK_DISABLE:-}" == "1" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  # Match the other hooks' dependency on jq, but never block on a *post* hook:
  # a missing verifier must not turn into a failed edit.
  exit 0
fi

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

if [[ -z "$file_path" ]]; then
  exit 0
fi

project_dir="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$project_dir" ]]; then
  exit 0
fi

# 1. Explicit per-project script wins.
verify_sh="${project_dir}/.claude/verify.sh"
if [[ -x "$verify_sh" ]]; then
  if ! out=$("$verify_sh" "$file_path" 2>&1); then
    echo "Hook: verification failed for '${file_path}' (.claude/verify.sh):" >&2
    echo "$out" >&2
    exit 2
  fi
  exit 0
fi

# 2. Else a `verify` task in a Taskfile at the project root.
if command -v task >/dev/null 2>&1; then
  if [[ -f "${project_dir}/Taskfile.yml" || -f "${project_dir}/Taskfile.yaml" ]]; then
    if task --taskfile "${project_dir}/Taskfile.yml" --list-all 2>/dev/null | grep -qE '^\* verify:' \
       || task --taskfile "${project_dir}/Taskfile.yaml" --list-all 2>/dev/null | grep -qE '^\* verify:'; then
      if ! out=$(cd "$project_dir" && task verify -- "$file_path" 2>&1); then
        echo "Hook: verification failed for '${file_path}' (task verify):" >&2
        echo "$out" >&2
        exit 2
      fi
    fi
  fi
fi

exit 0

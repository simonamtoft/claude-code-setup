#!/usr/bin/env bash
# PreToolUse hook for Bash. Blocks non-readonly commands.
# See ~/.claude/hooks/README.md for policy and bypass.

set -uo pipefail

if [[ "${CLAUDE_HOOK_DISABLE:-}" == "1" ]]; then
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Hook: jq not installed (brew install jq). Blocking Bash for safety." >&2
  exit 2
fi

# Emit a PreToolUse "allow" decision so Claude skips the permission prompt
# for commands the hook recognizes as readonly.
_emit_allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"readonly allowlist"}}\n'
  exit 0
}

cmd=$(jq -r '.tool_input.command // empty')
if [[ -z "$cmd" ]]; then
  exit 0
fi

# Backticks and <(…) / >(…) stay blocked outright — rare in practice and
# harder to validate. $(...) is peeled below: if every inner command is
# readonly, the substitution is replaced with a placeholder and the outer
# command continues through the normal allowlist checks.
if [[ "$cmd" == *'<('* || "$cmd" == *'>('* || "$cmd" == *'`'* ]]; then
  cat >&2 <<EOF
Hook: process substitution (<(...), >(...)) or backticks blocked.
Use separate Bash calls instead.

Command: ${cmd}
EOF
  exit 2
fi

# ---------------------------------------------------------------------------
# Readonly allowlist — applied to either a whole command or each segment of a
# compound pipeline. Returns 0 if the segment is readonly, 1 otherwise.
# ---------------------------------------------------------------------------
_is_readonly_segment() {
  local seg="$1"
  local tok1 tok2 tok3 _rest pair triple

  # ltrim
  seg="${seg#"${seg%%[![:space:]]*}"}"
  [[ -z "$seg" ]] && return 0

  read -r tok1 tok2 tok3 _rest <<< "$seg"
  pair="${tok1} ${tok2}"
  triple="${tok1} ${tok2} ${tok3}"

  # gh readonly subcommands (matched before the two-token pair table so
  # arbitrary gh subcommands fall through to default-deny).
  case "$triple" in
    "gh pr view"|"gh pr view "*|\
    "gh pr diff"|"gh pr diff "*|\
    "gh pr list"|"gh pr list "*|\
    "gh pr checks"|"gh pr checks "*|\
    "gh run view"|"gh run view "*|\
    "gh run list"|"gh run list "*|\
    "gh run view-log"|"gh run view-log "*|\
    "gh issue view"|"gh issue view "*|\
    "gh issue list"|"gh issue list "*)
      return 0 ;;
  esac

  case "$pair" in
    "node --version"|"node --help"|\
    "npm --version"|"npm --help"|\
    "npx --version"|"npx --help"|\
    "python --version"|"python3 --version"|\
    "deno --version"|"deno --help"|\
    "bun --version"|"bun --help"|\
    "go version"|"cargo --version")
      return 0 ;;
  esac

  case "$pair" in
    "git status"|"git status "*|\
    "git diff"|"git diff "*|\
    "git log"|"git log "*|\
    "git show"|"git show "*|\
    "git branch"|"git branch "*|\
    "git remote"|"git remote "*|\
    "git stash"|"git stash "*|\
    "git rev-parse"|"git rev-parse "*|\
    "git config"|"git config "*|\
    "git ls-files"|"git ls-files "*|\
    "git blame"|"git blame "*|\
    "command -v"|"command -v "*)
      return 0 ;;
  esac

  # Allow scripts in the user's Claude skills/hooks directories
  # Match both ~/... and $HOME/... forms since ~ isn't expanded in [[ ]]
  if [[ "$tok1" == "$HOME/.claude/skills/"* || "$tok1" == "$HOME/.claude/hooks/"* || \
        "$tok1" == "~/.claude/skills/"* || "$tok1" == "~/.claude/hooks/"* ]]; then
    return 0
  fi

  case "$tok1" in
    ls|pwd|cat|head|tail|wc|file|stat|grep|rg|ripgrep|which|type|echo|printf|date|whoami|hostname|uname|tree|jq|yq|xmllint|column|sort|uniq|cut|awk|sed|tr|paste|xxd|od|env|true|false|test|\[|mkdir|fp|bunx|npx|cd|basename|dirname)
      return 0 ;;
    find)
      if [[ "$seg" == *" -delete"* || "$seg" == *" -exec"* || "$seg" == *" -execdir"* || "$seg" == *" -ok"* || "$seg" == *" -okdir"* ]]; then
        return 1
      fi
      return 0 ;;
  esac

  return 1
}

_normalize_path() {
  # Resolve .. and . without requiring the path to exist
  local path="$1" result="" part
  IFS='/' read -ra parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|".") ;;
      "..") result="${result%/*}" ;;
      *) result="$result/$part" ;;
    esac
  done
  printf '%s' "${result:-/}"
}

_is_rm_in_scope() {
  local seg="$1" tok1
  read -r tok1 _ <<< "$seg"
  [[ "$tok1" != "rm" ]] && return 1

  local -a args
  read -ra args <<< "$seg"

  local found_path=0 arg resolved
  for arg in "${args[@]:1}"; do   # skip 'rm' itself
    [[ "$arg" == -* || "$arg" == "--" ]] && continue
    found_path=1

    if   [[ "$arg" == /* ]]; then resolved="$arg"
    elif [[ "$arg" == "~"* ]]; then resolved="${arg/#~/$HOME}"
    else resolved="$PWD/$arg"
    fi
    resolved=$(_normalize_path "$resolved")

    if [[ "$resolved" != "$PWD/"* && "$resolved" != "$PWD" \
       && "$resolved" != "$HOME/.claude/plans/"* \
       && "$resolved" != /tmp/* && "$resolved" != /private/tmp/* ]]; then
      return 1
    fi
  done

  [[ $found_path -eq 1 ]] || return 1
  return 0
}

_is_bash_local_script() {
  local seg="$1" tok1 tok2
  read -r tok1 tok2 _ <<< "$seg"
  [[ "$tok1" != "bash" && "$tok1" != "sh" ]] && return 1
  [[ -z "$tok2" || "$tok2" == -* ]] && return 1
  local resolved
  if   [[ "$tok2" == /* ]]; then resolved="$tok2"
  elif [[ "$tok2" == "~"* ]]; then resolved="${tok2/#~/$HOME}"
  else resolved="$PWD/$tok2"
  fi
  resolved=$(_normalize_path "$resolved")
  [[ "$resolved" == "$PWD/"* || "$resolved" == "$PWD" ]]
}

_is_write_in_tmp() {
  local seg="$1"
  local -a args
  read -ra args <<< "$seg"
  local tok1="${args[0]:-}"

  local mode=""
  case "$tok1" in
    tee|touch)   mode="all" ;;
    cp|mv|ln)    mode="last" ;;
    chmod|chown) mode="skip_first" ;;
    *) return 1 ;;
  esac

  local -a positionals=()
  local t_dest=""
  local i=1 a
  while (( i < ${#args[@]} )); do
    a="${args[i]}"
    if [[ "$a" == "--" ]]; then
      (( i++ ))
      while (( i < ${#args[@]} )); do positionals+=("${args[i]}"); (( i++ )); done
      break
    fi
    if [[ "$a" == "-t" || "$a" == "--target-directory" ]]; then
      (( i++ )); t_dest="${args[i]:-}"; (( i++ )); continue
    fi
    if [[ "$a" == --target-directory=* ]]; then
      t_dest="${a#--target-directory=}"; (( i++ )); continue
    fi
    if [[ "$a" == -* ]]; then
      (( i++ )); continue
    fi
    positionals+=("$a"); (( i++ ))
  done

  local -a to_check=()
  local n=${#positionals[@]}
  case "$mode" in
    all)
      (( n > 0 )) || return 1
      to_check=("${positionals[@]}") ;;
    last)
      if [[ -n "$t_dest" ]]; then
        to_check=("$t_dest")
      else
        (( n > 0 )) || return 1
        to_check=("${positionals[$((n-1))]}")
      fi ;;
    skip_first)
      (( n >= 2 )) || return 1
      to_check=("${positionals[@]:1}") ;;
  esac

  local p resolved
  for p in "${to_check[@]}"; do
    if   [[ "$p" == /* ]]; then resolved="$p"
    elif [[ "$p" == "~"* ]]; then resolved="${p/#~/$HOME}"
    else resolved="$PWD/$p"
    fi
    resolved=$(_normalize_path "$resolved")
    [[ "$resolved" == "/tmp" || "$resolved" == "/tmp/"* ]] || return 1
  done
  return 0
}

_is_permitted_segment() {
  _is_readonly_segment "$1"  && return 0
  _is_rm_in_scope "$1"       && return 0
  _is_bash_local_script "$1" && return 0
  _is_write_in_tmp "$1"      && return 0
  return 1
}

# Peel $(...) substitutions: if every inner command is readonly (e.g.
# $(git rev-parse …), $(basename …)), replace each with a placeholder so the
# outer command can flow through the normal allowlist. If any inner command
# isn't readonly, block the whole command.
if [[ "$cmd" == *'$('* ]]; then
  _peel_subst() {
    local s="$1" out="" depth start inner rest ch i=0
    while [[ "$s" == *'$('* ]] && (( i < 32 )); do
      (( i++ ))
      start="${s%%\$\(*}"
      rest="${s#"$start"\$\(}"
      depth=1
      inner=""
      while [[ -n "$rest" && $depth -gt 0 ]]; do
        ch="${rest:0:1}"
        rest="${rest:1}"
        if   [[ "$ch" == '(' ]]; then depth=$((depth+1)); inner+="$ch"
        elif [[ "$ch" == ')' ]]; then depth=$((depth-1)); [[ $depth -gt 0 ]] && inner+="$ch"
        else inner+="$ch"
        fi
      done
      [[ $depth -ne 0 ]] && { printf '%s' "__BAD__"; return; }
      if _is_readonly_segment "$inner"; then
        s="${start}__SUBST__${rest}"
      else
        printf '%s' "__BAD__"
        return
      fi
    done
    printf '%s' "$s"
  }
  peeled=$(_peel_subst "$cmd")
  if [[ "$peeled" == "__BAD__" ]]; then
    cat >&2 <<EOF
Hook: \$(...) blocked — inner command is not in the readonly allowlist.

Command: ${cmd}

Allowed inner commands include: ls, pwd, cat, head, tail, wc, stat, grep, rg, git status|diff|log|show|rev-parse|config|ls-files|blame, jq, yq, basename, dirname, date, echo, printf, cd, fp.
Split into separate Bash calls if you need a non-readonly subcommand.
EOF
    exit 2
  fi
  cmd="$peeled"
fi

# Compound? Split on |, &&, ||, ; and validate each segment.
# First strip the contents of single- and double-quoted strings to a
# placeholder so e.g. `grep -E '(Edit|Write)'` isn't mis-split on the `|`
# that lives inside the quotes. The :a;N;$!ba slurps all input lines into a
# single pattern space first so the regex matches across newlines (handles
# multi-line `--description "…"` style arguments). Best-effort: doesn't
# handle `\'` escapes.
stripped=$(printf '%s' "$cmd" | sed -E -e ':a' -e 'N' -e '$!ba' -e "s/'[^']*'/__QSTR__/g" -e 's/"[^"]*"/__QSTR__/g')

if [[ "$stripped" == *"|"* || "$stripped" == *"&&"* || "$stripped" == *"||"* || "$stripped" == *";"* ]]; then
  # Operate on the stripped form so quoted operators don't trigger splits.
  # We only need tok1 of each segment to check the allowlist, and tok1 is
  # the command name — never quoted in practice.
  normalised=$(printf '%s' "$stripped" | sed -E 's/&&|\|\|/\n/g; s/[|;]/\n/g')

  bad_segment=""
  while IFS= read -r seg; do
    # ltrim + rtrim
    seg="${seg#"${seg%%[![:space:]]*}"}"
    seg="${seg%"${seg##*[![:space:]]}"}"
    [[ -z "$seg" ]] && continue
    if ! _is_permitted_segment "$seg"; then
      bad_segment="$seg"
      break
    fi
  done <<< "$normalised"

  if [[ -z "$bad_segment" ]]; then
    _emit_allow
  fi

  cat >&2 <<EOF
Hook: compound shell — segment is not in the readonly allowlist.

Segment: ${bad_segment}
Full command: ${cmd}

Either split into separate Bash calls (each must be readonly) or print the command in a fenced \`\`\`bash block and ask the user to run it.
EOF
  exit 2
fi

# Pass-through: commands that aren't readonly but shouldn't be hard-blocked
# either. Exit 0 without emitting an allow decision so Claude's normal
# permission flow runs (settings allowlist → prompt if no match).
read -r tok1 _ <<< "$cmd"
case "$tok1" in
  task) exit 0 ;;
esac

# Single command path
if _is_permitted_segment "$cmd"; then
  _emit_allow
fi

cat >&2 <<EOF
Hook: non-readonly Bash blocked.

Command: ${cmd}

Print the command in a fenced \`\`\`bash block and ask the user to run it, then wait for the output.

Allowed without asking: ls, pwd, cat, head, tail, wc, stat, grep, rg, find (no -delete/-exec/-ok), mkdir, cd, basename, dirname, rm (paths under \$PWD, ~/.claude/plans/, or /tmp/), cp|mv|tee|touch|ln|chmod|chown (every required path must resolve under /tmp), git status|diff|log|show|branch|remote|stash|rev-parse|config|ls-files|blame, gh pr view|diff|list|checks, gh run view|list|view-log, gh issue view|list, bunx, npx, which, type, command -v, echo, printf, date, whoami, hostname, uname, tree, jq, yq, xmllint, sort, uniq, cut, awk, sed, tr, paste, column, xxd, od, env, true, false, test. Compound commands (|, &&, ||, ;) are allowed when every segment is in this hook's allowlist. \$(...) is allowed when the inner command is readonly; \`...\`, <(...), >(...) are always blocked.

To bypass for a single session, start it with CLAUDE_HOOK_DISABLE=1 in the environment.
EOF
exit 2

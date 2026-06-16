#!/usr/bin/env bash
# detect_stack.sh — detect tech stacks present in the repo root.
# Usage: detect_stack.sh [repo-root]
# Output: one label per line (node python rust go dotnet ruby java docker). Exit 0 always.
set -euo pipefail

root="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

[[ -f "$root/package.json" ]] && echo "node"
[[ -f "$root/pyproject.toml" || -f "$root/setup.py" || -f "$root/requirements.txt" ]] && echo "python"
[[ -f "$root/Cargo.toml" ]] && echo "rust"
[[ -f "$root/go.mod" ]] && echo "go"
find "$root" -maxdepth 2 \( -name "*.csproj" -o -name "*.sln" \) -print -quit 2>/dev/null | grep -q . && echo "dotnet" || true
[[ -f "$root/Gemfile" ]] && echo "ruby"
[[ -f "$root/pom.xml" || -f "$root/build.gradle" || -f "$root/build.gradle.kts" ]] && echo "java"
[[ -f "$root/Dockerfile" || -f "$root/docker-compose.yml" || -f "$root/docker-compose.yaml" ]] && echo "docker"

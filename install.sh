#!/usr/bin/env bash
# Install the opus-use-subagents skill and its agents.
# Usage: ./install.sh            -> ~/.claude
#        ./install.sh <project>  -> <project>/.claude
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
target="${1:+$1/.claude}"
target="${target:-$HOME/.claude}"
mkdir -p "$target/skills" "$target/agents"
cp -R "$here/skills/opus-use-subagents" "$target/skills/"
cp "$here"/agents/*.md "$target/agents/"
echo "Installed into $target"

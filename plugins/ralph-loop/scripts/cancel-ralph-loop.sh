#!/bin/bash

# Cancel Ralph Loop Script
# Removes state file to stop the loop

set -euo pipefail

# Function to walk up directory tree to find ralph-loop.local.md
# This handles cases where user cd's into a subdirectory after starting the loop
find_ralph_state() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/ralph-loop.local.md" ]]; then
      echo "$dir/.claude/ralph-loop.local.md"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  # Check root as well
  if [[ -f "/.claude/ralph-loop.local.md" ]]; then
    echo "/.claude/ralph-loop.local.md"
    return 0
  fi
  return 1
}

# Walk up from current directory to find state file
STATE_FILE=$(find_ralph_state "$(pwd)") || true

if [[ -z "$STATE_FILE" ]] || [[ ! -f "$STATE_FILE" ]]; then
  echo "No active Ralph loop found."
  exit 0
fi

# Get current iteration before removing
ITERATION=$(grep '^iteration:' "$STATE_FILE" | head -1 | awk '{print $2}')

# Remove the state file
rm "$STATE_FILE"

echo "✅ Cancelled Ralph loop (was at iteration ${ITERATION:-unknown})"

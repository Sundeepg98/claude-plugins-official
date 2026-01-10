#!/bin/bash
set -euo pipefail

# Helper to exit with "allow" decision (Claude Code expects JSON output)
allow_exit() {
  echo '{"decision": "allow"}'
  exit 0
}

normalize_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    echo "$path"
    return
  fi
  path=$(echo "$path" | tr '\\' '/')
  if [[ "$path" =~ ^([A-Za-z]):/ ]]; then
    local drive="${BASH_REMATCH[1]}"
    drive=$(echo "$drive" | tr '[:upper:]' '[:lower:]')
    path="/${drive}${path:2}"
  fi
  echo "$path"
}

HOOK_INPUT=$(cat)
HOOK_CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')

find_ralph_state() {
  local dir="$1"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.claude/ralph-loop.local.md" ]]; then
      echo "$dir/.claude/ralph-loop.local.md"
      return 0
    fi
    dir=$(dirname "$dir")
  done
  return 1
}

if [[ -n "$HOOK_CWD" ]]; then
  RALPH_STATE_FILE=$(find_ralph_state "$HOOK_CWD") || true
else
  RALPH_STATE_FILE=$(find_ralph_state "$(pwd)") || true
fi

[[ -z "$RALPH_STATE_FILE" ]] || [[ ! -f "$RALPH_STATE_FILE" ]] && allow_exit

FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || true)
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || true)
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || true)
ORIGIN_CWD=$(echo "$FRONTMATTER" | grep '^origin_cwd:' | sed 's/origin_cwd: *//' | tr -d '"' || true)
STORED_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' | tr -d '"' || true)

TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')
CURRENT_SESSION=$(basename "$TRANSCRIPT_PATH" .jsonl)

if [[ -n "$ORIGIN_CWD" ]]; then
  if [[ -n "$STORED_SESSION" ]] && [[ "$STORED_SESSION" != "null" ]]; then
    [[ "$STORED_SESSION" != "$CURRENT_SESSION" ]] && allow_exit
  else
    NORMALIZED_HOOK_CWD=$(normalize_path "$HOOK_CWD")
    NORMALIZED_ORIGIN_CWD=$(normalize_path "$ORIGIN_CWD")
    [[ "$NORMALIZED_HOOK_CWD" != "$NORMALIZED_ORIGIN_CWD" ]] && allow_exit
    TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
    sed "s/^session_id: .*/session_id: \"$CURRENT_SESSION\"/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$RALPH_STATE_FILE"
    FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
  fi
fi

[[ ! "$ITERATION" =~ ^[0-9]+$ ]] && { rm "$RALPH_STATE_FILE"; allow_exit; }

if [[ -n "$MAX_ITERATIONS" ]] && [[ "$MAX_ITERATIONS" != "null" ]] && [[ "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  [[ $ITERATION -ge $MAX_ITERATIONS ]] && { rm "$RALPH_STATE_FILE"; allow_exit; }
fi

PROMPT=$(sed '1,/^---$/d' "$RALPH_STATE_FILE" | sed '1d')
NEW_ITERATION=$((ITERATION + 1))
sed -i "s/^iteration: .*/iteration: $NEW_ITERATION/" "$RALPH_STATE_FILE"

# Check for completion promise in LAST ASSISTANT MESSAGE only (not entire transcript)
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  TRANSCRIPT_UNIX=$(normalize_path "$TRANSCRIPT_PATH")
  if [[ -f "$TRANSCRIPT_UNIX" ]]; then
    # Extract last assistant message
    if grep -q '"role":"assistant"' "$TRANSCRIPT_UNIX" 2>/dev/null; then
      LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_UNIX" | tail -1)
      LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '.message.content | map(select(.type == "text")) | map(.text) | join("\n")' 2>/dev/null || echo "")
      # Extract promise text using perl (handles multiline)
      if [[ -n "$LAST_OUTPUT" ]]; then
        PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
        if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
          rm "$RALPH_STATE_FILE"
          allow_exit
        fi
      fi
    fi
  fi
fi

cat << EOF
{
  "decision": "block",
  "reason": "🔄 Ralph Loop - Iteration $NEW_ITERATION of ${MAX_ITERATIONS:-∞}\n\n$PROMPT"
}
EOF

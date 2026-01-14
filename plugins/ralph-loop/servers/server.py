#!/usr/bin/env python3
"""
Ralph Loop MCP Server - Manages iteration state via MCP protocol.

This MCP server integrates with the ralph-loop plugin by writing state
to .claude/ralph-loop.local.md in the same format, allowing the existing
stop hook to work seamlessly.

Tools:
  - start_loop: Start a new Ralph loop
  - get_status: Get current loop state
  - cancel_loop: Cancel/abort loop early

Note: increment_iteration and complete_loop are handled automatically
by the plugin's stop hook (auto-increment on stop, promise matching).
"""

import os
import sys
import re
from datetime import datetime, timezone
from typing import Optional

# MCP imports
try:
    from mcp.server.fastmcp import FastMCP
except ImportError:
    print("Error: mcp package not installed. Run: pip install mcp", file=sys.stderr)
    sys.exit(1)

# Initialize FastMCP server
mcp = FastMCP("ralph-mcp")


def get_state_file(origin_cwd: str) -> str:
    """Get state file path for a given working directory."""
    return os.path.join(origin_cwd, ".claude", "ralph-loop.local.md")


def parse_frontmatter(content: str) -> dict:
    """Parse YAML frontmatter from markdown content."""
    match = re.match(r'^---\n(.*?)\n---\n(.*)$', content, re.DOTALL)
    if not match:
        return {}

    frontmatter_text = match.group(1)
    prompt_text = match.group(2).strip()

    state = {"prompt": prompt_text}

    for line in frontmatter_text.split('\n'):
        if ':' in line:
            key, value = line.split(':', 1)
            key = key.strip()
            value = value.strip()

            # Parse values
            if value == 'true':
                state[key] = True
            elif value == 'false':
                state[key] = False
            elif value == 'null':
                state[key] = None
            elif value.isdigit():
                state[key] = int(value)
            elif value.startswith('"') and value.endswith('"'):
                state[key] = value[1:-1]
            else:
                state[key] = value

    return state


def load_state(origin_cwd: str) -> dict:
    """Load current loop state from file."""
    state_file = get_state_file(origin_cwd)

    if os.path.exists(state_file):
        try:
            with open(state_file, 'r', encoding='utf-8') as f:
                content = f.read()
            return parse_frontmatter(content)
        except (IOError, UnicodeDecodeError):
            pass

    return {
        "active": False,
        "iteration": 0,
        "max_iterations": 0,
        "completion_promise": None,
        "prompt": None,
        "started_at": None
    }


def save_state(origin_cwd: str, state: dict) -> None:
    """Save loop state to file in ralph-loop.local.md format."""
    state_file = get_state_file(origin_cwd)
    os.makedirs(os.path.dirname(state_file), exist_ok=True)

    # Format completion promise for YAML
    promise = state.get("completion_promise") or state.get("promise")
    if promise:
        promise_yaml = f'"{promise}"'
    else:
        promise_yaml = "null"

    # Build markdown with YAML frontmatter
    content = f"""---
active: {'true' if state.get('active') else 'false'}
iteration: {state.get('iteration', 0)}
max_iterations: {state.get('max_iterations', 0)}
completion_promise: {promise_yaml}
completion_promise_alt: null
started_at: "{state.get('started_at', '')}"
origin_cwd: "{origin_cwd}"
---

{state.get('prompt', '')}
"""

    with open(state_file, 'w', encoding='utf-8') as f:
        f.write(content)


def delete_state(origin_cwd: str) -> None:
    """Delete state file."""
    state_file = get_state_file(origin_cwd)
    if os.path.exists(state_file):
        os.remove(state_file)


@mcp.tool()
def start_loop(prompt: str, origin_cwd: str, max_iterations: int = 0, promise: str = None) -> dict:
    """
    Start a new Ralph loop.

    Args:
        prompt: The task prompt for the loop
        origin_cwd: Working directory path (project directory)
        max_iterations: Maximum iterations (0 = unlimited)
        promise: Completion promise text (optional)

    Returns:
        Loop state with status
    """
    # Normalize path
    origin_cwd = os.path.normpath(origin_cwd)

    state = load_state(origin_cwd)

    if state.get("active"):
        return {
            "success": False,
            "error": "Loop already active",
            "current_iteration": state.get("iteration", 0),
            "origin_cwd": origin_cwd
        }

    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    state = {
        "active": True,
        "iteration": 1,
        "max_iterations": max_iterations,
        "completion_promise": promise,
        "prompt": prompt,
        "started_at": now,
        "origin_cwd": origin_cwd
    }
    save_state(origin_cwd, state)

    return {
        "success": True,
        "status": "started",
        "iteration": 1,
        "max_iterations": max_iterations,
        "promise": promise,
        "origin_cwd": origin_cwd,
        "state_file": get_state_file(origin_cwd)
    }


@mcp.tool()
def get_status(origin_cwd: str = None) -> dict:
    """
    Get current loop status.

    Args:
        origin_cwd: Working directory path. If not provided, returns inactive status.

    Returns:
        Current loop state including iteration, max, promise, active status
    """
    if not origin_cwd:
        return {
            "active": False,
            "error": "No origin_cwd provided"
        }

    origin_cwd = os.path.normpath(origin_cwd)
    state = load_state(origin_cwd)

    return {
        "active": state.get("active", False),
        "iteration": state.get("iteration", 0),
        "max_iterations": state.get("max_iterations", 0),
        "promise": state.get("completion_promise"),
        "prompt": state.get("prompt"),
        "started_at": state.get("started_at"),
        "origin_cwd": origin_cwd,
        "state_file": get_state_file(origin_cwd)
    }


@mcp.tool()
def cancel_loop(origin_cwd: str, reason: str = None) -> dict:
    """
    Cancel the loop early.

    Args:
        origin_cwd: Working directory path
        reason: Optional cancellation reason

    Returns:
        Cancellation status and iteration reached
    """
    origin_cwd = os.path.normpath(origin_cwd)
    state = load_state(origin_cwd)

    if not state.get("active"):
        return {
            "success": False,
            "error": "No active loop to cancel"
        }

    final_iteration = state.get("iteration", 0)

    # Delete state file (same as plugin does on cancel)
    delete_state(origin_cwd)

    return {
        "success": True,
        "status": "cancelled",
        "iteration_reached": final_iteration,
        "reason": reason
    }


if __name__ == "__main__":
    mcp.run()

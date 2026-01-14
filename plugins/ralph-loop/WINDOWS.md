# Ralph Loop - Cross-Platform Support

This fork includes fixes for running ralph-loop on Windows (native and WSL).

## Supported Environments

| Environment | Status | How It Works |
|-------------|--------|--------------|
| Native Windows | ✅ | Polyglot `.cmd` calls Git Bash |
| WSL | ✅ | Polyglot `.cmd` runs as bash script |
| Linux/Mac | ✅ | Polyglot `.cmd` runs as bash script |

## What's Different from Upstream

| File | Change | Why |
|------|--------|-----|
| `hooks/hooks.json` | Points to `stop-hook.cmd` | Single entry point for all platforms |
| `hooks/stop-hook.cmd` | Polyglot script | Works in both cmd.exe AND bash |
| `hooks/stop-hook.sh` | Added `normalize_path()` | Converts Windows paths (D:\) to Unix (/d/) |
| `commands/ralph-loop.md` | `RALPH_ARGS` wrapper | Protects special chars in prompts |
| `scripts/setup-ralph-loop.sh` | Session tracking fields | Prevents inheritance bugs |

## Prerequisites

### Native Windows
- **Git for Windows** installed at `C:\Program Files\Git\`
- **jq** installed (via `winget install jqlang.jq`)

### WSL / Linux / Mac
- **jq** installed
- **bash** available

## How the Polyglot Works

The `stop-hook.cmd` file is a polyglot - valid in both cmd.exe and bash:

```cmd
:; exec bash "$(dirname "$0")/stop-hook.sh" ; exit
@echo off
"C:\Program Files\Git\bin\bash.exe" "%~dp0stop-hook.sh"
```

**In bash (WSL/Linux/Mac):**
- `:` is a no-op command
- `;` separates commands
- `exec bash ...` runs stop-hook.sh directly
- Never reaches line 2

**In cmd.exe (Native Windows):**
- `:;` is a label (skipped)
- `@echo off` executes
- Calls Git Bash with stop-hook.sh

## Syncing with Upstream

When upstream (anthropics/claude-plugins-official) updates:

```bash
# Add upstream remote (once)
git remote add upstream https://github.com/anthropics/claude-plugins-official.git

# Fetch and merge
git fetch upstream
git merge upstream/main

# Resolve conflicts - keep these fixes:
#   - hooks.json: keep pointing to .cmd
#   - stop-hook.cmd: keep polyglot version
#   - stop-hook.sh: keep normalize_path() function
# Push
git push origin main
```

## Recent Fixes

| Issue | Status | Solution |
|-------|--------|----------|
| Special characters `() [] {}` in prompts | Fixed | `parse_shell_args()` using xargs+bash |
| Multi-word completion promises | Fixed | Use `+` instead of spaces (e.g., `TASK+COMPLETE`) |
| Promise matching | Fixed | Both `+` and space versions matched via `completion_promise_alt` |

## Known Limitations

- **Multi-word promises require `+` syntax**: Use `--completion-promise TASK+COMPLETE` instead of `"TASK COMPLETE"`
  - The `+` is automatically converted to spaces for display and matching
  - This is a Claude Code `$ARGUMENTS` limitation, not fixable in plugin

## Files Changed from Upstream

```
plugins/ralph-loop/
├── commands/
│   └── ralph-loop.md      (RALPH_ARGS wrapper)
├── hooks/
│   ├── hooks.json         (points to .cmd)
│   ├── stop-hook.cmd      (polyglot - bash + cmd)
│   └── stop-hook.sh       (normalize_path added)
└── scripts/
    └── setup-ralph-loop.sh (session tracking)
```

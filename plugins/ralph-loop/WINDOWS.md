# Ralph Loop - Windows Support

This fork includes Windows-specific fixes for the ralph-loop plugin.

## What's Different from Upstream

| File | Change | Why |
|------|--------|-----|
| `hooks/hooks.json` | Points to `stop-hook.cmd` | Windows can't run `.sh` directly |
| `hooks/stop-hook.cmd` | New file | Wrapper that calls bash.exe |
| `hooks/stop-hook.sh` | Added `normalize_path()` | Converts Windows paths (D:\) to Unix (/d/) |
| `commands/ralph-loop.md` | `RALPH_ARGS` wrapper | Protects special chars in prompts |
| `scripts/setup-ralph-loop.sh` | Session tracking fields | Prevents inheritance bugs |

## Prerequisites

- **Git for Windows** installed at `C:\Program Files\Git\`
- **jq** installed (via `winget install jqlang.jq`)

## How It Works

1. Claude Code calls `stop-hook.cmd` (Windows can run .cmd natively)
2. `stop-hook.cmd` calls `bash.exe` with `stop-hook.sh`
3. `stop-hook.sh` uses `normalize_path()` to handle Windows paths

## Syncing with Upstream

When upstream (anthropics/claude-plugins-official) updates:

```bash
# Add upstream remote (once)
git remote add upstream https://github.com/anthropics/claude-plugins-official.git

# Fetch and merge
git fetch upstream
git merge upstream/main

# Resolve conflicts - keep Windows fixes in ralph-loop folder
# Push
git push origin main
```

## Known Limitations

- **Double quotes in arguments** don't work: `/ralph-loop test "quoted"` will fail
  - This is a Claude Code limitation, not fixable in plugin
  - Workaround: Avoid double quotes, use single words for completion promises

## Files Changed from Upstream

```
plugins/ralph-loop/
├── commands/
│   └── ralph-loop.md      (RALPH_ARGS wrapper)
├── hooks/
│   ├── hooks.json         (points to .cmd)
│   ├── stop-hook.cmd      (NEW - Windows wrapper)
│   └── stop-hook.sh       (normalize_path added)
└── scripts/
    └── setup-ralph-loop.sh (session tracking)
```

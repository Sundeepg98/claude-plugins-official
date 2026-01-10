# Ralph Loop Stop Hook - PowerShell version for Windows
# This avoids Git Bash fork() issues on Windows

$ErrorActionPreference = "SilentlyContinue"
$LogFile = "$env:TEMP\ralph-hook.log"

function Log($msg) {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogFile -Value "[$timestamp] $msg"
}

function Allow-Exit {
    Log "Allowing exit"
    exit 0
}

Log "Hook started (PowerShell)"

# Read JSON input from stdin
$input_json = [Console]::In.ReadToEnd()
Log "Got input: $($input_json.Substring(0, [Math]::Min(100, $input_json.Length)))..."

try {
    $hook_data = $input_json | ConvertFrom-Json
    $hook_cwd = $hook_data.cwd
    $transcript_path = $hook_data.transcript_path
} catch {
    Log "Failed to parse JSON: $_"
    Allow-Exit
}

Log "CWD: $hook_cwd"

# Find ralph state file by walking up directories
function Find-RalphState($dir) {
    while ($dir -and $dir.Length -gt 3) {
        $state_file = Join-Path $dir ".claude\ralph-loop.local.md"
        if (Test-Path $state_file) {
            return $state_file
        }
        $dir = Split-Path $dir -Parent
    }
    return $null
}

$search_dir = if ($hook_cwd) { $hook_cwd } else { Get-Location }
Log "Searching from: $search_dir"

$ralph_state_file = Find-RalphState $search_dir
Log "State file: $(if ($ralph_state_file) { $ralph_state_file } else { 'none' })"

if (-not $ralph_state_file -or -not (Test-Path $ralph_state_file)) {
    Log "No state file, exiting"
    Allow-Exit
}

# Parse frontmatter
$content = Get-Content $ralph_state_file -Raw
$frontmatter_match = [regex]::Match($content, '(?s)^---\r?\n(.+?)\r?\n---')
if (-not $frontmatter_match.Success) {
    Log "No frontmatter found"
    Remove-Item $ralph_state_file -Force
    Allow-Exit
}

$frontmatter = $frontmatter_match.Groups[1].Value
$iteration = 0
$max_iterations = $null
$completion_promise = $null
$origin_cwd = $null
$stored_session = $null

foreach ($line in $frontmatter -split "`n") {
    if ($line -match '^iteration:\s*(\d+)') { $iteration = [int]$Matches[1] }
    if ($line -match '^max_iterations:\s*(\d+)') { $max_iterations = [int]$Matches[1] }
    if ($line -match '^completion_promise:\s*"?([^"]+)"?') { $completion_promise = $Matches[1] }
    if ($line -match '^origin_cwd:\s*"?([^"]+)"?') { $origin_cwd = $Matches[1] }
    if ($line -match '^session_id:\s*"?([^"]+)"?') { $stored_session = $Matches[1] }
}

$current_session = [System.IO.Path]::GetFileNameWithoutExtension($transcript_path)

Log "Iteration: $iteration, Max: $max_iterations, Session: $current_session"

# Session isolation check
if ($origin_cwd) {
    if ($stored_session -and $stored_session -ne "null") {
        if ($stored_session -ne $current_session) {
            Log "Different session, allowing exit"
            Allow-Exit
        }
    } else {
        # Normalize paths for comparison
        $norm_hook = $hook_cwd -replace '\\', '/'
        $norm_origin = $origin_cwd -replace '\\', '/'
        if ($norm_hook -ne $norm_origin) {
            Log "Different CWD, allowing exit"
            Allow-Exit
        }
        # Update session ID
        $content = $content -replace 'session_id:\s*"?[^"\r\n]*"?', "session_id: `"$current_session`""
        Set-Content -Path $ralph_state_file -Value $content -NoNewline
    }
}

# Check max iterations
if ($max_iterations -and $iteration -ge $max_iterations) {
    Log "Max iterations reached"
    Remove-Item $ralph_state_file -Force
    Allow-Exit
}

# Check completion promise
if ($completion_promise -and $completion_promise -ne "null" -and (Test-Path $transcript_path)) {
    $transcript_content = Get-Content $transcript_path -Raw
    $assistant_lines = $transcript_content -split "`n" | Where-Object { $_ -match '"role":"assistant"' }
    if ($assistant_lines) {
        $last_line = $assistant_lines[-1]
        try {
            $msg = $last_line | ConvertFrom-Json
            $text_content = ($msg.message.content | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join "`n"
            if ($text_content -match '<promise>([^<]+)</promise>') {
                $promise_text = $Matches[1].Trim() -replace '\s+', ' '
                if ($promise_text -eq $completion_promise) {
                    Log "Promise matched, completing"
                    Remove-Item $ralph_state_file -Force
                    Allow-Exit
                }
            }
        } catch {
            Log "Error parsing transcript: $_"
        }
    }
}

# Extract prompt (everything after frontmatter)
$prompt = $content -replace '(?s)^---\r?\n.+?\r?\n---\r?\n?', ''

# Increment iteration
$new_iteration = $iteration + 1
$content = $content -replace 'iteration:\s*\d+', "iteration: $new_iteration"
Set-Content -Path $ralph_state_file -Value $content -NoNewline

Log "Blocking - iteration $new_iteration"

# Output block decision
$max_display = if ($max_iterations) { $max_iterations } else { "∞" }
$reason = "🔄 Ralph Loop - Iteration $new_iteration of $max_display`n`n$prompt"

@{
    decision = "block"
    reason = $reason
} | ConvertTo-Json -Compress

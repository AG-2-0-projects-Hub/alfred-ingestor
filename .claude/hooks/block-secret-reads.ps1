# PreToolUse hook: blocks Read/Bash/PowerShell calls that would dump a
# secrets-file's full contents into the transcript. Mechanical backstop for
# a mistake that recurred multiple times despite a standing memory telling
# Claude not to do this (see lessons.md 2026-09-19 in this repo).
$raw = [Console]::In.ReadToEnd()
try { $data = $raw | ConvertFrom-Json } catch { exit 0 }
$toolName = $data.tool_name

# Matches this project's actual secret-bearing files (.env variants, MCP
# configs, anything named secret/credential) -- deliberately NOT a bare
# "token"/"key" substring match, which would false-positive on ordinary
# source files (task_queue.py, keyboard_shortcuts.dart, etc.).
$secretPattern = '\.env(\.|$)|\.mcp\.json$|_mcp_profiles[/\\]global\.json$|secret|credential'

function Deny($reason) {
  $out = @{
    hookSpecificOutput = @{
      hookEventName = "PreToolUse"
      permissionDecision = "deny"
      permissionDecisionReason = $reason
    }
  }
  $out | ConvertTo-Json -Compress -Depth 5
  exit 0
}

if ($toolName -eq "Read") {
  $path = $data.tool_input.file_path
  if ($path -and ($path -imatch $secretPattern)) {
    Deny "This looks like a secrets file ($path). Never Read a secrets file directly -- it dumps every real value into the transcript (this exact mistake recurred multiple times; see lessons.md 2026-09-19). Use the project's own exported values instead (e.g. _tests/runner/lib/env.ts's env.* exports), or jq 'keys' / an anchored grep '^[A-Za-z_]+=' if you only need key names."
  }
  exit 0
}

if ($toolName -eq "Bash" -or $toolName -eq "PowerShell") {
  $cmd = $data.tool_input.command
  if ($cmd -and ($cmd -imatch $secretPattern)) {
    if ($cmd -imatch '(^|[|;&\s])(cat|head|tail|less|more|type|Get-Content)(\s|$)') {
      Deny "This command reads a secrets-like file with a tool that dumps its full contents (cat/head/tail/type/Get-Content). Use the project's exported env values instead (e.g. _tests/runner/lib/env.ts), or extract only key names with jq 'keys' / grep -oE '^[A-Za-z_]+='."
    }
    if ($cmd -imatch '(^|[|;&\s])(grep|rg|sed|awk|Select-String)(\s|$)') {
      if ($cmd -notmatch 'jq' -and $cmd -notmatch '\^\[A-Za-z_') {
        Deny "This command inspects a secrets-like file without a structural, value-safe extraction. Use jq 'keys' for JSON, or an anchored pattern like grep -oE '^[A-Za-z_]+=' for .env files -- an unanchored grep/sed/Select-String on a secrets file has leaked a full value before in this project."
      }
    }
  }
  exit 0
}

exit 0

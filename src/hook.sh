#!/bin/bash
# Claude Code Permission Dialog Hook
# Displays a native macOS dialog for tool approval instead of the terminal prompt.
#
# Uses a compiled Swift app for a proper floating window with keyboard support:
#   Enter = Allow, Escape = Deny
#
# Dependencies: jq

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Read the hook input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // "Unknown"')
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // {}')
CWD=$(echo "$INPUT" | jq -r '.cwd // ""')

# Build a short, human-readable action description (shown prominently)
build_action() {
  case "$TOOL_NAME" in
    Bash)
      local desc
      desc=$(echo "$TOOL_INPUT" | jq -r '.description // empty')
      if [ -n "$desc" ]; then
        printf 'Run command: %s' "$desc"
      else
        printf 'Run a shell command'
      fi
      ;;
    Edit)
      local file
      file=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
      file=$(abbreviate_home "$file")
      printf 'Edit file: %s' "$file"
      ;;
    Write)
      local file
      file=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
      file=$(abbreviate_home "$file")
      printf 'Write file: %s' "$file"
      ;;
    Read)
      local file
      file=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
      file=$(abbreviate_home "$file")
      printf 'Read file: %s' "$file"
      ;;
    WebFetch)
      local url
      url=$(echo "$TOOL_INPUT" | jq -r '.url // "unknown"')
      printf 'Fetch URL: %s' "$url"
      ;;
    WebSearch)
      local query
      query=$(echo "$TOOL_INPUT" | jq -r '.query // "unknown"')
      printf 'Web search: %s' "$query"
      ;;
    Task)
      local desc subtype
      desc=$(echo "$TOOL_INPUT" | jq -r '.description // "unknown"')
      subtype=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // "unknown"')
      printf 'Launch %s agent: %s' "$subtype" "$desc"
      ;;
    Glob)
      local pattern
      pattern=$(echo "$TOOL_INPUT" | jq -r '.pattern // "unknown"')
      printf 'Search for files matching: %s' "$pattern"
      ;;
    Grep)
      local pattern
      pattern=$(echo "$TOOL_INPUT" | jq -r '.pattern // "unknown"')
      printf 'Search file contents for: %s' "$pattern"
      ;;
    mcp__*)
      # Extract a readable name from mcp__server__tool format
      local readable
      readable=$(echo "$TOOL_NAME" | sed 's/mcp__//;s/__/ > /g')
      printf 'MCP call: %s' "$readable"
      ;;
    *)
      printf 'Use tool: %s' "$TOOL_NAME"
      ;;
  esac
}

# Build the detailed view (shown in scrollable area below)
build_detail() {
  case "$TOOL_NAME" in
    Bash)
      local cmd
      cmd=$(echo "$TOOL_INPUT" | jq -r '.command // "unknown command"')
      printf '%s' "$cmd"
      ;;
    Edit)
      local old new
      old=$(echo "$TOOL_INPUT" | jq -r '.old_string // ""')
      new=$(echo "$TOOL_INPUT" | jq -r '.new_string // ""')
      printf 'Replace:\n%s\n\nWith:\n%s' "$old" "$new"
      ;;
    Write)
      local content
      content=$(echo "$TOOL_INPUT" | jq -r '.content // ""' | head -c 1000)
      printf '%s' "$content"
      ;;
    Read)
      local offset limit
      offset=$(echo "$TOOL_INPUT" | jq -r '.offset // empty')
      limit=$(echo "$TOOL_INPUT" | jq -r '.limit // empty')
      if [ -n "$offset" ] || [ -n "$limit" ]; then
        printf 'Offset: %s, Limit: %s' "${offset:-0}" "${limit:-all}"
      else
        printf '(entire file)'
      fi
      ;;
    WebFetch)
      local prompt
      prompt=$(echo "$TOOL_INPUT" | jq -r '.prompt // ""')
      printf 'Prompt: %s' "$prompt"
      ;;
    WebSearch)
      echo "$TOOL_INPUT" | jq -r 'to_entries | map("\(.key): \(.value)") | join("\n")'
      ;;
    Task)
      local prompt
      prompt=$(echo "$TOOL_INPUT" | jq -r '.prompt // ""' | head -c 500)
      printf '%s' "$prompt"
      ;;
    Glob)
      local path
      path=$(echo "$TOOL_INPUT" | jq -r '.path // "."')
      path=$(abbreviate_home "$path")
      printf 'Path: %s' "$path"
      ;;
    Grep)
      local path glob output_mode
      path=$(echo "$TOOL_INPUT" | jq -r '.path // "."')
      path=$(abbreviate_home "$path")
      glob=$(echo "$TOOL_INPUT" | jq -r '.glob // empty')
      output_mode=$(echo "$TOOL_INPUT" | jq -r '.output_mode // empty')
      printf 'Path: %s' "$path"
      [ -n "$glob" ] && printf '\nFile filter: %s' "$glob"
      [ -n "$output_mode" ] && printf '\nOutput: %s' "$output_mode"
      ;;
    *)
      echo "$TOOL_INPUT" | jq -r 'to_entries | map("\(.key): \(.value)") | join("\n")' | head -c 1000
      ;;
  esac
}

abbreviate_home() {
  local path="$1"
  echo "${path/#$HOME/~}"
}

ACTION=$(build_action)
DETAIL=$(build_detail)

# Pass data to the Swift dialog via stdin as JSON
RESULT=$(jq -n \
  --arg tool "$TOOL_NAME" \
  --arg action "$ACTION" \
  --arg detail "$DETAIL" \
  --arg cwd "$CWD" \
  '{"tool_name": $tool, "action": $action, "detail": $detail, "cwd": $cwd}' \
  | "$HOOK_DIR/permission-dialog")

if [ "$RESULT" = "allow" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: "Approved via macOS dialog"
    }
  }'
  exit 0
else
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Denied via macOS dialog"
    }
  }'
  exit 0
fi

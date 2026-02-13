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

# Save hook input to temp files for reliable jq parsing
# (avoids issues with echo piping large/complex JSON through shell variables)
HOOK_INPUT_FILE=$(mktemp)
TOOL_INPUT_FILE=$(mktemp)
trap 'rm -f "$HOOK_INPUT_FILE" "$TOOL_INPUT_FILE"' EXIT

cat > "$HOOK_INPUT_FILE"

TOOL_NAME=$(jq -r '.tool_name // "Unknown"' < "$HOOK_INPUT_FILE")
jq '.tool_input // {}' < "$HOOK_INPUT_FILE" > "$TOOL_INPUT_FILE"
CWD=$(jq -r '.cwd // ""' < "$HOOK_INPUT_FILE")

# Build a short, human-readable action description (shown prominently)
build_action() {
  case "$TOOL_NAME" in
    Bash)
      local desc
      desc=$(jq -r '.description // empty' < "$TOOL_INPUT_FILE")
      if [ -n "$desc" ]; then
        printf 'Run command: %s' "$desc"
      else
        printf 'Run a shell command'
      fi
      ;;
    Edit)
      local file
      file=$(jq -r '.file_path // "unknown"' < "$TOOL_INPUT_FILE")
      file=$(abbreviate_home "$file")
      printf 'Edit file: %s' "$file"
      ;;
    Write)
      local file
      file=$(jq -r '.file_path // "unknown"' < "$TOOL_INPUT_FILE")
      file=$(abbreviate_home "$file")
      printf 'Write file: %s' "$file"
      ;;
    Read)
      local file
      file=$(jq -r '.file_path // "unknown"' < "$TOOL_INPUT_FILE")
      file=$(abbreviate_home "$file")
      printf 'Read file: %s' "$file"
      ;;
    WebFetch)
      local url
      url=$(jq -r '.url // "unknown"' < "$TOOL_INPUT_FILE")
      printf 'Fetch URL: %s' "$url"
      ;;
    WebSearch)
      local query
      query=$(jq -r '.query // "unknown"' < "$TOOL_INPUT_FILE")
      printf 'Web search: %s' "$query"
      ;;
    Task)
      local desc subtype
      desc=$(jq -r '.description // "unknown"' < "$TOOL_INPUT_FILE")
      subtype=$(jq -r '.subagent_type // "unknown"' < "$TOOL_INPUT_FILE")
      printf 'Launch %s agent: %s' "$subtype" "$desc"
      ;;
    Glob)
      local pattern
      pattern=$(jq -r '.pattern // "unknown"' < "$TOOL_INPUT_FILE")
      printf 'Search for files matching: %s' "$pattern"
      ;;
    Grep)
      local pattern
      pattern=$(jq -r '.pattern // "unknown"' < "$TOOL_INPUT_FILE")
      printf 'Search file contents for: %s' "$pattern"
      ;;
    ExitPlanMode)
      printf 'Review plan'
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
      cmd=$(jq -r '.command // "unknown command"' < "$TOOL_INPUT_FILE")
      printf '%s' "$cmd"
      ;;
    Edit)
      local old new
      old=$(jq -r '.old_string // ""' < "$TOOL_INPUT_FILE")
      new=$(jq -r '.new_string // ""' < "$TOOL_INPUT_FILE")
      printf 'Replace:\n%s\n\nWith:\n%s' "$old" "$new"
      ;;
    Write)
      local content
      content=$(jq -r '.content // ""' < "$TOOL_INPUT_FILE" | head -c 1000)
      printf '%s' "$content"
      ;;
    Read)
      local offset limit
      offset=$(jq -r '.offset // empty' < "$TOOL_INPUT_FILE")
      limit=$(jq -r '.limit // empty' < "$TOOL_INPUT_FILE")
      if [ -n "$offset" ] || [ -n "$limit" ]; then
        printf 'Offset: %s, Limit: %s' "${offset:-0}" "${limit:-all}"
      else
        printf '(entire file)'
      fi
      ;;
    WebFetch)
      local prompt
      prompt=$(jq -r '.prompt // ""' < "$TOOL_INPUT_FILE")
      printf 'Prompt: %s' "$prompt"
      ;;
    WebSearch)
      jq -r 'to_entries | map("\(.key): \(.value)") | join("\n")' < "$TOOL_INPUT_FILE"
      ;;
    Task)
      local prompt
      prompt=$(jq -r '.prompt // ""' < "$TOOL_INPUT_FILE" | head -c 500)
      printf '%s' "$prompt"
      ;;
    Glob)
      local path
      path=$(jq -r '.path // "."' < "$TOOL_INPUT_FILE")
      path=$(abbreviate_home "$path")
      printf 'Path: %s' "$path"
      ;;
    Grep)
      local path glob output_mode
      path=$(jq -r '.path // "."' < "$TOOL_INPUT_FILE")
      path=$(abbreviate_home "$path")
      glob=$(jq -r '.glob // empty' < "$TOOL_INPUT_FILE")
      output_mode=$(jq -r '.output_mode // empty' < "$TOOL_INPUT_FILE")
      printf 'Path: %s' "$path"
      [ -n "$glob" ] && printf '\nFile filter: %s' "$glob"
      [ -n "$output_mode" ] && printf '\nOutput: %s' "$output_mode"
      ;;
    ExitPlanMode)
      local plan
      plan=$(jq -r '.plan // ""' < "$TOOL_INPUT_FILE")
      printf '%s' "$plan"
      ;;
    *)
      jq -r 'to_entries | map("\(.key): \(.value)") | join("\n")' < "$TOOL_INPUT_FILE" | head -c 1000
      ;;
  esac
}

# Build custom options JSON for specific tools (null = use defaults)
build_options() {
  case "$TOOL_NAME" in
    ExitPlanMode)
      cat <<'OPTS'
[
  {"label": "Approve plan", "shortcut": "\u23ce", "icon": "checkmark.circle", "value": "allow"},
  {"label": "Approve with auto-accepted edits", "shortcut": "\u2318A", "icon": "checkmark.circle.badge.checkmark", "value": "allow_accept_edits"},
  {"label": "Request changes", "shortcut": "\u238b", "icon": "pencil.circle", "value": "deny"}
]
OPTS
      ;;
    *)
      echo "null"
      ;;
  esac
}

abbreviate_home() {
  local path="$1"
  echo "${path/#$HOME/~}"
}

ACTION=$(build_action)
DETAIL=$(build_detail)
OPTIONS=$(build_options)

# Pass data to the Swift dialog via stdin as JSON
RAW_INPUT=$(<"$HOOK_INPUT_FILE")
if [ "$OPTIONS" != "null" ]; then
  RESULT=$(jq -n \
    --arg tool "$TOOL_NAME" \
    --arg action "$ACTION" \
    --arg detail "$DETAIL" \
    --arg cwd "$CWD" \
    --arg raw "$RAW_INPUT" \
    --argjson options "$OPTIONS" \
    '{tool_name: $tool, action: $action, detail: $detail, cwd: $cwd, raw_input: $raw, options: $options, deny_value: "deny"}' \
    | "$HOOK_DIR/permission-dialog")
else
  RESULT=$(jq -n \
    --arg tool "$TOOL_NAME" \
    --arg action "$ACTION" \
    --arg detail "$DETAIL" \
    --arg cwd "$CWD" \
    --arg raw "$RAW_INPUT" \
    '{tool_name: $tool, action: $action, detail: $detail, cwd: $cwd, raw_input: $raw}' \
    | "$HOOK_DIR/permission-dialog")
fi

# Extract the first permission_suggestions entry for "Always Allow"
SUGGESTIONS=$(jq '.permission_suggestions // []' < "$HOOK_INPUT_FILE")

case "$RESULT" in
  allow)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "allow"
        }
      }
    }'
    ;;
  allow_always|allow_accept_edits)
    jq -n --argjson perms "$SUGGESTIONS" '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "allow",
          updatedPermissions: $perms
        }
      }
    }'
    ;;
  deny:*)
    REASON="${RESULT#deny:}"
    jq -n --arg reason "$REASON" '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "deny",
          message: $reason
        }
      }
    }'
    ;;
  *)
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PermissionRequest",
        decision: {
          behavior: "deny",
          message: "Denied via macOS dialog"
        }
      }
    }'
    ;;
esac
exit 0

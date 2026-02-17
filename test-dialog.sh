#!/bin/bash
# Test the permission dialog directly with sample data.
# Usage: ./test-dialog.sh [tool_name]
# Examples:
#   ./test-dialog.sh           # defaults to Bash
#   ./test-dialog.sh Edit
#   ./test-dialog.sh ExitPlanMode

set -euo pipefail

HOOK_DIR="${HOME}/.claude/hooks"
TOOL="${1:-Bash}"

case "$TOOL" in
  Bash)
    INPUT='{"tool_name":"Bash","tool_input":{"command":"find . -name \"*.swift\" | xargs grep -l NSPanel","description":"Find Swift files referencing NSPanel"},"cwd":"'"$(pwd)"'","permission_suggestions":[{"type":"bash","pattern":"find *"}]}'
    ;;
  Edit)
    INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'"$(pwd)"'/src/PermissionDialog.swift","old_string":"override var canBecomeKey: Bool { true }","new_string":"override var canBecomeKey: Bool { return true }"},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  Write)
    INPUT='{"tool_name":"Write","tool_input":{"file_path":"'"$(pwd)"'/test-output.txt","content":"Hello world\nThis is a test file.\nLine three."},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  Read)
    INPUT='{"tool_name":"Read","tool_input":{"file_path":"'"$(pwd)"'/src/PermissionDialog.swift","offset":10,"limit":50},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  Grep)
    INPUT='{"tool_name":"Grep","tool_input":{"pattern":"NSPanel","path":".","glob":"*.swift","output_mode":"content"},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  Task)
    INPUT='{"tool_name":"Task","tool_input":{"description":"Find all UI components","subagent_type":"Explore","prompt":"Search the codebase for all NSView subclasses and document their purpose."},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  ExitPlanMode)
    INPUT='{"tool_name":"ExitPlanMode","tool_input":{"plan":"1. Refactor KeyHandlerView to support configurable key bindings\n2. Add unit tests for selection logic\n3. Extract theme colors into a separate struct"},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
  *)
    INPUT='{"tool_name":"'"$TOOL"'","tool_input":{"example_param":"example_value"},"cwd":"'"$(pwd)"'","permission_suggestions":[]}'
    ;;
esac

echo "Testing: $TOOL"
echo "---"
RESULT=$(echo "$INPUT" | "$HOOK_DIR/permission-dialog.sh")
echo "Result:"
echo "$RESULT" | jq .

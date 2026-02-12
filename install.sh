#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> Claude Code Permission Dialog Installer"
echo ""

# Check dependencies
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required. Install with: brew install jq"
  exit 1
fi

if ! command -v swiftc &>/dev/null; then
  echo "Error: swiftc is required. Install Xcode Command Line Tools: xcode-select --install"
  exit 1
fi

# Create install directory
mkdir -p "$INSTALL_DIR"

# Compile Swift dialog
echo "==> Compiling permission dialog..."
swiftc -O -o "$INSTALL_DIR/permission-dialog" "$SCRIPT_DIR/src/PermissionDialog.swift" -framework Cocoa
echo "    Built: $INSTALL_DIR/permission-dialog"

# Install hook script
cp "$SCRIPT_DIR/src/hook.sh" "$INSTALL_DIR/permission-dialog.sh"
chmod +x "$INSTALL_DIR/permission-dialog.sh"
echo "    Installed: $INSTALL_DIR/permission-dialog.sh"

# Configure Claude Code settings
HOOK_CONFIG='{
  "matcher": ".*",
  "hooks": [
    {
      "type": "command",
      "command": "~/.claude/hooks/permission-dialog.sh",
      "timeout": 130,
      "statusMessage": "Waiting for permission dialog..."
    }
  ]
}'

if [ -f "$SETTINGS_FILE" ]; then
  # Check if hooks.PermissionRequest already has our hook
  if jq -e '.hooks.PermissionRequest[]? | select(.hooks[]?.command == "~/.claude/hooks/permission-dialog.sh")' "$SETTINGS_FILE" &>/dev/null; then
    echo ""
    echo "==> Hook already configured in $SETTINGS_FILE, skipping."
  else
    # Add our hook to the existing settings
    UPDATED=$(jq --argjson hook "$HOOK_CONFIG" '
      .hooks //= {} |
      .hooks.PermissionRequest //= [] |
      .hooks.PermissionRequest += [$hook]
    ' "$SETTINGS_FILE")
    echo "$UPDATED" > "$SETTINGS_FILE"
    echo ""
    echo "==> Added hook to $SETTINGS_FILE"
  fi
else
  # Create new settings file with just the hook
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  jq -n --argjson hook "$HOOK_CONFIG" '{
    hooks: {
      PermissionRequest: [$hook]
    }
  }' > "$SETTINGS_FILE"
  echo ""
  echo "==> Created $SETTINGS_FILE with hook config"
fi

echo ""
echo "==> Done! Restart Claude Code for the hook to take effect."
echo ""
echo "    Usage:"
echo "      Enter = Allow"
echo "      Escape = Deny"
echo ""
echo "    To limit which tools trigger the dialog, edit the"
echo "    \"matcher\" in $SETTINGS_FILE."
echo "    Examples:"
echo "      \".*\"                         All tools (default)"
echo "      \"Bash|Edit|Write\"            Only mutating tools"
echo "      \"Bash|Edit|Write|mcp__.*\"    Mutating + MCP tools"

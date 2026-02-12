#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "==> Uninstalling Claude Code Permission Dialog"
echo ""

# Remove binaries
rm -f "$INSTALL_DIR/permission-dialog"
rm -f "$INSTALL_DIR/permission-dialog.sh"
echo "    Removed: $INSTALL_DIR/permission-dialog"
echo "    Removed: $INSTALL_DIR/permission-dialog.sh"

# Remove hook from settings
if [ -f "$SETTINGS_FILE" ]; then
  UPDATED=$(jq '
    if .hooks.PermissionRequest then
      .hooks.PermissionRequest |= map(select(.hooks[]?.command != "~/.claude/hooks/permission-dialog.sh"))
    else . end |
    if .hooks.PermissionRequest == [] then del(.hooks.PermissionRequest) else . end |
    if .hooks == {} then del(.hooks) else . end
  ' "$SETTINGS_FILE")
  echo "$UPDATED" > "$SETTINGS_FILE"
  echo "    Removed hook from $SETTINGS_FILE"
fi

echo ""
echo "==> Done! Restart Claude Code for changes to take effect."

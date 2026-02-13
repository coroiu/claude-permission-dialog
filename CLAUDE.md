# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Install

Compile the Swift dialog and install both files to `~/.claude/hooks/`:
```bash
swiftc -O -o ~/.claude/hooks/permission-dialog src/PermissionDialog.swift -framework Cocoa
cp src/hook.sh ~/.claude/hooks/permission-dialog.sh && chmod +x ~/.claude/hooks/permission-dialog.sh
```

Or run `./install.sh` which also configures `~/.claude/settings.json`.

Dependencies: macOS, `jq`, Xcode Command Line Tools (`swiftc`).

## Architecture

This replaces Claude Code's terminal permission prompt with a native macOS floating dialog, using the **PermissionRequest** hook type.

**Data flow:** Claude Code → `hook.sh` (stdin JSON) → compiled `PermissionDialog` binary (stdin JSON) → binary prints decision to stdout → `hook.sh` wraps it in PermissionRequest response JSON → Claude Code reads stdout.

### hook.sh
- Receives `{tool_name, tool_input, cwd, permission_suggestions}` from Claude Code on stdin
- Formats human-readable `action` (short summary) and `detail` (full parameters) strings via `build_action()` / `build_detail()` tool-specific cases
- Passes `{tool_name, action, detail, cwd}` as JSON to the compiled binary
- Maps binary output (`allow`, `allow_always`, `deny`, `deny:<reason>`) to PermissionRequest hook response with `hookSpecificOutput.decision.behavior`
- For `allow_always`, passes through the native `permission_suggestions` array as `updatedPermissions`

### PermissionDialog.swift
- Single-file macOS Cocoa app, no external dependencies
- Uses `NSPanel` with `.nonactivatingPanel` — receives keyboard input without stealing focus from the terminal (like Spotlight)
- `KeyPanel` subclass overrides `canBecomeKey` to accept keyboard input
- `KeyHandlerView` handles arrow keys, Enter, Esc, and mouse clicks on option rows
- `PassthroughTextView` for the detail area prevents focus stealing
- Deny flow is two-step: selecting Deny shows a reason text field; Enter submits, Esc skips

## Hook Response Format

The PermissionRequest hook response must nest `behavior` inside a `decision` object:
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": []
    }
  }
}
```

**Not** directly in `hookSpecificOutput` — that was a previous bug.

## Testing

No automated tests. Manual testing workflow:
1. Compile and install (see above)
2. Ensure hook is configured in `~/.claude/settings.json` under `hooks.PermissionRequest`
3. Start a new Claude Code session (hooks are snapshotted at startup)
4. Trigger any tool that requires permission

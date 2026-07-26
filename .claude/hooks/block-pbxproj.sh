#!/bin/bash
# PreToolUse hook: Block agents from editing Xcode project files
# Exit code 2 blocks the tool call; stderr is fed back to Claude

path=$(jq -r '.tool_input.file_path // empty' < /dev/stdin)

case "$path" in
  *.pbxproj|*.xcodeproj/*)
    echo "BLOCKED: agents must not edit Xcode project files. Change project.yml instead." >&2
    exit 2
    ;;
esac

exit 0

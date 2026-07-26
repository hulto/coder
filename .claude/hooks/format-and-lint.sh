#!/bin/bash
# PostToolUse hook: Run format and lint checks after file edits
# This provides immediate feedback but doesn't block (exit 0 always)

path=$(jq -r '.tool_input.file_path // empty' < /dev/stdin)

# Only run on Swift files
if [[ "$path" != *.swift ]]; then
  exit 0
fi

# Extract module name from path (Modules/<ModuleName>/...)
module=$(echo "$path" | grep -oP 'Modules/\K[^/]+')

if [[ -z "$module" ]]; then
  exit 0
fi

# Run swift-format if available
if command -v swift-format &> /dev/null; then
  swift-format lint -s "$path" 2>&1 | head -20
fi

# Run swiftlint if available
if command -v swiftlint &> /dev/null; then
  swiftlint lint --quiet "$path" 2>&1 | head -20
fi

# Always exit 0 (informational only, not blocking)
exit 0

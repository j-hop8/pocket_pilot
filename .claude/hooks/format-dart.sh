#!/bin/bash
# PostToolUse hook: auto-format edited .dart files. Fail-soft — never blocks the edit.
f=$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' 2>/dev/null)
case "$f" in
  *.dart) command -v dart >/dev/null 2>&1 && dart format "$f" >/dev/null 2>&1 ;;
esac
exit 0

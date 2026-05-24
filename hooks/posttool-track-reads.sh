#!/usr/bin/env bash
# posttool-track-reads.sh — PostToolUse hook that records every Read tool call
# to a session-scoped log so PreToolUse validators can check "recently read".
#
# Spec: https://github.com/igorklimm/claude-code-memory-rails/blob/main/docs/architecture.md
# Log location: $XDG_RUNTIME_DIR/memory-rails/reads-<session>.log
#
# Hook input on stdin (Claude Code hook spec, PostToolUse):
#   { "tool_name": "Read", "tool_input": { "file_path": "..." },
#     "session_id": "...", "tool_result": { ... } }
#
# Always exits 0 — PostToolUse hooks must not block tool results.

set +e

if [ "${MEMORY_RAILS_ENABLED:-1}" = "0" ]; then
    exit 0
fi

INPUT_JSON=$(cat)

# Parse fields inline via node (no jq dependency assumption).
parse_field() {
    local field="$1"
    echo "$INPUT_JSON" | FIELD="$field" node -e '
(function() {
  try {
    const o = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const f = process.env.FIELD;
    if (f === "tool_name")  { process.stdout.write(o.tool_name || ""); return; }
    if (f === "session_id") { process.stdout.write(o.session_id || ""); return; }
    if (f === "file_path")  { process.stdout.write((o.tool_input || {}).file_path || ""); return; }
  } catch(e) { process.stdout.write(""); }
})();
' 2>/dev/null
}

TOOL_NAME=$(parse_field "tool_name")
[ "$TOOL_NAME" = "Read" ] || exit 0

SESSION_ID=$(parse_field "session_id")
FILE_PATH=$(parse_field "file_path")
[ -n "$FILE_PATH" ] || exit 0

# Ensure log dir exists on tmpfs (or fallback to /tmp).
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
LOG_DIR="$RUNTIME_DIR/memory-rails"
mkdir -p "$LOG_DIR" 2>/dev/null || true

# Session ID → safe filename (strip non-alphanumeric).
SAFE_SID=$(printf '%s' "${SESSION_ID:-unknown}" | tr -cd '[:alnum:]-_' | cut -c1-64)
LOG_FILE="$LOG_DIR/reads-${SAFE_SID}.log"

# Append: timestamp<TAB>file_path
printf '%s\t%s\n' "$(date -u +%s)" "$FILE_PATH" >> "$LOG_FILE" 2>/dev/null || true

exit 0

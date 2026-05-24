#!/usr/bin/env bash
# pretool-memory-deny.sh — PreToolUse DENY guard for Write/Edit/NotebookEdit
# on memory/** and wiki/** paths. Enforces chain-of-custody from memory-rails
# slash commands (/remember, /update-roadmap, /lesson, /research-summary).
#
# Origin: memory-rails v1 — deterministic write guard for memory/wiki.
# Ensures writes only happen via approved pipeline commands.
# Spec: docs/architecture.md (in this repo)
#
# Hook input on stdin (Claude Code hook spec):
#   { "tool_name": "Write|Edit|NotebookEdit",
#     "tool_input": { "file_path": "...", "content": "..." | "new_string": "..." },
#     "session_id": "...", ... }
#
# Exit codes:
#   0  = allow (tool proceeds)
#   2  = block (Claude reads stderr, must rewrite)
#   other = error (fail-open by design — bug in hook shouldn't brick the agent)

set +e

# --- gating: only fire when MEMORY_RAILS_ENABLED is set (canary) ---
# Default ON; opt-out via MEMORY_RAILS_ENABLED=0. During migration sessions,
# set MEMORY_RAILS_MIGRATE=1 to bypass (audit-logged below).
if [ "${MEMORY_RAILS_ENABLED:-1}" = "0" ]; then
    exit 0
fi

INPUT_JSON=$(cat)

# --- parse tool name + file_path + content via node ---
parse_field() {
    local field="$1"
    echo "$INPUT_JSON" | FIELD="$field" node -e '
(function() {
  try {
    const o = JSON.parse(require("fs").readFileSync(0, "utf8"));
    const field = process.env.FIELD;
    if (field === "tool_name") { process.stdout.write(o.tool_name || ""); return; }
    if (field === "session_id") { process.stdout.write(o.session_id || ""); return; }
    const ti = o.tool_input || {};
    if (field === "file_path") {
      process.stdout.write(String(ti.file_path || ti.notebook_path || ""));
      return;
    }
    if (field === "content") {
      // Write tool uses "content"; Edit uses old_string + new_string.
      // For Edit/NotebookEdit, hash the NEW state (new_string) as proxy.
      const c = ti.content || ti.new_string || ti.new_source || "";
      process.stdout.write(String(c));
      return;
    }
    process.stdout.write("");
  } catch(e) { process.stdout.write(""); }
})();
' 2>/dev/null
}

TOOL_NAME=$(parse_field "tool_name")
FILE_PATH=$(parse_field "file_path")
SESSION_ID=$(parse_field "session_id")

# Not a memory-write tool — fail-open.
case "$TOOL_NAME" in
    Write|Edit|NotebookEdit) ;;
    *) exit 0 ;;
esac

# Not a memory/wiki path — fail-open.
case "$FILE_PATH" in
    */memory/*|*/wiki/*) ;;
    *) exit 0 ;;
esac

# --- MIGRATE bypass: log to audit trail, then allow ---
# Every MEMORY_RAILS_MIGRATE=1 bypass
# of a memory/wiki Write MUST append to migrate-audit.log for forensics.
# Format: ISO8601\tagent_id\trun_id\ttarget_path  (tab-separated, append-only)
if [ "${MEMORY_RAILS_MIGRATE:-0}" = "1" ]; then
    SCRIPT_DIR_AUDIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    AUDIT_LOG="${SCRIPT_DIR_AUDIT}/../../scripts/memory-rails/migrate-audit.log"
    AUDIT_TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    AUDIT_AGENT="${PAPERCLIP_AGENT_ID:-unknown-agent}"
    AUDIT_RUN="${PAPERCLIP_RUN_ID:-unknown-run}"
    printf '%s\t%s\t%s\t%s\n' "$AUDIT_TS" "$AUDIT_AGENT" "$AUDIT_RUN" "$FILE_PATH" >> "$AUDIT_LOG" 2>/dev/null
    exit 0
fi

# --- whitelist: log.md + index.md appends from pipeline scripts ---
# Pipeline scripts use bash redirect/printf, NOT the LLM Write tool, so they
# don't trigger this hook. But if an LLM legitimately needs to edit these
# specific files, allow it (rare).
case "$FILE_PATH" in
    */wiki/log.md|*/wiki/index.md)
        # These files are pipeline-maintained but legitimate hand-edits are
        # allowed for repair. Log it for review but don't block.
        echo "[memory-rails] note: direct edit on $FILE_PATH (pipeline-maintained file) — allowed but review for drift" >&2
        exit 0
        ;;
esac

# --- chain-of-custody check ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTODY_LIB="${SCRIPT_DIR}/../../scripts/memory-rails/lib-custody.sh"
if [ ! -f "$CUSTODY_LIB" ]; then
    # Hook installed but lib missing — fail-open with warning to avoid bricking agent.
    echo "[memory-rails] WARN: lib-custody.sh missing at $CUSTODY_LIB — failing open" >&2
    exit 0
fi
# shellcheck disable=SC1090
source "$CUSTODY_LIB"

CONTENT=$(parse_field "content")
CONTENT_SHA=$(printf '%s' "$CONTENT" | custody_sha256_stdin)

if custody_validate_and_consume "$FILE_PATH" "$CONTENT_SHA" "$SESSION_ID"; then
    # Token matched + consumed. Allow.
    exit 0
fi

# --- DENY ---
cat >&2 <<EOF
❌ DENIED: direct $TOOL_NAME to $FILE_PATH

This file is governed by the memory-rails state-machine.
No valid custody token found for this Write (target + content hash + session).

Use one of these slash commands instead:
  /remember <fact>            → facts about entities (people, agents, systems)
  /update-roadmap <change>    → ROADMAP.md changes
  /lesson <text>              → project_lessons_log.md appends
  /research-summary <topic>   → research/ fetches

Why this exists: prevents silent overwrites of prior facts, ensures
index.md + log.md + cross-refs stay synced, enforces conflict-handling
per wiki-memory-standard.md (strikethrough-supersede on contradictions).

Emergency bypass (use sparingly):
  export MEMORY_RAILS_MIGRATE=1   # bulk migration sessions only
  export MEMORY_RAILS_ENABLED=0   # disable entirely (canary off)

Spec: https://github.com/igorklimm/claude-code-memory-rails/blob/main/docs/architecture.md
Origin: memory-rails v1 (2026-05-24).
EOF

exit 2

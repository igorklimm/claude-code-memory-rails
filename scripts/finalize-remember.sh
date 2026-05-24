#!/usr/bin/env bash
# finalize-remember.sh — post-Write steps 7-9 of /remember pipeline.
#
# Invoked by the LLM AFTER the Write tool succeeds with the custody-approved content.
# Args: $1 = target relative path, $2 = fact text.
#
# Steps:
#   7. Update wiki/index.md if a new page was created
#   8. Append wiki/log.md timeline entry
#   9. Re-read written file, confirm fact present (verification)

set -uo pipefail

TARGET_REL="$1"
FACT="$2"

WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
TARGET_ABS="$WORKSPACE/$TARGET_REL"

if [ ! -f "$TARGET_ABS" ]; then
    echo "❌ finalize-remember: target file does not exist: $TARGET_ABS" >&2
    echo "    Run /remember again — the Write step must have failed." >&2
    exit 1
fi

WIKI_DIR="$WORKSPACE/wiki"
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Step 7: update wiki/index.md (only if new page and wiki/ exists) ---
if [ -d "$WIKI_DIR" ]; then
    INDEX="$WIKI_DIR/index.md"
    INDEX_LINE="- [[$TARGET_REL]] — $FACT"
    if [ -f "$INDEX" ]; then
        if ! grep -qF "$TARGET_REL" "$INDEX" 2>/dev/null; then
            echo "$INDEX_LINE" >> "$INDEX"
            INDEX_TOUCHED="appended"
        else
            INDEX_TOUCHED="already present"
        fi
    else
        # Bootstrap index.md
        printf '# Wiki Index\n\n%s\n' "$INDEX_LINE" > "$INDEX"
        INDEX_TOUCHED="created"
    fi
else
    INDEX_TOUCHED="n/a (no wiki/ — legacy memory/ mode)"
fi

# --- Step 8: append wiki/log.md ---
if [ -d "$WIKI_DIR" ]; then
    LOG="$WIKI_DIR/log.md"
    LOG_ENTRY="## [$NOW_ISO] remember | $TARGET_REL — $FACT"
    if [ -f "$LOG" ]; then
        printf '\n%s\n' "$LOG_ENTRY" >> "$LOG"
    else
        printf '# Memory Log (append-only)\n\n%s\n' "$LOG_ENTRY" > "$LOG"
    fi
    LOG_TOUCHED="appended"
else
    LOG_TOUCHED="n/a"
fi

# --- Step 9: verify ---
VERIFY="unknown"
if grep -qF "$FACT" "$TARGET_ABS" 2>/dev/null; then
    VERIFY="✓ fact present"
else
    VERIFY="⚠ fact NOT found in target — verify manually"
fi

cat <<EOF
[memory-rails:/remember] finalized
  target:    $TARGET_REL
  index.md:  $INDEX_TOUCHED
  log.md:    $LOG_TOUCHED
  verify:    $VERIFY
EOF

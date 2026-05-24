#!/usr/bin/env bash
# pipeline-remember.sh — 8-step deterministic write pipeline for /remember.
#
# Invoked by ~/.claude/commands/remember.md slash command.
# Args: $@ = the fact text to remember.
#
# Pipeline:
#   1. Locate agent workspace (cwd or $CLAUDE_PROJECT_DIR)
#   2. Read wiki/CLAUDE.md schema (or fall back to memory-format-standard.md)
#   3. Classify fact → category
#   4. Find target file (existing match by slug, or new path)
#   5. Build proposed content (fact + frontmatter + cross-refs placeholder)
#   6. Emit custody token allowing the upcoming LLM Write
#   7. Print instructions for the LLM (which file to Write, what content)
#   8. After LLM Write completes, append wiki/log.md entry
#
# The actual file Write is done by the LLM (Claude) so PostToolUse hooks still fire.
# This script does NOT bash-write the wiki page directly — it issues custody and
# lets the LLM Write tool be the actual write surface. log.md append IS done here
# (bash, whitelisted in DENY hook).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-custody.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-classify.sh"

FACT="$*"
if [ -z "$FACT" ]; then
    echo "❌ /remember requires a fact. Usage: /remember <fact>" >&2
    exit 1
fi

# --- Step 1: locate workspace ---
WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
WIKI_DIR="$WORKSPACE/wiki"
MEMORY_DIR="$WORKSPACE/memory"

# Choose wiki/ if it exists, else fall back to memory/ (pre-migration agents)
if [ -d "$WIKI_DIR" ]; then
    BASE_DIR="$WIKI_DIR"
    USE_WIKI=1
elif [ -d "$MEMORY_DIR" ]; then
    BASE_DIR="$MEMORY_DIR"
    USE_WIKI=0
else
    echo "❌ no wiki/ or memory/ directory at $WORKSPACE — agent workspace missing memory layer" >&2
    exit 1
fi

# --- Step 2: read schema ---
SCHEMA_PATH=""
if [ -f "$BASE_DIR/CLAUDE.md" ]; then
    SCHEMA_PATH="$BASE_DIR/CLAUDE.md"
elif [ -f "${MEMORY_RAILS_INSTALL_DIR:-$(dirname "$0")/..}/wiki-memory-standard.md" ]; then
    SCHEMA_PATH="${MEMORY_RAILS_INSTALL_DIR:-$(dirname "$0")/..}/wiki-memory-standard.md"
fi

# --- Step 3: classify ---
CATEGORY=$(classify_fact "$FACT")
SLUG=$(slug_for_fact "$FACT")
TODAY=$(date -u +%Y-%m-%d)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Step 4: find target file ---
TARGET_REL=""
if [ "$USE_WIKI" = "1" ]; then
    CATEGORY_DIR="$BASE_DIR/$CATEGORY"
    mkdir -p "$CATEGORY_DIR" 2>/dev/null
    # Look for existing page matching first 2 slug tokens
    FIRST_TOKENS=$(echo "$SLUG" | cut -d- -f1-2)
    EXISTING=$(find "$CATEGORY_DIR" -maxdepth 1 -name "*${FIRST_TOKENS}*.md" -type f 2>/dev/null | head -1)
    if [ -n "$EXISTING" ]; then
        TARGET_REL="${EXISTING#$WORKSPACE/}"
        MODE="append"
    else
        TARGET_REL="wiki/$CATEGORY/$SLUG.md"
        MODE="create"
    fi
else
    # Legacy memory/ — append to lessons_log or write user-fact file
    TARGET_REL="memory/project_lessons_log.md"
    MODE="append"
fi

TARGET_ABS="$WORKSPACE/$TARGET_REL"

# --- Step 5: build proposed content ---
if [ "$MODE" = "create" ]; then
    NEW_CONTENT=$(cat <<EOF
---
title: $FACT
last_updated: $TODAY
tags: [$CATEGORY]
---

# $FACT

## Summary
$FACT

## Details
_Recorded $NOW_ISO via /remember pipeline._

## Cross-refs
- [[wiki/index]]

## Sources
- /remember invocation $NOW_ISO
EOF
)
else
    # Append-mode: add a dated note under "## Updates" section
    NEW_CONTENT=$(cat <<EOF

## Update $NOW_ISO
$FACT

_Appended via /remember pipeline._
EOF
)
fi

# --- Step 6: emit custody token ---
CONTENT_SHA=$(printf '%s' "$NEW_CONTENT" | custody_sha256_stdin)
TOKEN_PATH=$(custody_issue "$TARGET_ABS" "$CONTENT_SHA" "remember")

# --- Step 7: print LLM instructions ---
cat <<EOF
[memory-rails:/remember] custody issued (expires in ${MEMORY_RAILS_TOKEN_TTL_SEC}s)

Pipeline state:
  category:  $CATEGORY
  mode:      $MODE
  target:    $TARGET_REL
  schema:    ${SCHEMA_PATH:-<none — use defaults>}
  token:     $TOKEN_PATH

Next action (LLM): use the Write tool with EXACTLY this content to EXACTLY this path.
The PreToolUse DENY hook will validate the custody token and allow this single Write.
After the Write succeeds, run: bash ${MEMORY_RAILS_SCRIPTS_DIR:-$(dirname "$0")}/finalize-remember.sh "$TARGET_REL" "$FACT"

  Write file_path: $TARGET_ABS
  Write content:
----- BEGIN CONTENT -----
$NEW_CONTENT
----- END CONTENT -----
EOF

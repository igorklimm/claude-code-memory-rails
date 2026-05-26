#!/usr/bin/env bash
# pipeline-update-roadmap.sh — deterministic write pipeline for /update-roadmap.
#
# Invoked by ~/.claude/commands/update-roadmap.md slash command.
# Args: $@ = the change description (with optional owner-voice citation (e.g. «voice 3447»)).
#
# Target: wiki/decisions/current-wave.md (if wiki/ exists) or memory/ROADMAP.md
# Pipeline mirrors pipeline-remember.sh steps 1-7.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib-custody.sh"

CHANGE="$*"
if [ -z "$CHANGE" ]; then
    echo "❌ /update-roadmap requires a change description. Usage: /update-roadmap <change>" >&2
    exit 1
fi

# --- Step 1: locate workspace ---
WORKSPACE="${CLAUDE_PROJECT_DIR:-$PWD}"
WIKI_DIR="$WORKSPACE/wiki"
MEMORY_DIR="$WORKSPACE/memory"

TODAY=$(date -u +%Y-%m-%d)
NOW_ISO=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# --- Step 2: determine target ---
if [ -d "$WIKI_DIR" ]; then
    TARGET_REL="wiki/decisions/current-wave.md"
    mkdir -p "$WIKI_DIR/decisions" 2>/dev/null
elif [ -d "$MEMORY_DIR" ]; then
    TARGET_REL="memory/ROADMAP.md"
else
    echo "❌ no wiki/ or memory/ at $WORKSPACE" >&2
    exit 1
fi

TARGET_ABS="$WORKSPACE/$TARGET_REL"

# --- Step 3: extract voice citation if present ---
CITATION=""
if echo "$CHANGE" | grep -qiE 'voice [0-9]+'; then
    CITATION=$(echo "$CHANGE" | grep -oiE 'voice [0-9]+' | head -1)
fi

# --- Step 4: build append content ---
CITE_LINE=""
if [ -n "$CITATION" ]; then
    CITE_LINE="  _Source: ${CITATION}, ${TODAY}_"
fi

NEW_CONTENT=$(cat <<EOF

## [$TODAY] Roadmap change
$CHANGE
$CITE_LINE
_Recorded $NOW_ISO via /update-roadmap pipeline._
EOF
)

# If target doesn't exist yet, create with header
if [ ! -f "$TARGET_ABS" ]; then
    NEW_CONTENT=$(cat <<EOF
# Current Wave Roadmap
_Append-only. Each entry dated. Source: /update-roadmap pipeline._

## [$TODAY] Roadmap change
$CHANGE
$CITE_LINE
_Recorded $NOW_ISO via /update-roadmap pipeline._
EOF
)
fi

# --- Step 5: emit custody token ---
CONTENT_SHA=$(printf '%s' "$NEW_CONTENT" | custody_sha256_stdin)
TOKEN_PATH=$(custody_issue "$TARGET_ABS" "$CONTENT_SHA" "update-roadmap")

# --- Step 6: print LLM instructions ---
cat <<EOF
[memory-rails:/update-roadmap] custody issued (expires in ${MEMORY_RAILS_TOKEN_TTL_SEC}s)

Pipeline state:
  target:    $TARGET_REL
  citation:  ${CITATION:-<none>}
  token:     $TOKEN_PATH

Next action (LLM): use the Write tool (append mode if file exists) with EXACTLY this content to EXACTLY this path.
The PreToolUse DENY hook will validate the custody token and allow this single Write.
After the Write succeeds, run: bash ${MEMORY_RAILS_SCRIPTS_DIR:-$(dirname "$0")}/finalize-update-roadmap.sh "$TARGET_REL" "$CHANGE"

  Write file_path: $TARGET_ABS
  Write content (APPEND to existing file, or create if missing):
----- BEGIN CONTENT -----
$NEW_CONTENT
----- END CONTENT -----
EOF

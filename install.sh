#!/usr/bin/env bash
# install.sh — plug-and-play installer for claude-code-memory-rails
#
# Usage:
#   bash install.sh [--workspace <path>] [--claude-dir <path>]
#
# Defaults:
#   --workspace   $PWD  (your agent workspace — where wiki/ will live)
#   --claude-dir  ~/.claude

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="${MEMORY_RAILS_WORKSPACE:-$PWD}"
CLAUDE_DIR="${MEMORY_RAILS_CLAUDE_DIR:-$HOME/.claude}"

# --- parse args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --claude-dir) CLAUDE_DIR="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

SCRIPTS_DIR="$REPO_DIR/scripts"
HOOKS_DIR="$REPO_DIR/hooks"
COMMANDS_DIR="$REPO_DIR/commands"

echo "=== claude-code-memory-rails install ==="
echo "  repo:      $REPO_DIR"
echo "  workspace: $WORKSPACE"
echo "  claude:    $CLAUDE_DIR"
echo

# --- 1. Install slash commands ---
CLAUDE_COMMANDS="$CLAUDE_DIR/commands"
mkdir -p "$CLAUDE_COMMANDS"

# Render remember.md with the concrete scripts path baked in
sed "s|\${MEMORY_RAILS_SCRIPTS_DIR}|$SCRIPTS_DIR|g" \
    "$COMMANDS_DIR/remember.md" > "$CLAUDE_COMMANDS/remember.md"

echo "✓ slash command: $CLAUDE_COMMANDS/remember.md"

# --- 2. Print settings.json hook block ---
cat <<SETTINGS

=== Add the following hooks to your Claude Code settings.json ===
(~/.claude/settings.json  or  <workspace>/.claude/settings.json)

  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOKS_DIR/pretool-memory-deny.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "bash $HOOKS_DIR/posttool-track-reads.sh"
          }
        ]
      }
    ]
  }

SETTINGS

# --- 3. Bootstrap wiki/ in workspace ---
WIKI_DIR="$WORKSPACE/wiki"
if [ ! -d "$WIKI_DIR" ]; then
    mkdir -p "$WIKI_DIR"/{agents,infrastructure,decisions,people,business,research,misc}
    cat > "$WIKI_DIR/CLAUDE.md" <<'WIKI_SCHEMA'
# Wiki Schema

This is the agent memory wiki. Facts are stored in categorized markdown pages.
Use `/remember <fact>` to write — direct edits are blocked by the memory-rails DENY hook.

## Categories
- `agents/`     — known agents, roles, capabilities
- `people/`     — human contacts, users, stakeholders
- `infrastructure/` — systems, deployments, servers
- `decisions/`  — mandates, pivots, lessons
- `business/`   — strategy, pricing, clients
- `research/`   — digested summaries of external sources
- `misc/`       — anything else

## Operations
- `index.md`   — live catalog, auto-maintained by pipeline
- `log.md`     — append-only audit trail of all writes
WIKI_SCHEMA
    echo "✓ bootstrapped wiki/ at $WIKI_DIR"
else
    echo "✓ wiki/ already exists at $WIKI_DIR — skipping bootstrap"
fi

echo
echo "=== Install complete ==="
echo "  Run /remember <fact> in Claude Code to test."
echo "  Set MEMORY_RAILS_ENABLED=0 to temporarily disable the DENY hook."

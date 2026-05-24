# claude-code-memory-rails

> A deterministic state-machine that stops Claude Code agents from forgetting — and from silently corrupting what they already know.

[![CI](https://github.com/igorklimm/claude-code-memory-rails/actions/workflows/ci.yml/badge.svg)](https://github.com/igorklimm/claude-code-memory-rails/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## Why

Andrej Karpathy published a [canonical note on LLM memory](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) in April 2026:

> "The solution I've found most elegant is to have the LLM maintain its own wiki... The LLM is the author and the reader of its own long-term memory."

The pattern works — but it breaks in practice for two reasons:

1. **Context overflow forgets.** After enough tokens, the agent no longer "sees" its own memory files. It repeats stale facts to users.
2. **Direct writes corrupt.** When the agent decides to write a memory, it opens the file and overwrites it — silently blowing away older facts instead of updating them correctly.

Standard hooks (PostToolUse reminders, SessionStart auto-loads) are **advisory**. The agent reads them but can skip them. Three failure modes we observed in production:

| Failure | Symptom |
|---------|---------|
| Stale-citation | Agent recalls a fact from 6 days ago, doesn't re-read, repeats it to user |
| Silent overwrite | Direct `Write` on `wiki/foo.md` deletes older content |
| Index drift | New page written but never added to `wiki/index.md` |

**memory-rails** fixes all three by making the default path the safe path: the only way to write memory is through a guided pipeline that handles indexing, conflict detection, and audit logs deterministically. Direct writes are denied with a helpful message.

---

## How it works

```
User says "remember X"  /  agent decides "I should record X"
                              │
                              ▼
              ┌─────────────────────────────┐
              │  /remember <fact>           │  ← slash command
              └──────────────┬──────────────┘
                             │  8-step deterministic pipeline
                             ▼
              ┌──────────────────────────────┐
              │ pipeline-remember.sh         │
              │  1. locate workspace         │
              │  2. read wiki schema         │
              │  3. classify fact → category │
              │  4. find/create target file  │
              │  5. build proposed content   │
              │  6. emit custody token       │
              │  7. LLM does Write ──────────┼──► PreToolUse check:
              │  8. update index.md          │    custody token valid?
              │  9. append log.md + verify   │    ✓ allow / ✗ DENY exit 2
              └──────────────────────────────┘

Direct Write/Edit on wiki/** or memory/**
──────────────────────────────────► DENY hook → exit 2
                                    stderr: "use /remember"
```

**Key components:**

| File | Role |
|------|------|
| `scripts/pipeline-remember.sh` | 8-step write pipeline for facts |
| `scripts/pipeline-update-roadmap.sh` | Write pipeline for decisions/roadmap changes |
| `scripts/lib-custody.sh` | Chain-of-custody tokens (60s TTL, single-use) |
| `scripts/lib-classify.sh` | Keyword heuristics → wiki category |
| `scripts/finalize-remember.sh` | Post-write: update index, append log, verify |
| `hooks/pretool-memory-deny.sh` | PreToolUse DENY guard |
| `hooks/posttool-track-reads.sh` | PostToolUse read tracker (for freshness gates) |
| `commands/remember.md` | Claude Code `/remember` slash command |

**Architecture diagram:** [`docs/architecture.md`](docs/architecture.md)

---

## Install

**Prerequisites:** `bash`, `node` (for JSON parsing), `sha256sum` or `shasum`.

```bash
git clone https://github.com/igorklimm/claude-code-memory-rails.git
cd claude-code-memory-rails

# Install to current workspace (defaults to $PWD) + ~/.claude
bash install.sh

# Or specify paths explicitly
bash install.sh --workspace /path/to/agent/workspace --claude-dir ~/.claude
```

The installer:
1. Copies the `/remember` slash command into `~/.claude/commands/remember.md` with the correct `scripts/` path baked in
2. Prints the `hooks` block to add to your `settings.json`
3. Bootstraps `wiki/` directory structure in your workspace

**Add hooks to `~/.claude/settings.json`** (the installer prints this):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/claude-code-memory-rails/hooks/pretool-memory-deny.sh"
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
            "command": "bash /path/to/claude-code-memory-rails/hooks/posttool-track-reads.sh"
          }
        ]
      }
    ]
  }
}
```

**Test the install:**

```
# In Claude Code, type:
/remember My project uses PostgreSQL 16 on port 5432
```

You should see the pipeline classify → propose → write → finalize in one step.

---

## Token cost

The pipeline adds overhead on every memory write. Measured on Claude Sonnet 4.6:

| Operation | Extra tokens | Notes |
|-----------|-------------|-------|
| `/remember <fact>` | ~200 input | pipeline output read by model |
| DENY hook block | ~80 input | stderr message redirecting to `/remember` |
| Custody token check | 0 | pure bash/node, no LLM call |

**Savings** from avoiding stale-citation failures: each recovered context (agent re-reads a correct fact instead of asserting a wrong one) saves the full cost of a correction loop, typically 2–5k tokens + human round-trip.

Net: the overhead is negligible against the cost of even one stale-citation correction.

---

## Fail-fast disable

| Env var | Default | Effect |
|---------|---------|--------|
| `MEMORY_RAILS_ENABLED` | `1` | Set to `0` to fully disable DENY hook (fail-open) |
| `MEMORY_RAILS_MIGRATE` | `0` | Set to `1` to bypass DENY during migration sessions |

```bash
# Temporarily disable (e.g. bulk migration):
MEMORY_RAILS_MIGRATE=1 claude

# Fully disable DENY hook:
MEMORY_RAILS_ENABLED=0 claude
```

---

## Wiki layout

The pipeline writes into a structured `wiki/` directory inside your agent workspace:

```
<workspace>/
  wiki/
    CLAUDE.md            # schema — how this wiki works
    index.md             # live catalog, auto-maintained
    log.md               # append-only audit trail
    agents/              # known agents/systems
    people/              # human contacts
    infrastructure/      # servers, deployments, tools
    decisions/           # mandates, pivots, lessons
    business/            # strategy, pricing
    research/            # digested external sources
    misc/                # anything else
```

---

## Extending

**Add a new write command** (e.g. `/lesson`):

1. Copy `scripts/pipeline-remember.sh` → `scripts/pipeline-lesson.sh`
2. Change the target directory logic to `wiki/decisions/lessons/`
3. Create `commands/lesson.md` following the same template as `commands/remember.md`
4. Update `install.sh` to symlink the new command

**Custom categories:** edit `scripts/lib-classify.sh` — it's pure bash keyword matching, no ML.

---

## Contributing

PRs welcome. Run `shellcheck scripts/*.sh hooks/*.sh` before submitting. CI must pass.

---

## License

MIT — see [LICENSE](LICENSE).

---

*Inspired by [Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f). Built for [Claude Code](https://claude.ai/code) hook architecture.*

# Architecture: memory-rails state-machine

**Version:** v1 (2026-05-24)

---

## Problem

Claude Code agents write to their own memory files. Without guardrails, three failure modes emerge:

1. **Stale-citation** — agent recalls a fact from a prior session, doesn't re-read, repeats outdated information.
2. **Silent overwrite** — agent does `Write` on `wiki/foo.md`, blowing away older facts instead of strikethrough-supersede.
3. **Index drift** — new page written but never added to `wiki/index.md`; unreachable by future reads.

Advisory hooks (PostToolUse reminders, SessionStart prompts) don't solve this — the agent reads them but can skip them.

---

## Solution: deterministic chain-of-custody

Every memory write must pass through an approved pipeline that issues a **single-use, 60-second custody token** before the Claude `Write` tool fires. The PreToolUse hook validates this token and blocks any write that doesn't have one.

```
pipeline-remember.sh
  ├── classify fact → category (lib-classify.sh)
  ├── find/create target file
  ├── build proposed content
  ├── custody_issue() → /tmp/memory-rails/custody-<session>-<sha>.tok
  └── print instructions + BEGIN/END CONTENT block

Claude Code LLM
  └── Write tool call → file_path + content
          │
          ▼
  PreToolUse hook: pretool-memory-deny.sh
          │
          ├── file_path matches wiki/** or memory/**?
          │   no  → allow (not a memory write)
          │   yes → compute sha256(content)
          │         custody_validate_and_consume(path, sha, session)
          │         ✓ found + fresh → allow
          │         ✗ missing/expired → exit 2 (DENY)

finalize-remember.sh
  ├── update wiki/index.md (if new page)
  ├── append wiki/log.md
  └── verify: grep fact in written file
```

---

## Custody token format

Tokens live in `$XDG_RUNTIME_DIR/memory-rails/` (tmpfs, 700 permissions):

```json
{
  "target": "wiki/misc/postgres-config.md",
  "content_sha256": "a3f8b2...",
  "expires_at": 1716544800,
  "pipeline": "remember",
  "ts": 1716544740
}
```

- Single-use: consumed (deleted) on successful validation
- 60-second TTL: prevents token accumulation from aborted runs
- SHA256 binding: token is tied to the exact content emitted by the pipeline — any modification triggers re-classification and re-issue

---

## Wiki structure

```
wiki/
  CLAUDE.md          # schema
  index.md           # live catalog
  log.md             # append-only audit trail
  agents/
  people/
  infrastructure/
  decisions/
    lessons/
  business/
  research/
  misc/
```

**`index.md`** — one `[[wiki-link]]` per page, auto-maintained by `finalize-remember.sh`.
**`log.md`** — append-only, format: `## [ISO8601] <command> | <target> — <fact>`.

---

## Env vars

| Variable | Default | Purpose |
|----------|---------|---------|
| `MEMORY_RAILS_ENABLED` | `1` | `0` disables DENY hook entirely (fail-open) |
| `MEMORY_RAILS_MIGRATE` | `0` | `1` bypasses DENY (bulk migration sessions) |
| `MEMORY_RAILS_CUSTODY_DIR` | `$XDG_RUNTIME_DIR/memory-rails` | Token directory |
| `MEMORY_RAILS_TOKEN_TTL_SEC` | `60` | Token lifetime in seconds |
| `MEMORY_RAILS_SCRIPTS_DIR` | auto | Path to `scripts/` — baked in by installer |
| `CLAUDE_PROJECT_DIR` | `$PWD` | Agent workspace root (where `wiki/` lives) |

---

## Dependencies

- `bash` ≥ 4
- `node` ≥ 16 (for JSON parsing in hooks and custody validation — avoids `jq` dependency)
- `sha256sum` (coreutils) or `shasum` (macOS)
- Claude Code ≥ any version supporting PreToolUse/PostToolUse hooks

---

## Failure modes and mitigations

| Failure | Mitigation |
|---------|-----------|
| Token directory missing | `custody_dir_ensure()` creates it on every call |
| Node not available | `pretool-memory-deny.sh` uses `set +e` + exits 0 on parse error (fail-open) |
| Token expired (slow LLM) | Re-run `/remember` — fresh token issued |
| Concurrent writes same file | Each pipeline call gets unique token keyed on content SHA |
| `MEMORY_RAILS_ENABLED=0` | Full fail-open — document in runbooks |

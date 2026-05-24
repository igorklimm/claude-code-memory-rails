# Wiki Memory Standard

**Origin:** Иги voice mandates 3335+3337+3340+3344+3345+3347 (2026-05-24).
**Source pattern:** [Karpathy LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) (2026-04-04, 17M views).
**Pilot trigger:** John mandate (archived inter-agent msg `d8c9cf84`) + spec `[internal spec]
**Authored by:** Mechanic-Agents 2026-05-24.
**Status:** Draft v1 — pilot on John (VPS Tier 1) + Mechanic Главный (Comp Tier 2), then fleet rollout.
**Scope:** ALL 21+ fleet agents (Tier 1/2/3, Claude Code + Codex CLI).

---

## TL;DR

Replace scattered `memory/*.md` + manual `MEMORY.md` index with structured `wiki/` layer maintained by LLM hooks. Per-agent: raw sources in `raw/`, digested entity pages in `wiki/`, live `index.md`, append-only `log.md`. Three operations (ingest / query / lint) per Karpathy canonical. Graphiti can serve as an optional cross-agent shared layer. The wiki/ layer is Obsidian-compatible (human-readable filenames, [[wiki-links]]).

Layout, hooks, conflict handling, sync prereq, migration playbook — all defined below.

---

## Goals (Иги mandate)

1. **Stop forgetting after context overflow.** Replace ~50 disjoint .md files + Graphiti queries with pre-digested wiki pages.
2. **Иги-readable in Obsidian** — folder structure intuitive, human-readable filenames, `[[wiki-links]]` clickable, minimal frontmatter (no JSON/hashes visible).
3. **Automatic via hooks** — Иги explicit «главное чтобы автоматом срабатывало, как hook».
4. **Fleet-shareable through Graphiti** — wiki = per-agent local layer, Graphiti = cross-agent shared.
5. **Per-tenant ready** — when CRM-tenant-agents arrive, each customer has its own wiki/ instance.

---

## Canonical per-agent layout

```
<agent-workspace>/
  wiki/
    CLAUDE.md            # schema: how this agent's wiki works
    index.md             # live catalog — LLM-maintained on every ingest
    log.md               # append-only `## [YYYY-MM-DD HH:MM] action | page` timeline
    agents/              # one page per known agent (role, status, recent activity)
      john.md
      mechanic.md
      iggy-team.md       # collective fleet roster overview
    crm/                 # CRM-related decisions, workflows, design choices
      workflow-decisions.md
      tenant-pattern.md
    infrastructure/      # AMP, hooks, Tailscale, sync, deploy
      amp-shutdown.md
      tailscale-sync.md
    decisions/           # major Иги mandates with date + context
      2026-05-24-karpathy-wiki-pivot.md
      lessons/           # collapsed thematic lessons (NOT one-per-mistake)
        api-key-discipline.md
        no-paid-default.md
    people/              # Иги profile, contractors, vendor contacts
      iggy.md
    business/            # B2B strategy, NeuroTeam goals, pricing
      neuroteam-b2b-goals.md
    research/            # digested research summaries (NOT raw fetches)
      karpathy-llm-wiki.md
    clients/             # per-tenant CRM wiki (when CRM-tenant agents arrive)
      <customer-slug>/
        CLAUDE.md
        workflows.md
        decisions.md
  raw/                   # immutable fetched content (sources of truth)
    2026-05-24-karpathy-gist.md
    2026-05-24-mindstudio-pattern-blog.md
    transcripts/
      2026-05-23-iggy-voice-NNNN.md
  memory/                # LEGACY — kept read-only during migration window
    MEMORY.md
    feedback_*.md
    project_*.md
    project_status_matrix.md   # migrates to wiki/decisions/current-wave.md
    project_lessons_log.md     # migrates to wiki/decisions/lessons/
```

**Folder hard-rule:** every folder name lowercase kebab-case (Obsidian friendly), no underscores, no UUIDs in paths.

---

## Three operations (Karpathy canonical)

### Ingest
New source arrives (research fetch, conversation, fact, Иги voice transcript) → agent:
1. Drops immutable content in `raw/YYYY-MM-DD-<slug>.md` (frontmatter: title, source-url-if-any, date)
2. Touches 5-15 related `wiki/` pages with digested facts (entity-by-entity fan-out)
3. Adds `[[wiki-links]]` to cross-reference related pages
4. Refreshes `wiki/index.md` if new page created
5. Appends single entry to `wiki/log.md`: `## [2026-05-24 02:30Z] ingest | <slug>`

### Query (anti-confabulation discipline — Иги voice 1849 2026-05-24)

Иги asks question OR agent needs fact:
1. **Search `wiki/` first** (NOT `raw/`) — wiki is digested, fast, scoped
2. If found → answer with `[[wiki-link]]` citations
3. If wiki incomplete → search `raw/` for source, synthesize, **file new wiki page back** (compounding)
4. If cross-agent fact needed → `mcp__graphiti__search_*` (Graphiti stays as fleet-wide layer)
5. **If NOT found in wiki + raw + Graphiti → say «не знаю» / «нет в моей памяти, нужно уточнить».** DO NOT guess from training data. Anti-naugad hard rule (Иги voice 1849: «у себя не нашёл — значит нету»).

Hard rule for agent self-discipline: **before any factual claim** in conversation, agent runs internal check «искал ли я это в wiki?». If no — search first OR caveat «без проверки в wiki, исходя из общего понимания: ...».

### Lint
Periodic (hook-driven) automated check:
- Pages not updated > 30 days
- Pages with zero inbound `[[links]]` (orphans)
- Contradicting timestamps between pages
- `log.md` last entry > 7 days (memory stagnation)
- Frontmatter completeness

Output: digest report; agent decides merge / archive / leave.

---

## CLAUDE.md schema (per agent wiki/)

Single source of truth for "how memory works HERE". Replaces scattered @imports of `memory-format-standard.md` / `anthropic-memory-plan.md` / `inbox-triage-rule.md` for the wiki layer.

**Required sections:**

1. **Naming conventions** — kebab-case, descriptive, no abbreviations Иги wouldn't understand
2. **Templates** (5 page types: agent / decision / research / project / lesson):

   ```markdown
   ---
   title: <human-readable title>
   last_updated: 2026-05-24
   tags: [<obsidian-native-tag>, <tag>]
   ---

   # <title>

   ## Summary
   <2-3 sentences plain Russian>

   ## Details
   <markdown body>

   ## Cross-refs
   - [[wiki/agents/john]] — связан через ...
   - [[wiki/decisions/2026-05-23-XX]] — последствие ...

   ## Sources
   - raw/2026-05-24-source.md
   - Graphiti: source_description=<who>, episode_uuid=<uuid> (если был add_memory)
   ```

3. **Conflict handling** (CRITICAL):
   - When new fact contradicts existing page → NEVER silently overwrite
   - Mark old fact with `~~strikethrough~~`
   - Add inline annotation: `(superseded 2026-05-24: see [[new-page]])`
   - Append to log.md: `## [<ts>] supersede | <page> — old <X> → new <Y>`
   - This preserves audit trail (ASI03 memory poisoning mitigation)

4. **Frontmatter required fields:** `title`, `last_updated`, `tags` (max 5, Obsidian-native syntax)

5. **How to update index.md** — single line per page: `- [[wiki/decisions/2026-05-24-karpathy-wiki-pivot]] — Иги mandate to rewrite memory model`

6. **How to write log.md entries** — append-only, newest at bottom OR top (decide per agent, document choice in CLAUDE.md)

7. **Graphiti fan-out rule** — write `add_memory` to Graphiti ONLY when fact is:
   - Cross-agent (other agents need to know)
   - Temporally significant (decision with deadline / vendor relationship / Иги mandate affecting > 1 agent)
   - Append `source_description=<agent-slug>` mandatory (ASI03 attribution)

   **NOT** auto-hooked — manual decision per ingest (avoid cascade poisoning).

---

## Hook design

### Hook 1 — PostToolUse `wiki-fan-out-prompt`

**Matcher:** `Write|Edit` where target path matches `raw/**` or `docs/research/**`

**Action:** stderr prompt:
```
[wiki-update] New raw source written: <path>
Review wiki/index.md and touch 5-15 related pages with digested facts.
Then append wiki/log.md with `## [<ts>] ingest | <slug>`.
```

Agent reads prompt next tool call, performs fan-out within same session.

**Implementation:** `_fleet-standards/hooks/wiki-fan-out-prompt.sh` (bash, portable Comp/Linux).

### Hook 2 — SessionStart `wiki-load-pointers`

Replace current `MEMORY.md` auto-load with pointers (per AMP discipline 2 KB STDOUT cap):

```
[OBLIGATORY READING — wiki layer]
1. wiki/CLAUDE.md (XXX bytes, YY lines) — schema for this agent's wiki
2. wiki/index.md (XXX bytes, YY lines) — what pages exist
3. wiki/log.md (tail 50 lines) — recent activity
4. memory/project_status_matrix.md (legacy, during migration) — current Wave
5. memory/project_lessons_log.md (legacy, during migration) — recent lessons
```

Agent reads via `Read` tool (no 2 KB cap).

**Implementation:** `_fleet-standards/hooks/wiki-load-pointers.sh`.

**Migration period:** both old `MEMORY.md` auto-load + new wiki pointers active in parallel. After pilot validation → kill old auto-load.

### Hook 3 — Stop `wiki-lint-check`

Runs `_fleet-standards/scripts/wiki-lint.sh` every Nth session-end (e.g. every 10th, gated by counter file). Emits warnings if:
- Stale pages (> 30 days no updates)
- Orphan pages (zero inbound `[[links]]`)
- Contradicting timestamps
- log.md last entry > 7 days

Non-blocking — informational digest.

### Hook 4 — Anthropic Routine `wiki-deep-lint-weekly`

Sunday 03:00 UTC (deferred to Главного scheduler). Full wiki/ scan, generates drift report. Posts a Paperclip Issue assigned to each agent owner (John for John's wiki, Mechanic for Mechanic's, etc.).

### Hook 5 — AMP-shutdown wiki extension (Иги voice 1849 2026-05-24 «в АМП-шатдаун встроить»)

When AMP-shutdown triggers (RED threshold OR manual `/amp-shutdown`), in addition to current handoff:
- Agent scans current session transcript for new entities/facts/decisions discussed
- Auto-appends to `wiki/log.md`: `## [<ts>] amp-shutdown-snapshot | <agent-name> | session_id=<id>`
- Lists candidate wiki pages to touch (NOT auto-writes — manual review next session)
- Marks in `wiki/index.md` queue: `<!-- shutdown-queue: fan-out N candidate pages from session X -->`

Next session SessionStart hook reads queue → prompts agent: «previous shutdown left N candidates, review now».

This closes Иги's «как я должен постоянно говорить чтобы записывалось?» — answer: **not at all**. Hooks catch session-end auto, agent reviews on next session start. Иги в loop ТОЛЬКО когда explicit mandate (voice / Telegram message).

**Implementation:** extends existing `skills/auto-amp-shutdown/save-state.sh` with wiki-snapshot append step. Mechanic-Agents owns hook code, deploys after standard ack.

---

## Open questions resolved (per John spec sec 285)

1. **Code in Obsidian?** — **docs/specs/decisions → wiki/, raw source code (.ts/.py/.go) stays in git.** Иги voice 3344 «весь код, вся CRM» interpreted as docs/specs/architecture, not raw files. Confirm with Иги if пересмотрит.

2. **Per-tenant CRM wiki structure** — `wiki/clients/<customer-slug>/` per customer. Customer-CRM-Mechanic agent owns per-tenant wiki population. Tenant-isolation: agent reads ONLY its own tenant's wiki.

3. **Graphiti↔wiki sync** — **manual `add_memory` decision per ingest**. NOT auto-hooked. Reason: ASI03 cascade poisoning risk if wiki fan-out auto-pushes to Graphiti without attribution review. Agent uses Karpathy rule «cross-agent fact?» → if yes, manually call `add_memory(source_description=<agent>, group=neuroteam_b2b)`.

4. **status_matrix / lessons_log fate** — **migrate into wiki/** during pilot:
   - `project_status_matrix.md` → `wiki/decisions/current-wave.md` (mutable)
   - `project_lessons_log.md` → `wiki/decisions/lessons/` (one page per thematic lesson, NOT one per entry)
   - Legacy files kept read-only with header `> MIGRATED to [[wiki/...]] on 2026-05-XX`
   - Wave-end ritual updates `wiki/decisions/current-wave.md` per [`memory-format-standard.md`](memory-format-standard.md) protocol — unchanged

5. **CLAUDE.md fleet-standard imports** — **root `CLAUDE.md` keeps agent identity** (SOUL/USER/IDENTITY/RULE_OF_TWO/AGENTS/TOOLS/MY_AUTHORITY) + fleet-standards @imports. **NEW: `wiki/CLAUDE.md`** owns wiki-specific schema (per-workspace, may diverge per agent role — e.g. Designer-Codex wiki vs Coder-Codex wiki). Compromise: 2 CLAUDE.md per agent (root + wiki/). Karpathy single-CLAUDE pure form sacrificed for fleet-standards-import compatibility.

6. **Lint script implementation** — **bash**, location `_fleet-standards/scripts/wiki-lint.sh`. Portable Comp (Git Bash) + Linux. Falls back to `python3` for JSON parsing if jq unavailable.

7. **/wiki-ingest slash command** — **yes ship**. Location `~/.claude/commands/wiki-ingest.md` (user scope, fleet-wide). Args: source URL or path. Action: fetch → write raw/, prompt agent for fan-out. Karpathy parity.

---

## Sync prereq (BLOCKER — Mechanic Главный zone)

Wiki pattern requires bidirectional Comp ↔ VPS sync so Иги Obsidian (Comp) reads VPS-side agents' wikis AND VPS agents read Comp-side agents' wikis.

**Current state (per John spec sec 74-87):**
- Tailscale mesh works (`100.92.0.42` VPS reachable)
- Auto-snapshot git every 15 min on VPS (local only)
- No cross-host filesystem mount

**Recommended approach (Mechanic decides):**
1. **Syncthing** — P2P, real-time, native Obsidian community support — **first choice**
2. rsync over Tailscale + cron (60s lag fallback)
3. Git as transport (slower but reliable)
4. SMB share (fragile on Windows)

Mechanic Главный owns sync layer implementation. Pilot **blocked** until done.

---

## Migration playbook (generic per agent)

### Phase 0: Sync prereq verified (Mechanic owns, fleet-wide BLOCKER)

### Phase 1: Audit existing memory (~30 min per agent)
- Inventory all `memory/*.md` files
- Group by **topic**, not file prefix
- Map to wiki/ folders (agents / crm / infrastructure / decisions / people / business / research)

### Phase 2: Build wiki skeleton (~30 min)
- Create `wiki/CLAUDE.md` from template
- Create `wiki/index.md` empty
- Create `wiki/log.md` empty
- Create folder structure (empty dirs OK)

### Phase 3: Migrate content (multi-session, 3-5h spread over 1-2 days)
- For each `memory/<file>.md`:
  1. Read content
  2. Find target wiki page(s) — usually 1-3 pages
  3. Write/merge with `[[cross-refs]]`, frontmatter, last_updated
  4. Update `wiki/index.md` if new page
  5. Append `wiki/log.md`
  6. Mark source: `> MIGRATED to [[wiki/...]] on 2026-05-XX, kept until pilot validated`

### Phase 4: Switch hooks (~30 min)
- Disable old `MEMORY.md` SessionStart auto-load
- Enable new `wiki-load-pointers.sh` SessionStart
- Add `wiki-fan-out-prompt.sh` PostToolUse
- Add `wiki-lint-check.sh` Stop (Nth gate)

### Phase 5: Validate (1 week)
- Daily check: context load size, recall accuracy, fan-out fire rate, Иги navigation success

### Phase 6: Fleet rollout (if pilot validated)
- Mechanic-Agents writes per-agent migration playbook
- Other 18 agents migrate one-by-one, agent owner per migration

---

## Success criteria (pilot)

- ✅ Context load SessionStart decreases ≥40% vs baseline (token measurement)
- ✅ Agent survives ≥3 sessions without overflow (vs current ~daily)
- ✅ Иги opens Obsidian, navigates ≥5 wiki pages without help
- ✅ ≥10 PostToolUse fan-out events fired and acted on
- ✅ Zero unresolved contradictions from /lint (24h max resolution)
- ✅ Both pilots (John + Mechanic) reach milestones
- ✅ Bidirectional sync healthy (no >5-min lag, no unresolved conflicts)

**Fail triggers (rollback):**
- Sync conflicts > 5/week unresolved
- Hook fan-out generates > 50% ignored noise
- Иги Obsidian navigation worse than current `Read MEMORY.md`
- Migration takes > 2x estimated time

---

## What stays unchanged

- **Graphiti** — cross-agent shared layer, orthogonal
- **Paperclip** — inter-agent Issue/comment channel (replaces killed fleet-mail per Иги voice 3462, 2026-05-24), orthogonal
- **AMP-Shutdown hook** — context overflow handler, orthogonal
- **`memory-format-standard.md`** — `project_status_matrix.md` + `project_lessons_log.md` protocols stay (just migrate location into wiki/decisions/)
- **`anthropic-memory-plan.md`** — AMP infrastructure stays (hook gates, etc.)
- **Root `CLAUDE.md`** — agent identity + fleet-standards @imports unchanged
- **`inbox-triage-rule.md`** — queue triage stays (rewritten for Paperclip 2026-05-24)

---

## Anti-patterns (NOT)

1. **Auto-fan-out wiki → Graphiti** — ASI03 cascade poisoning risk. Manual decision per ingest.
2. **Silent overwrite of contradicting facts** — always strikethrough + supersede note + log.md entry.
3. **Raw fetch content в `wiki/`** — `wiki/` is digested, `raw/` is immutable. Mixing destroys signal-to-noise.
4. **UUIDs / hashes in Obsidian-visible filenames** — Иги can't navigate. Human-readable kebab-case ALWAYS.
5. **Loading full wiki/ in SessionStart** — defeats Karpathy purpose. Pointers only, agent reads on demand.
6. **One lesson page per mistake** — collapses into thematic pages (e.g. `lessons/api-key-discipline.md` aggregates all API-key-related mistakes).
7. **Skipping log.md entry** — append-only is the audit trail. Skip = poison.

---

## Sources

- Karpathy gist: https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f
- John spec: `[internal spec]
- Current `_fleet-standards/memory-format-standard.md` (predecessor)
- Current `_fleet-standards/anthropic-memory-plan.md` (AMP infrastructure)
- Иги voice mandates 3335+3337+3340+3344+3345+3347 (2026-05-24)

---

## Status

- **2026-05-24:** v1 authored. Pilot pending Comp↔VPS sync prereq (Mechanic Главный).
- Phase 0-5: pending sync done. Phase 6 fleet rollout: TBD.
- Paperclip task IGG-XX creation: deferred — Mechanic-Agents has no Paperclip token on VPS (backlog Главного). John or Mechanic creates pilot task на initial sync done.

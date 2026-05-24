---
description: Persist a fact into wiki memory through deterministic 8-step state-machine pipeline. Use this instead of direct Write/Edit on memory/** or wiki/**.
allowed-tools: Bash(bash ${MEMORY_RAILS_SCRIPTS_DIR}/*:*), Write, Read
argument-hint: <fact to remember>
---

# /remember

You are about to persist a fact through the **memory-rails state-machine**. Direct Write/Edit on `memory/**` or `wiki/**` is BLOCKED by a DENY hook — the only way to write memory is through this pipeline.

## Step 1 — Run the pipeline planner

Execute:

!`bash "${MEMORY_RAILS_SCRIPTS_DIR}/pipeline-remember.sh" "$ARGUMENTS"`

The script prints:
- The classified category
- The target file path
- The proposed content (between `----- BEGIN CONTENT -----` / `----- END CONTENT -----`)
- The custody token path (expires in 60s)

## Step 2 — Write the file EXACTLY as instructed

Use the `Write` tool with the EXACT path and EXACT content the pipeline emitted. Do not paraphrase, do not reformat. The DENY hook validates the content SHA — any deviation will block.

If the DENY hook blocks, the most likely cause is content modification. Re-run `/remember` to get a fresh token.

## Step 3 — Finalize (index + log + verify)

Immediately after the `Write` succeeds, run:

```
bash "${MEMORY_RAILS_SCRIPTS_DIR}/finalize-remember.sh" "<target_rel>" "$ARGUMENTS"
```

(`<target_rel>` is the path printed by the planner — relative to the workspace.)

This appends `wiki/index.md` (if new page), appends `wiki/log.md`, and verifies the fact is present in the written file.

## What this prevents

- **Silent overwrite:** new content blowing away an existing fact without strikethrough-supersede.
- **Index drift:** new pages not registered in `wiki/index.md`.
- **Missing audit trail:** writes not logged in `wiki/log.md`.
- **Wrong category:** facts scattered across random files instead of routed to canonical wiki section.

## Reference

- Spec: `docs/architecture.md` (in this repo)
- Foundation: `docs/wiki-memory-standard.md` (in this repo)
- Origin: memory-rails v1 (2026-05-24)

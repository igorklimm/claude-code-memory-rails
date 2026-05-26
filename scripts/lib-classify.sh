#!/usr/bin/env bash
# lib-classify.sh — keyword heuristics to classify a memory fact into a wiki category.
#
# Returns category slug on stdout. Defaults to "misc" if no match.
#
# Categories (docs/wiki-memory-standard.md):
#   people / agents / crm / infrastructure / decisions / business / research / misc
#
# Override category routing with MEMORY_RAILS_CLASSIFY_FN: set it to a function name
# defined in a sourced helper file (see docs/architecture.md → "Custom categories").

classify_fact() {
    # Allow downstream projects to swap in their own classifier.
    if [ -n "${MEMORY_RAILS_CLASSIFY_FN:-}" ] && declare -F "$MEMORY_RAILS_CLASSIFY_FN" >/dev/null 2>&1; then
        "$MEMORY_RAILS_CLASSIFY_FN" "$1"
        return
    fi

    local text="$1"
    local lower
    lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    # people: human contacts, users, stakeholders
    case "$lower" in
        *user*|*customer*|*contact*|*stakeholder*|*vendor*|*owner*) echo "people"; return ;;
    esac

    # agents: mention of an agent/assistant/bot
    case "$lower" in
        *agent*|*assistant*|*coordinator*|*bot*) echo "agents"; return ;;
    esac

    # crm: tenant, workflow, pipeline
    case "$lower" in
        *crm*|*tenant*|*workflow*|*pipeline*) echo "crm"; return ;;
    esac

    # infrastructure: deploy, server, docker, network, hook
    case "$lower" in
        *deploy*|*server*|*docker*|*kubernetes*|*hook*|*sync*|*vps*|*infra*) echo "infrastructure"; return ;;
    esac

    # decisions: mandate, decision, pivot, roadmap, sprint
    case "$lower" in
        *mandate*|*decision*|*pivot*|*roadmap*|*sprint*|*wave*) echo "decisions"; return ;;
    esac

    # business: pricing, strategy, b2b, revenue
    case "$lower" in
        *pricing*|*strategy*|*b2b*|*revenue*|*business*) echo "business"; return ;;
    esac

    # research: paper, gist, study, research
    case "$lower" in
        *paper*|*gist*|*study*|*research*) echo "research"; return ;;
    esac

    echo "misc"
}

# Suggest a kebab-case filename slug from fact text. Truncated to 40 chars.
slug_for_fact() {
    local text="$1"
    echo "$text" | tr '[:upper:]' '[:lower:]' \
        | tr -c 'a-z0-9' '-' \
        | sed 's/--*/-/g; s/^-//; s/-$//' \
        | cut -c1-40
}

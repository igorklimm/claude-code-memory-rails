#!/usr/bin/env bash
# lib-classify.sh — keyword heuristics to classify a memory fact into a wiki category.
#
# Returns category slug on stdout. Defaults to "misc" if no match.
#
# Categories (wiki-memory-standard.md sec 30-75):
#   people / agents / crm / infrastructure / decisions / business / research / misc

classify_fact() {
    local text="$1"
    local lower
    lower=$(echo "$text" | tr '[:upper:]' '[:lower:]')

    # people: иги, contractor names, vendor contacts
    case "$lower" in
        *иги*|*iggy*|*igor*|*контрактор*|*vendor*) echo "people"; return ;;
    esac

    # agents: mention of known fleet agents
    case "$lower" in
        *john*|*mechanic*|*brigadir*|*jarvis*|*advisor*|*pushkin*|*designer*|*security*|*mech-agents*|*vps-mechanic*) echo "agents"; return ;;
    esac

    # crm: tenant, customer, workflow, contacts
    case "$lower" in
        *crm*|*tenant*|*customer*|*клиент*|*workflow*|*contact*|*pipeline*) echo "crm"; return ;;
    esac

    # infrastructure: tailscale, sync, amp, hook, deploy, vps, docker
    case "$lower" in
        *tailscale*|*sync*|*amp-shutdown*|*amp_shutdown*|*hook*|*deploy*|*vps*|*docker*|*graphiti*|*paperclip*|*инфра*|*infra*|*server*) echo "infrastructure"; return ;;
    esac

    # decisions: иги mandate, decision, wave, sprint, roadmap, voice
    case "$lower" in
        *mandate*|*voice*|*decision*|*wave*|*sprint*|*roadmap*|*мандат*|*решение*|*pivot*) echo "decisions"; return ;;
    esac

    # business: pricing, strategy, company, b2b, revenue
    case "$lower" in
        *pricing*|*strategy*|*company*|*b2b*|*revenue*|*стратегия*|*цена*|*бизнес*) echo "business"; return ;;
    esac

    # research: karpathy, anthropic, paper, gist, study
    case "$lower" in
        *karpathy*|*anthropic*|*paper*|*gist*|*study*|*research*|*исследование*) echo "research"; return ;;
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

#!/usr/bin/env bash
# lib-custody.sh — chain-of-custody token helpers for memory-rails state-machine.
#
# Tokens prove an LLM Write was emitted by an approved pipeline script.
# Tokens are single-use, expire after 60s, and live in tmpfs.
#
# Source this file from pipeline scripts; DENY hook calls custody_validate
# directly via its own copy of these helpers.

# --- token directory ---
MEMORY_RAILS_CUSTODY_DIR="${XDG_RUNTIME_DIR:-/tmp}/memory-rails"
MEMORY_RAILS_TOKEN_TTL_SEC=60

custody_dir_ensure() {
    mkdir -p "$MEMORY_RAILS_CUSTODY_DIR" 2>/dev/null
    chmod 700 "$MEMORY_RAILS_CUSTODY_DIR" 2>/dev/null
}

# Compute sha256 of stdin. Portable across coreutils + bsd.
custody_sha256_stdin() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    else
        echo "no-sha256-available"
        return 1
    fi
}

# Issue a custody token.
# Args: <target_path> <content_sha256> <pipeline_name> [session_id]
# Prints token file path on stdout.
custody_issue() {
    local target="$1"
    local content_sha="$2"
    local pipeline="$3"
    local session="${4:-${CLAUDE_SESSION_ID:-${PPID}-$$}}"

    custody_dir_ensure

    local now expires
    now=$(date +%s)
    expires=$((now + MEMORY_RAILS_TOKEN_TTL_SEC))

    local short_sha="${content_sha:0:12}"
    local token_path="${MEMORY_RAILS_CUSTODY_DIR}/custody-${session}-${short_sha}.tok"

    # Atomic write: tmp then rename.
    local tmp="${token_path}.tmp.$$"
    printf '{"target":"%s","content_sha256":"%s","expires_at":%d,"pipeline":"%s","ts":%d}\n' \
        "$target" "$content_sha" "$expires" "$pipeline" "$now" > "$tmp"
    mv "$tmp" "$token_path"
    chmod 600 "$token_path" 2>/dev/null

    echo "$token_path"
}

# Validate a custody token against a Write attempt.
# Args: <target_path> <content_sha256> [session_id]
# Returns 0 (allow) if matching unexpired token exists; consumes (deletes) it on success.
# Returns 1 (deny) otherwise.
custody_validate_and_consume() {
    local target="$1"
    local content_sha="$2"
    local session="${3:-${CLAUDE_SESSION_ID:-${PPID}-$$}}"

    custody_dir_ensure

    local short_sha="${content_sha:0:12}"
    local token_path="${MEMORY_RAILS_CUSTODY_DIR}/custody-${session}-${short_sha}.tok"

    [ -f "$token_path" ] || return 1

    # Parse + validate via node (portable JSON parse).
    local now valid
    now=$(date +%s)
    valid=$(TOKEN_PATH="$token_path" TARGET="$target" CONTENT_SHA="$content_sha" NOW="$now" \
        node -e "
        (function() {
          try {
            const o = JSON.parse(require('fs').readFileSync(process.env.TOKEN_PATH,'utf8'));
            const okTarget = o.target === process.env.TARGET;
            const okSha = o.content_sha256 === process.env.CONTENT_SHA;
            const okFresh = Number(process.env.NOW) < (o.expires_at || 0);
            process.stdout.write(okTarget && okSha && okFresh ? '1' : '0');
          } catch(e) { process.stdout.write('0'); }
        })();
    " 2>/dev/null)

    if [ "$valid" = "1" ]; then
        rm -f "$token_path" 2>/dev/null
        return 0
    fi
    return 1
}

# Garbage-collect expired tokens. Cheap to call.
custody_gc() {
    custody_dir_ensure
    local now
    now=$(date +%s)
    find "$MEMORY_RAILS_CUSTODY_DIR" -name 'custody-*.tok' -type f 2>/dev/null | while read -r f; do
        local expires
        expires=$(F="$f" node -e "
            (function() {
              try {
                const o = JSON.parse(require('fs').readFileSync(process.env.F,'utf8'));
                process.stdout.write(String(o.expires_at || 0));
              } catch(e) { process.stdout.write('0'); }
            })();
        " 2>/dev/null)
        if [ -n "$expires" ] && [ "$now" -gt "$expires" ]; then
            rm -f "$f" 2>/dev/null
        fi
    done
}

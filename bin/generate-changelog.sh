#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

OLD_TAG="${OLD_TAG:-latest}"
DRY_RUN="${DRY_RUN:-false}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-300}"

if [[ "$(uname -s)" == "Darwin" ]]; then
    FLAKE_OUTPUT="${FLAKE_OUTPUT:-.#darwinConfigurations.mac-arm64.system}"
else
    FLAKE_OUTPUT="${FLAKE_OUTPUT:-.#homeConfigurations.linux-x64.activationPackage}"
fi

log() { echo "📋 $*" >&2; }
warn() { echo "⚠️  $*" >&2; }
error() { echo "❌ $*" >&2; exit 1; }

cd "$REPO_DIR"

if ! git rev-parse "$OLD_TAG" &>/dev/null; then
    log "No previous tag '$OLD_TAG' found, creating initial changelog"
    OLD_TAG=""
fi

get_commits() {
    if [[ -z "$OLD_TAG" ]]; then
        git log --format='{"sha":"%h","message":"%s","author":"%an"}' -10 | jq -s '.'
    else
        git log --format='{"sha":"%h","message":"%s","author":"%an"}' "$OLD_TAG..HEAD" | jq -s '.'
    fi
}

get_flake_input_changes() {
    if [[ -z "$OLD_TAG" ]]; then
        echo "{}"
        return
    fi

    local old_lock new_lock
    old_lock=$(git show "$OLD_TAG:flake.lock" 2>/dev/null) || { echo "{}"; return; }
    new_lock=$(cat flake.lock)

    local inputs
    inputs=$(echo "$new_lock" | jq -r '.nodes | keys[] | select(. != "root")' | grep -v "^systems$" | grep -v "^flake-parts$" || true)

    local result="{}"
    for input in $inputs; do
        local old_rev new_rev
        old_rev=$(echo "$old_lock" | jq -r ".nodes[\"$input\"].locked.rev // empty" 2>/dev/null || true)
        new_rev=$(echo "$new_lock" | jq -r ".nodes[\"$input\"].locked.rev // empty" 2>/dev/null || true)

        if [[ -n "$old_rev" && -n "$new_rev" && "$old_rev" != "$new_rev" ]]; then
            local owner repo commit_count
            owner=$(echo "$new_lock" | jq -r ".nodes[\"$input\"].locked.owner // empty")
            repo=$(echo "$new_lock" | jq -r ".nodes[\"$input\"].locked.repo // empty")

            commit_count=0
            if [[ -n "$owner" && -n "$repo" ]]; then
                commit_count=$(curl -s "https://api.github.com/repos/$owner/$repo/compare/${old_rev}...${new_rev}" 2>/dev/null | jq '.total_commits // 0' || echo "0")
            fi

            result=$(echo "$result" | jq --arg input "$input" \
                --arg from "$old_rev" \
                --arg to "$new_rev" \
                --argjson count "$commit_count" \
                '. + {($input): {"from_rev": $from, "to_rev": $to, "commit_count": $count}}')
        fi
    done

    echo "$result"
}

try_nvd_diff() {
    local new_store_path="$1"

    if [[ -z "$OLD_TAG" ]]; then
        echo '{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
        return
    fi

    log "Attempting nvd diff..."

    local old_rev old_store_path
    old_rev=$(git rev-parse "$OLD_TAG")

    local old_flake_output="${FLAKE_OUTPUT/.#/.?rev=${old_rev}#}"
    old_store_path=$(nix eval --raw "${old_flake_output}.outPath" 2>/dev/null) || true

    if [[ -z "$old_store_path" ]]; then
        warn "Could not evaluate old store path"
        echo '{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
        return
    fi

    if nix path-info "$old_store_path" &>/dev/null; then
        log "Old store path found in cache"
    else
        log "Old store path not cached, attempting build (timeout: ${BUILD_TIMEOUT}s)..."
        local build_output
        if ! build_output=$(timeout "$BUILD_TIMEOUT" nix build --no-link --print-out-paths "$old_flake_output" 2>&1); then
            warn "Build timed out or failed: $build_output"
            echo '{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
            return
        fi
        log "Old build completed: $build_output"
    fi

    if ! nix path-info "$old_store_path" &>/dev/null; then
        warn "Old store path still not available after build: $old_store_path"
        echo '{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
        return
    fi

    log "Running nvd diff between $old_store_path and $new_store_path"
    local nvd_output nvd_error
    if ! nvd_output=$(nvd diff "$old_store_path" "$new_store_path" 2>&1); then
        warn "nvd diff failed: $nvd_output"
        echo '{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
        return
    fi

    parse_nvd_output "$nvd_output"
}

parse_nvd_output() {
    local nvd_output="$1"

    local upgraded=()
    local added=()
    local removed=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        if [[ "$line" =~ ^([a-zA-Z0-9_-]+):\ +([0-9][^\ ]*)\ *→\ *([0-9][^\ ,]*) ]]; then
            local name="${BASH_REMATCH[1]}"
            local from="${BASH_REMATCH[2]}"
            local to="${BASH_REMATCH[3]}"
            upgraded+=("{\"name\":\"$name\",\"from\":\"$from\",\"to\":\"$to\"}")
        elif [[ "$line" =~ ^([a-zA-Z0-9_-]+):\ +∅\ *→ ]]; then
            local name="${BASH_REMATCH[1]}"
            added+=("\"$name\"")
        elif [[ "$line" =~ ^([a-zA-Z0-9_-]+):.*→\ *∅ ]]; then
            local name="${BASH_REMATCH[1]}"
            removed+=("\"$name\"")
        fi
    done <<< "$nvd_output"

    local upgraded_json="[]"
    local added_json="[]"
    local removed_json="[]"

    if [[ ${#upgraded[@]} -gt 0 ]]; then
        upgraded_json=$(printf '%s\n' "${upgraded[@]}" | jq -s '.')
    fi
    if [[ ${#added[@]} -gt 0 ]]; then
        added_json=$(printf '%s\n' "${added[@]}" | jq -s '.')
    fi
    if [[ ${#removed[@]} -gt 0 ]]; then
        removed_json=$(printf '%s\n' "${removed[@]}" | jq -s '.')
    fi

    jq -n \
        --argjson upgraded "$upgraded_json" \
        --argjson added "$added_json" \
        --argjson removed "$removed_json" \
        '{nvd_available: true, upgraded: $upgraded, added: $added, removed: $removed}'
}

call_claude_api() {
    local commits="$1"
    local flake_changes="$2"
    local package_changes="$3"

    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        warn "No ANTHROPIC_API_KEY set, using default classification"
        echo '{"importance":"minor","summary":"Package and configuration updates.","security_notes":[],"breaking_changes":[]}'
        return
    fi

    local nvd_section
    if [[ $(echo "$package_changes" | jq '.nvd_available') == "true" ]]; then
        nvd_section="Package version changes (from nvd diff):
Upgraded: $(echo "$package_changes" | jq -c '.upgraded')
Added: $(echo "$package_changes" | jq -c '.added')
Removed: $(echo "$package_changes" | jq -c '.removed')"
    else
        nvd_section="Package version changes: unavailable - analyze from commits only"
    fi

    local prompt
    prompt="Analyze these changes to a Nix home-manager/nix-darwin configuration repository.

## Commits
$commits

## Flake Input Changes
$flake_changes

## $nvd_section

Classify these changes and respond with ONLY valid JSON (no markdown, no explanation):
{
  \"importance\": \"security|breaking|feature|fix|minor\",
  \"summary\": \"1-2 sentence human-readable summary\",
  \"security_notes\": [\"array of security-related items, empty if none\"],
  \"breaking_changes\": [\"array of breaking changes requiring user action, empty if none\"]
}

Guidelines:
- importance: security (CVE/vulnerability fixes), breaking (requires user action), feature (new capabilities), fix (bug fixes), minor (routine updates)
- Look for CVE mentions, security keywords, breaking change indicators
- Be concise in summary"

    local response
    local max_retries=3
    local retry_delay=2

    for attempt in $(seq 1 $max_retries); do
        response=$(curl -s --max-time 30 -X POST "https://api.anthropic.com/v1/messages" \
            -H "Content-Type: application/json" \
            -H "x-api-key: $ANTHROPIC_API_KEY" \
            -H "anthropic-version: 2023-06-01" \
            -d "$(jq -n \
                --arg prompt "$prompt" \
                '{
                    model: "claude-3-5-haiku-latest",
                    max_tokens: 512,
                    messages: [{role: "user", content: $prompt}]
                }')" 2>/dev/null) || true

        if [[ -n "$response" ]]; then
            local content
            content=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null) || true

            if [[ -n "$content" ]] && echo "$content" | jq . &>/dev/null; then
                echo "$content"
                return
            fi
        fi

        if [[ $attempt -lt $max_retries ]]; then
            warn "API call failed (attempt $attempt/$max_retries), retrying in ${retry_delay}s..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))
        fi
    done

    warn "All API attempts failed, using default classification"
    echo '{"importance":"minor","summary":"Package and configuration updates.","security_notes":[],"breaking_changes":[]}'
}

main() {
    log "Starting changelog generation..."

    log "Building current configuration ($FLAKE_OUTPUT)..."
    local new_store_path
    new_store_path=$(nix build --print-out-paths "$FLAKE_OUTPUT" 2>/dev/null) || {
        error "Failed to build current configuration"
    }
    log "Current store path: $new_store_path"

    log "Gathering commits..."
    local commits
    commits=$(get_commits)
    local commit_count
    commit_count=$(echo "$commits" | jq 'length')
    log "Found $commit_count commits"

    if [[ "$commit_count" -eq 0 ]]; then
        log "No commits since last tag, skipping changelog generation"
        exit 0
    fi

    local manual_commits auto_commits
    manual_commits=$(echo "$commits" | jq '[.[] | select(.message | startswith("AutoFlakeUpdater") | not)]')
    auto_commits=$(echo "$commits" | jq '[.[] | select(.message | startswith("AutoFlakeUpdater"))]')

    log "Parsing flake.lock changes..."
    local flake_changes
    flake_changes=$(get_flake_input_changes)

    log "Attempting package diff..."
    local package_changes
    package_changes=$(try_nvd_diff "$new_store_path")

    log "Calling Claude API for classification..."
    local ai_response
    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY_RUN mode, using mock AI response"
        ai_response='{"importance":"minor","summary":"Mock changelog for testing.","security_notes":[],"breaking_changes":[]}'
    else
        ai_response=$(call_claude_api "$commits" "$flake_changes" "$package_changes")
    fi

    local current_version new_version
    current_version=$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo "0")
    new_version=$((current_version + 1))

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local changelog
    changelog=$(jq -n \
        --argjson version "$new_version" \
        --arg timestamp "$timestamp" \
        --arg importance "$(echo "$ai_response" | jq -r '.importance')" \
        --argjson package_changes "$package_changes" \
        --argjson inputs_changed "$flake_changes" \
        --argjson manual_commits "$manual_commits" \
        --arg ai_summary "$(echo "$ai_response" | jq -r '.summary')" \
        --argjson security_notes "$(echo "$ai_response" | jq '.security_notes')" \
        --argjson breaking_changes "$(echo "$ai_response" | jq '.breaking_changes')" \
        '{
            version: $version,
            timestamp: $timestamp,
            importance: $importance,
            package_changes: $package_changes,
            inputs_changed: $inputs_changed,
            manual_commits: $manual_commits,
            ai_summary: $ai_summary,
            security_notes: $security_notes,
            breaking_changes: $breaking_changes
        }')

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY_RUN mode, not writing files"
        echo "$changelog" | jq .
        exit 0
    fi

    log "Writing changelog v$new_version..."
    echo "$changelog" | jq . > "$REPO_DIR/changelogs/${new_version}.json"
    echo "$new_version" > "$REPO_DIR/VERSION"

    log "Changelog v$new_version generated successfully!"
    echo "$changelog" | jq .
}

main "$@"

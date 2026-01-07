#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

OLD_TAG="${OLD_TAG:-latest}"
DRY_RUN="${DRY_RUN:-false}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-300}"
VERSION_OVERRIDE="${VERSION_OVERRIDE:-}"

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

        # nvd output format: [U.] #01 package-name 1.0.0 -> 2.0.0
        # [U.] = Upgraded, [D.] = Downgraded, [A.] = Added, [R.] = Removed, [C.] = Changed
        if [[ "$line" =~ ^\[U.*\].*#[0-9]+[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([^[:space:]]+)[[:space:]]+-\>[[:space:]]+([^[:space:],]+) ]]; then
            local name="${BASH_REMATCH[1]}"
            local from="${BASH_REMATCH[2]}"
            local to="${BASH_REMATCH[3]}"
            upgraded+=("{\"name\":\"$name\",\"from\":\"$from\",\"to\":\"$to\"}")
        elif [[ "$line" =~ ^\[A.*\].*#[0-9]+[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([^[:space:],]+) ]]; then
            local name="${BASH_REMATCH[1]}"
            local version="${BASH_REMATCH[2]}"
            added+=("{\"name\":\"$name\",\"version\":\"$version\"}")
        elif [[ "$line" =~ ^\[R.*\].*#[0-9]+[[:space:]]+([a-zA-Z0-9_-]+)[[:space:]]+([^[:space:],]+) ]]; then
            local name="${BASH_REMATCH[1]}"
            local version="${BASH_REMATCH[2]}"
            removed+=("{\"name\":\"$name\",\"version\":\"$version\"}")
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
    # Filter out automated commits:
    # - AutoFlakeUpdater: daily flake update bot
    # - vXXX: changelog: automated changelog commits from CI
    manual_commits=$(echo "$commits" | jq '[.[] | select(
        (.message | startswith("AutoFlakeUpdater") | not) and
        (.message | test("^v[0-9]+: changelog") | not)
    )]')
    auto_commits=$(echo "$commits" | jq '[.[] | select(.message | startswith("AutoFlakeUpdater"))]')

    log "Parsing flake.lock changes..."
    local flake_changes
    flake_changes=$(get_flake_input_changes)

    log "Attempting package diff..."
    local package_changes
    package_changes=$(try_nvd_diff "$new_store_path")

    local current_version new_version
    if [[ -n "$VERSION_OVERRIDE" ]]; then
        current_version="$VERSION_OVERRIDE"
    else
        current_version=$(cat "$REPO_DIR/VERSION" 2>/dev/null || echo "0")
    fi
    new_version=$((current_version + 1))

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local changelog
    changelog=$(jq -n \
        --argjson version "$new_version" \
        --arg timestamp "$timestamp" \
        --argjson package_changes "$package_changes" \
        --argjson inputs_changed "$flake_changes" \
        --argjson manual_commits "$manual_commits" \
        '{
            version: $version,
            timestamp: $timestamp,
            package_changes: $package_changes,
            inputs_changed: $inputs_changed,
            manual_commits: $manual_commits
        }')

    if [[ "$DRY_RUN" == "true" ]]; then
        log "DRY_RUN mode, not writing files"
        echo "$changelog" | jq .
        exit 0
    fi

    log "Writing changelog v$new_version..."
    echo "$changelog" | jq . > "$REPO_DIR/changelogs/${new_version}.json"
    if [[ -z "$VERSION_OVERRIDE" ]]; then
        echo "$new_version" > "$REPO_DIR/VERSION"
    fi

    log "Changelog v$new_version generated successfully!"
    echo "$changelog" | jq .
}

main "$@"

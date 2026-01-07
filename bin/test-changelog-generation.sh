#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEST_CHANGELOGS_DIR="$REPO_DIR/local/test-changelogs"

NUM_CHANGELOGS="${NUM_CHANGELOGS:-3}"
MONTHS_BACK="${MONTHS_BACK:-6}"
BUILD_TIMEOUT="${BUILD_TIMEOUT:-600}"

if [[ "$(uname -s)" == "Darwin" ]]; then
    FLAKE_OUTPUT="${FLAKE_OUTPUT:-darwinConfigurations.mac-arm64.system}"
else
    FLAKE_OUTPUT="${FLAKE_OUTPUT:-homeConfigurations.linux-x64.activationPackage}"
fi

log() { echo "🧪 $*" >&2; }
warn() { echo "⚠️  $*" >&2; }
error() { echo "❌ $*" >&2; exit 1; }

cd "$REPO_DIR"

log "Finding commits over the last $MONTHS_BACK months..."
mapfile -t all_commits < <(git log --oneline --since="$MONTHS_BACK months ago" --reverse --format="%H")
total_commits=${#all_commits[@]}

if [[ $total_commits -lt $((NUM_CHANGELOGS + 1)) ]]; then
    error "Not enough commits ($total_commits) for $NUM_CHANGELOGS sequential changelogs"
fi

step=$((total_commits / NUM_CHANGELOGS))
log "Found $total_commits commits, selecting every ~$step commits for sequential comparison"

selected_commits=()
for i in $(seq 0 $NUM_CHANGELOGS); do
    idx=$((i * step))
    if [[ $idx -ge $total_commits ]]; then
        idx=$((total_commits - 1))
    fi
    selected_commits+=("${all_commits[$idx]}")
done

log "Selected commits for SEQUENTIAL comparison:"
for i in "${!selected_commits[@]}"; do
    commit="${selected_commits[$i]}"
    date=$(git log -1 --format="%ad" --date=short "$commit")
    msg=$(git log -1 --format="%s" "$commit" | head -c 50)
    log "  [$i] $date ${commit:0:7} $msg"
done

log ""
log "Sequential ranges to compare:"
for i in $(seq 1 $NUM_CHANGELOGS); do
    old="${selected_commits[$((i-1))]}"
    new="${selected_commits[$i]}"
    log "  Changelog $i: ${old:0:7} → ${new:0:7}"
done

rm -rf "$TEST_CHANGELOGS_DIR"
mkdir -p "$TEST_CHANGELOGS_DIR"

parse_nvd_output() {
    local nvd_output="$1"
    local upgraded=()
    local added=()
    local removed=()

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
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

build_config_at_rev() {
    local rev="$1"
    local flake_ref=".?rev=${rev}#${FLAKE_OUTPUT}"

    log "  Building configuration at ${rev:0:7}..."
    local store_path
    if ! store_path=$(timeout "$BUILD_TIMEOUT" nix build --no-link --print-out-paths "$flake_ref" 2>&1); then
        warn "  Build failed or timed out for ${rev:0:7}"
        echo ""
        return 1
    fi
    echo "$store_path"
}

get_commits_between() {
    local old_rev="$1"
    local new_rev="$2"
    git log --format='{"sha":"%h","message":"%s","author":"%an"}' "$old_rev..$new_rev" 2>/dev/null | jq -s '.' || echo "[]"
}

get_flake_changes_between() {
    local old_rev="$1"
    local new_rev="$2"

    local old_lock new_lock
    old_lock=$(git show "$old_rev:flake.lock" 2>/dev/null) || { echo "{}"; return; }
    new_lock=$(git show "$new_rev:flake.lock" 2>/dev/null) || { echo "{}"; return; }

    local inputs
    inputs=$(echo "$new_lock" | jq -r '.nodes | keys[] | select(. != "root")' | grep -v "^systems$" | grep -v "^flake-parts$" || true)

    local result="{}"
    for input in $inputs; do
        local old_input_rev new_input_rev
        old_input_rev=$(echo "$old_lock" | jq -r ".nodes[\"$input\"].locked.rev // empty" 2>/dev/null || true)
        new_input_rev=$(echo "$new_lock" | jq -r ".nodes[\"$input\"].locked.rev // empty" 2>/dev/null || true)

        if [[ -n "$old_input_rev" && -n "$new_input_rev" && "$old_input_rev" != "$new_input_rev" ]]; then
            result=$(echo "$result" | jq --arg input "$input" \
                --arg from "$old_input_rev" \
                --arg to "$new_input_rev" \
                '. + {($input): {"from_rev": $from, "to_rev": $to, "commit_count": 0}}')
        fi
    done
    echo "$result"
}

log ""
log "Generating SEQUENTIAL changelogs..."

for i in $(seq 1 $NUM_CHANGELOGS); do
    old_commit="${selected_commits[$((i-1))]}"
    new_commit="${selected_commits[$i]}"

    old_date=$(git log -1 --format="%ad" --date=short "$old_commit")
    new_date=$(git log -1 --format="%ad" --date=short "$new_commit")

    log ""
    log "=== Changelog $i: ${old_commit:0:7} ($old_date) → ${new_commit:0:7} ($new_date) ==="

    old_store_path=$(build_config_at_rev "$old_commit")
    if [[ -z "$old_store_path" ]]; then
        warn "Skipping changelog $i - could not build old config"
        continue
    fi

    new_store_path=$(build_config_at_rev "$new_commit")
    if [[ -z "$new_store_path" ]]; then
        warn "Skipping changelog $i - could not build new config"
        continue
    fi

    log "  Running nvd diff..."
    nvd_output=""
    if ! nvd_output=$(nvd diff "$old_store_path" "$new_store_path" 2>&1); then
        warn "  nvd diff failed"
        nvd_output=""
    fi

    package_changes=""
    if [[ -n "$nvd_output" ]]; then
        package_changes=$(parse_nvd_output "$nvd_output")
        upgrade_count=$(echo "$package_changes" | jq '.upgraded | length')
        log "  Found $upgrade_count package upgrades"
    else
        package_changes='{"nvd_available":false,"upgraded":[],"added":[],"removed":[]}'
    fi

    log "  Gathering commits and flake changes..."
    commits=$(get_commits_between "$old_commit" "$new_commit")
    flake_changes=$(get_flake_changes_between "$old_commit" "$new_commit")

    manual_commits=$(echo "$commits" | jq '[.[] | select(
        (.message | startswith("AutoFlakeUpdater") | not) and
        (.message | test("^v[0-9]+: changelog") | not)
    )]')

    timestamp=$(git log -1 --format="%aI" "$new_commit")

    changelog=$(jq -n \
        --argjson version "$i" \
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

    echo "$changelog" | jq . > "$TEST_CHANGELOGS_DIR/$i.json"
    log "✅ Generated changelog $i"
done

log ""
log "=== Test Changelogs Generated ==="
ls -la "$TEST_CHANGELOGS_DIR"

log ""
log "=== Package Upgrade Summary (to verify sequential data) ==="
for f in "$TEST_CHANGELOGS_DIR"/*.json; do
    v=$(basename "$f" .json)
    echo ""
    echo "--- Changelog $v ---"
    jq -r '.package_changes.upgraded[] | "  \(.name): \(.from) → \(.to)"' "$f" 2>/dev/null | head -10 || echo "  (no upgrades)"
done

log ""
log "=== Aggregated Changelog Display (v0 → v$NUM_CHANGELOGS) ==="

cp "$TEST_CHANGELOGS_DIR"/*.json "$REPO_DIR/changelogs/" 2>/dev/null || true

if command -v jacks-nix-changelog &>/dev/null; then
    jacks-nix-changelog 0 "$NUM_CHANGELOGS"
else
    log "(jacks-nix-changelog not in PATH, showing summaries with jq)"
    echo ""
    for f in "$TEST_CHANGELOGS_DIR"/*.json; do
        v=$(basename "$f" .json)
        upgrades=$(jq -r '.package_changes.upgraded | length' "$f")
        commits=$(jq -r '.manual_commits | length' "$f")
        echo "  v$v: ${upgrades} package upgrades, ${commits} commits"
    done
    echo ""
fi

for i in $(seq 1 $NUM_CHANGELOGS); do
    rm -f "$REPO_DIR/changelogs/$i.json"
done

log ""
log "Test changelogs preserved in: $TEST_CHANGELOGS_DIR"
log ""
log "To verify aggregation works correctly, look for packages that appear in"
log "multiple changelogs - the aggregated display should show their combined"
log "version jump (e.g., 1.0→1.1 + 1.1→1.2 = 1.0→1.2)"

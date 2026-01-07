#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TEST_CHANGELOGS_DIR="$REPO_DIR/local/test-changelogs"

# Configuration
NUM_CHANGELOGS="${NUM_CHANGELOGS:-5}"
MONTHS_BACK="${MONTHS_BACK:-6}"
DRY_RUN="${DRY_RUN:-false}"

log() { echo "🧪 $*" >&2; }

cd "$REPO_DIR"

# Get commits evenly spaced over the time period
log "Finding commits over the last $MONTHS_BACK months..."
all_commits=($(git log --oneline --since="$MONTHS_BACK months ago" --reverse --format="%H"))
total_commits=${#all_commits[@]}

if [[ $total_commits -lt $((NUM_CHANGELOGS + 1)) ]]; then
    log "Not enough commits ($total_commits) for $NUM_CHANGELOGS changelogs"
    exit 1
fi

# Calculate step size to get evenly spaced commits
step=$((total_commits / NUM_CHANGELOGS))
log "Found $total_commits commits, selecting every ~$step commits"

# Select commits (including oldest as baseline and newest as final)
selected_commits=()
for i in $(seq 0 $NUM_CHANGELOGS); do
    idx=$((i * step))
    if [[ $idx -ge $total_commits ]]; then
        idx=$((total_commits - 1))
    fi
    selected_commits+=("${all_commits[$idx]}")
done

# Show selected commits
log "Selected commits:"
for i in "${!selected_commits[@]}"; do
    commit="${selected_commits[$i]}"
    date=$(git log -1 --format="%ad" --date=short "$commit")
    msg=$(git log -1 --format="%s" "$commit" | head -c 50)
    log "  [$i] $date ${commit:0:7} $msg"
done

# Create test changelogs directory
rm -rf "$TEST_CHANGELOGS_DIR"
mkdir -p "$TEST_CHANGELOGS_DIR"

# Save current HEAD to restore later
original_head=$(git rev-parse HEAD)
original_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

cleanup() {
    log "Restoring original state..."
    if [[ -n "$original_branch" && "$original_branch" != "HEAD" ]]; then
        git checkout -q "$original_branch" 2>/dev/null || git checkout -q "$original_head"
    else
        git checkout -q "$original_head"
    fi
}
trap cleanup EXIT

# Generate changelogs for each pair
log ""
log "Generating changelogs..."
for i in $(seq 1 $NUM_CHANGELOGS); do
    old_commit="${selected_commits[$((i-1))]}"
    new_commit="${selected_commits[$i]}"

    old_date=$(git log -1 --format="%ad" --date=short "$old_commit")
    new_date=$(git log -1 --format="%ad" --date=short "$new_commit")

    log ""
    log "=== Changelog $i: ${old_commit:0:7} ($old_date) → ${new_commit:0:7} ($new_date) ==="

    # Checkout new commit
    git checkout -q "$new_commit"

    # Create a temporary tag for the old commit
    git tag -f test-old-tag "$old_commit" >/dev/null 2>&1

    # Run generate-changelog.sh with custom OLD_TAG
    # Override VERSION to use sequential numbers for our test
    echo "$i" > "$REPO_DIR/VERSION"

    if [[ "$DRY_RUN" == "true" ]]; then
        OLD_TAG="test-old-tag" DRY_RUN=true "$SCRIPT_DIR/generate-changelog.sh" 2>&1 | tail -20 || true
    else
        OLD_TAG="test-old-tag" "$SCRIPT_DIR/generate-changelog.sh" 2>&1 | grep -E "^(📋|⚠️|{)" || true
    fi

    # Move generated changelog to test directory
    if [[ -f "$REPO_DIR/changelogs/$i.json" ]]; then
        mv "$REPO_DIR/changelogs/$i.json" "$TEST_CHANGELOGS_DIR/$i.json"
        log "✅ Generated changelog $i"
    else
        log "⚠️  No changelog generated for $i"
    fi

    # Clean up tag
    git tag -d test-old-tag >/dev/null 2>&1 || true
done

# Restore VERSION
git checkout -q "$original_head" -- VERSION 2>/dev/null || echo "297" > "$REPO_DIR/VERSION"

log ""
log "=== Test Changelogs Generated ==="
ls -la "$TEST_CHANGELOGS_DIR"

log ""
log "=== Aggregated Changelog Display (v0 → v$NUM_CHANGELOGS) ==="
log ""

# Temporarily copy test changelogs to main changelogs dir for display
cp "$TEST_CHANGELOGS_DIR"/*.json "$REPO_DIR/changelogs/" 2>/dev/null || true

# Run the display script
if command -v jacks-nix-changelog-show &>/dev/null; then
    jacks-nix-changelog-show 0 "$NUM_CHANGELOGS"
else
    log "jacks-nix-changelog-show not in PATH, showing raw changelogs:"
    for f in "$TEST_CHANGELOGS_DIR"/*.json; do
        echo "--- $(basename "$f") ---"
        cat "$f" | jq -r '.ai_summary // "No summary"'
    done
fi

# Clean up test changelogs from main dir
for i in $(seq 1 $NUM_CHANGELOGS); do
    rm -f "$REPO_DIR/changelogs/$i.json"
done

log ""
log "Test changelogs preserved in: $TEST_CHANGELOGS_DIR"

#!/bin/bash

# Test script for jacks-nix flake
# This script performs dry runs to ensure the flake works on both Mac and Linux

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Initialize log file (overwrite if exists)
LOG_FILE="test-flake.log"
> "$LOG_FILE"

echo "🧪 Testing jacks-nix flake configurations..."
echo "============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "SUCCESS" ]; then
        echo -e "${GREEN}✅ $message${NC}"
    elif [ "$status" = "ERROR" ]; then
        echo -e "${RED}❌ $message${NC}"
    elif [ "$status" = "INFO" ]; then
        echo -e "${YELLOW}ℹ️  $message${NC}"
    fi
}

# Function to run a test
run_test() {
    local test_name=$1
    local command=$2

    print_status "INFO" "Testing: $test_name"

    if eval "$command" >> "$LOG_FILE" 2>&1; then
        print_status "SUCCESS" "$test_name passed"
        return 0
    else
        print_status "ERROR" "$test_name failed"
        return 1
    fi
}

# Check if nix is available
if ! command -v nix >> "$LOG_FILE" 2>&1; then
    print_status "ERROR" "Nix is not installed or not in PATH"
    exit 1
fi

print_status "INFO" "Nix version: $(nix --version)"
echo ""

# Test flake evaluation
echo "🔍 Testing flake evaluation..."
echo "------------------------------"

# Test basic flake show
run_test "Flake show" "nix flake show --no-write-lock-file"

# Test flake check
run_test "Flake check" "nix flake check --no-write-lock-file"

echo ""

# Test Linux x64 configuration
echo "🐧 Testing Linux x64 configuration..."
echo "------------------------------------"

run_test "Linux x64 home configuration evaluation" \
    "nix eval --no-write-lock-file .#homeConfigurations.linux-x64.config.home.username --apply 'x: \"evaluation-success\"'"

run_test "Linux x64 home configuration dry-run build" \
    "nix build --dry-run --no-write-lock-file .#homeConfigurations.linux-x64.activationPackage"

echo ""

# Test Mac ARM64 configuration
echo "🍎 Testing Mac ARM64 configuration..."
echo "-----------------------------------"

run_test "Mac ARM64 darwin configuration evaluation" \
    "nix eval --no-write-lock-file .#darwinConfigurations.mac-arm64.config.system.stateVersion --apply 'x: \"evaluation-success\"'"

run_test "Mac ARM64 darwin configuration dry-run build" \
    "nix build --dry-run --no-write-lock-file .#darwinConfigurations.mac-arm64.system"

echo ""

# Test configuration options
echo "⚙️  Testing configuration options..."
echo "----------------------------------"

run_test "Configuration options evaluation" \
    "nix eval --no-write-lock-file .#homeConfigurations.linux-x64.options.jacks-nix.user.name.type --apply 'x: \"evaluation-success\"'"

echo ""

# Summary
echo "📋 Test Summary"
echo "==============="

# Count passed/failed tests by checking return codes
# This is a simple approach - in a real script you might want more sophisticated tracking

print_status "INFO" "All dry-run tests completed!"
print_status "INFO" "If you see this message, the basic flake structure is working."
print_status "INFO" "Note: Some tests may fail on systems that don't match the target architecture."

echo ""
echo "💡 To manually test specific configurations:"
echo "   Linux:  nix build .#homeConfigurations.linux-x64.activationPackage"
echo "   macOS:  nix build .#darwinConfigurations.mac-arm64.system"
echo ""
echo "🚀 To apply configurations:"
echo "   Linux:  home-manager switch --flake .#linux-x64"
echo "   macOS:  darwin-rebuild switch --flake .#mac-arm64"

#!/bin/bash

# Test script for jacks-nix flake
# This script performs dry runs to ensure the flake works on both Mac and Linux

set -euo pipefail

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Initialize log file (overwrite if exists)
LOG_FILE="$(pwd)/test-flake.log"
> "$LOG_FILE"

cd ../

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
    "nix eval --no-write-lock-file .#homeConfigurations.linux-x64.options.jacks-nix.git.name.type --apply 'x: \"evaluation-success\"'"

echo ""

# Test environment variables
echo "🌍 Testing environment variable overrides..."
echo "-------------------------------------------"

# Function to run environment variable test
run_env_test() {
    local test_name=$1
    local env_vars=$2
    local config_path=$3
    local expected_value=$4

    print_status "INFO" "Testing: $test_name"

    local command="$env_vars nix eval --impure --no-write-lock-file .#homeConfigurations.linux-x64.config.jacks-nix.$config_path"
    local result
    result=$(eval "$command" 2>>"$LOG_FILE")

    if [ "$result" = "$expected_value" ]; then
        print_status "SUCCESS" "$test_name passed (got: $result)"
        return 0
    else
        print_status "ERROR" "$test_name failed (expected: $expected_value, got: $result)"
        echo "$command" >> "$LOG_FILE"
        echo "Expected: $expected_value" >> "$LOG_FILE"
        echo "Got: $result" >> "$LOG_FILE"
        return 1
    fi
}

# Test string environment variables with non-default values
run_env_test "JACKS_NIX_CONFIG_REPO_PATH override" \
    'JACKS_NIX_CONFIG_REPO_PATH="/custom/path"' \
    "configRepoPath" \
    '"/custom/path"'

run_env_test "JACKS_NIX_GIT_NAME override" \
    'JACKS_NIX_GIT_NAME="Test User"' \
    "git.name" \
    '"Test User"'

run_env_test "JACKS_NIX_GIT_EMAIL override" \
    'JACKS_NIX_GIT_EMAIL="test@example.com"' \
    "git.email" \
    '"test@example.com"'

run_env_test "JACKS_NIX_USERNAME override" \
    'JACKS_NIX_USERNAME="testuser"' \
    "username" \
    '"testuser"'

run_env_test "JACKS_NIX_ZSH_THEME override" \
    'JACKS_NIX_ZSH_THEME="robbyrussell"' \
    "zshTheme" \
    '"robbyrussell"'

# Test boolean environment variables - test both true and false for variables with different defaults
run_env_test "JACKS_NIX_ENABLE_GIT=false (default true)" \
    'JACKS_NIX_ENABLE_GIT="false"' \
    "enableGit" \
    'false'

run_env_test "JACKS_NIX_ENABLE_ZSH=false (default true)" \
    'JACKS_NIX_ENABLE_ZSH="false"' \
    "enableZsh" \
    'false'

run_env_test "JACKS_NIX_ENABLE_NVIM=false (default true)" \
    'JACKS_NIX_ENABLE_NVIM="false"' \
    "enableNvim" \
    'false'

run_env_test "JACKS_NIX_ENABLE_PYTHON=true (default false)" \
    'JACKS_NIX_ENABLE_PYTHON="true"' \
    "enablePython" \
    'true'

run_env_test "JACKS_NIX_ENABLE_NODE=true (default false)" \
    'JACKS_NIX_ENABLE_NODE="true"' \
    "enableNode" \
    'true'

run_env_test "JACKS_NIX_ENABLE_JAVA=true (default false)" \
    'JACKS_NIX_ENABLE_JAVA="true"' \
    "enableJava" \
    'true'

run_env_test "JACKS_NIX_ENABLE_RUBY=true (default false)" \
    'JACKS_NIX_ENABLE_RUBY="true"' \
    "enableRuby" \
    'true'

run_env_test "JACKS_NIX_ENABLE_BUN=true (default false)" \
    'JACKS_NIX_ENABLE_BUN="true"' \
    "enableBun" \
    'true'

run_env_test "JACKS_NIX_ENABLE_ASDF=true (default false)" \
    'JACKS_NIX_ENABLE_ASDF="true"' \
    "enableAsdf" \
    'true'

# Test boolean value variations (1, yes should also work as true)
run_env_test "JACKS_NIX_ENABLE_PYTHON=1 (alternative true)" \
    'JACKS_NIX_ENABLE_PYTHON="1"' \
    "enablePython" \
    'true'

run_env_test "JACKS_NIX_ENABLE_NODE=yes (alternative true)" \
    'JACKS_NIX_ENABLE_NODE="yes"' \
    "enableNode" \
    'true'

run_env_test "JACKS_NIX_MAC_NIXBLD_USER_ID=5123 (default 300)" \
    'JACKS_NIX_MAC_NIXBLD_USER_ID="5123"' \
    "mac.nixbldUserId" \
    5123

run_env_test "JACKS_NIX_MAC_NIXBLD_GROUP_ID=5123 (default 350)" \
    'JACKS_NIX_MAC_NIXBLD_GROUP_ID="5123"' \
    "mac.nixbldGroupId" \
    5123

# Comprehensive test - multiple environment variables at once
print_status "INFO" "Testing: Multiple environment variables simultaneously"
multi_env_command='JACKS_NIX_GIT_NAME="Multi Test" JACKS_NIX_GIT_EMAIL="multi@test.com" JACKS_NIX_ENABLE_PYTHON="true" JACKS_NIX_ENABLE_BUN="true" JACKS_NIX_ENABLE_GIT="false" nix eval --impure --no-write-lock-file --expr '"'"'
let
  flake = builtins.getFlake (toString ./.);
  config = flake.homeConfigurations.linux-x64.config.jacks-nix;
in {
  gitName = config.git.name;
  gitEmail = config.git.email;
  enablePython = config.enablePython;
  enableBun = config.enableBun;
  enableGit = config.enableGit;
}'"'"''

if multi_result=$(eval "$multi_env_command" 2>>"$LOG_FILE"); then
    expected_multi='{ enableBun = true; enableGit = false; enablePython = true; gitEmail = "multi@test.com"; gitName = "Multi Test"; }'
    if [ "$multi_result" = "$expected_multi" ]; then
        print_status "SUCCESS" "Multiple environment variables test passed"
    else
        print_status "ERROR" "Multiple environment variables test failed"
        echo "Multi-env command: $multi_env_command" >> "$LOG_FILE"
        echo "Expected: $expected_multi" >> "$LOG_FILE"
        echo "Got: $multi_result" >> "$LOG_FILE"
    fi
else
    print_status "ERROR" "Multiple environment variables test failed to execute"
    echo "$multi_env_command" >> "$LOG_FILE"
fi

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

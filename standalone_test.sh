#!/bin/bash

# Standalone Test Script for Alias Manager
# This tests am.sh without requiring installation
# Usage: ./test_am_standalone.sh [path_to_am.sh]

# Test configuration
TEST_DIR="/tmp/am_test_$$"
export ALIASES_FILE="$TEST_DIR/aliases"
export FUNCTIONS_FILE="$TEST_DIR/functions"
PASSED=0
FAILED=0
TOTAL=0

# Colors for output
if [[ -t 1 ]] && [[ -n "$TERM" ]] && [[ "$TERM" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    NC=''
fi

# Find and source the am script
AM_SCRIPT="${1:-./am.sh}"
if [[ ! -f "$AM_SCRIPT" ]]; then
    # Try other common names
    for name in am am.sh alias_manager.sh; do
        if [[ -f "./$name" ]]; then
            AM_SCRIPT="./$name"
            break
        fi
    done
fi

if [[ ! -f "$AM_SCRIPT" ]]; then
    echo -e "${RED}Error: Cannot find am script${NC}"
    echo "Usage: $0 [path_to_am.sh]"
    echo "Or place am.sh in the current directory"
    exit 1
fi

echo -e "${CYAN}=== Alias Manager Test Suite ===${NC}"
echo "Testing script: $AM_SCRIPT"
echo "Test directory: $TEST_DIR"
echo ""

# Source the script
source "$AM_SCRIPT"

# Verify am function is loaded
if ! type -t am >/dev/null 2>&1; then
    echo -e "${RED}Error: am function not loaded from $AM_SCRIPT${NC}"
    exit 1
fi

# Setup test environment to avoid conflicts
setup_test() {
    rm -rf "$TEST_DIR"
    mkdir -p "$TEST_DIR"
    # Ensure we're using the function 'am' not any system alias
    unalias am 2>/dev/null || true
}

cleanup_test() {
    rm -rf "$TEST_DIR"
}

# Simple assertion functions
assert() {
    local test_name="$1"
    local condition="$2"
    
    ((TOTAL++))
    if eval "$condition"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        ((FAILED++))
    fi
}

assert_file_contains() {
    local file="$1"
    local content="$2"
    local test_name="$3"
    
    ((TOTAL++))
    if [[ -f "$file" ]] && grep -q "$content" "$file"; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        if [[ ! -f "$file" ]]; then
            echo "  File not found: $file"
        else
            echo "  Content not found: $content"
        fi
        ((FAILED++))
    fi
}

assert_output_contains() {
    local output="$1"
    local expected="$2"
    local test_name="$3"
    
    ((TOTAL++))
    if [[ "$output" == *"$expected"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        ((PASSED++))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected to find: $expected"
        ((FAILED++))
    fi
}

# Test 1: Basic Help
echo -e "${BLUE}Test 1: Basic Commands${NC}"
setup_test

output=$(am help 2>&1)
assert_output_contains "$output" "Alias Manager" "Help command works"

output=$(am --help 2>&1)
assert_output_contains "$output" "Usage:" "Help flag works"

# Test 2: Add Alias
echo -e "\n${BLUE}Test 2: Add Alias${NC}"
setup_test

# Add simple alias
am add -a mytest 'echo test' >/dev/null 2>&1
assert_file_contains "$ALIASES_FILE" "alias mytest='echo test'" "Simple alias added"

# Add alias with quotes
am add -a quotealias "echo 'hello world'" >/dev/null 2>&1
assert_file_contains "$ALIASES_FILE" "alias quotealias=" "Alias with quotes added"

# Test invalid name
output=$(am add -a '123invalid' 'echo test' 2>&1)
assert_output_contains "$output" "Invalid name" "Invalid alias name rejected"

# Test 3: Add Function
echo -e "\n${BLUE}Test 3: Add Function${NC}"
setup_test

# Add simple function
am add -f greet 'echo "Hello, $1"' >/dev/null 2>&1
assert_file_contains "$FUNCTIONS_FILE" "function greet()" "Simple function added"
assert_file_contains "$FUNCTIONS_FILE" 'echo "Hello, $1"' "Function body saved correctly"

# Test 4: List
echo -e "\n${BLUE}Test 4: List Commands${NC}"
setup_test

# Create test data
echo "alias ll='ls -la'" > "$ALIASES_FILE"
echo "alias gs='git status'" >> "$ALIASES_FILE"
echo 'function hello() { echo "Hi"; }' > "$FUNCTIONS_FILE"

# Test list all
output=$(am list 2>&1)
assert_output_contains "$output" "ll" "List shows aliases"
assert_output_contains "$output" "hello" "List shows functions"

# Test list only aliases
output=$(am list -a 2>&1)
assert_output_contains "$output" "gs" "List -a shows aliases"

# Test list with commands
output=$(am list -a -c 2>&1)
assert_output_contains "$output" "ls -la" "List -c shows commands"

# Test search specific
output=$(am list ll 2>&1)
assert_output_contains "$output" "ll" "Search finds specific alias"

# Test 5: Remove
echo -e "\n${BLUE}Test 5: Remove Commands${NC}"
setup_test

# Create test entries
echo "alias temp='echo temp'" > "$ALIASES_FILE"
echo 'function temp() { echo "temp func"; }' > "$FUNCTIONS_FILE"

# Remove with force flag
am rm --force -a temp >/dev/null 2>&1
if [[ ! -f "$ALIASES_FILE" ]] || ! grep -q 'alias temp=' "$ALIASES_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Alias removed with --force"
    ((PASSED++))
    ((TOTAL++))
else
    echo -e "${RED}✗${NC} Alias removed with --force"
    ((FAILED++))
    ((TOTAL++))
fi

# Test 6: Audit
echo -e "\n${BLUE}Test 6: Audit${NC}"
setup_test

# Create problematic entries
echo "alias ls='ls --color'" > "$ALIASES_FILE"
echo "alias duplicate='echo dup'" >> "$ALIASES_FILE"
echo "alias 123bad='echo bad'" >> "$ALIASES_FILE"
echo 'function duplicate() { echo "dup func"; }' > "$FUNCTIONS_FILE"

output=$(am audit 2>&1)
assert_output_contains "$output" "Duplicate name" "Audit detects duplicates"
assert_output_contains "$output" "Invalid alias name" "Audit detects invalid names"

# Test 7: Edge Cases
echo -e "\n${BLUE}Test 7: Edge Cases${NC}"
setup_test

# Empty name
output=$(am add 2>&1)
assert_output_contains "$output" "Name is required" "Handles missing name"

# Nonexistent entry
output=$(am rm nonexistent 2>&1)
assert_output_contains "$output" "No alias or function" "Handles nonexistent entries"

# Cleanup and summary
cleanup_test

echo -e "\n${CYAN}=== Test Summary ===${NC}"
echo "Total:  $TOTAL"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"

if [[ $FAILED -eq 0 ]]; then
    echo -e "\n${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}Some tests failed${NC}"
    exit 1
fi
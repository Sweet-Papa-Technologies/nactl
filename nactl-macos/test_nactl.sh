#!/bin/bash
# nactl macOS Test Script
# Runs safe commands automatically, echoes disruptive commands for manual testing

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Path to nactl binary
NACTL="${NACTL_PATH:-.build/debug/nactl}"

# Check if binary exists
if [ ! -f "$NACTL" ]; then
    echo -e "${RED}Error: nactl binary not found at $NACTL${NC}"
    echo "Build first with: swift build"
    echo "Or set NACTL_PATH environment variable"
    exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  nactl macOS Test Suite${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "Binary: ${GREEN}$NACTL${NC}"
echo ""

# Track test results
PASSED=0
FAILED=0

run_test() {
    local name="$1"
    local cmd="$2"

    echo -e "${YELLOW}Test: $name${NC}"
    echo -e "  Command: $NACTL $cmd"

    if eval "$NACTL $cmd" > /dev/null 2>&1; then
        echo -e "  Result: ${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        local exit_code=$?
        echo -e "  Result: ${RED}FAILED (exit code: $exit_code)${NC}"
        ((FAILED++))
    fi
    echo ""
}

run_test_with_output() {
    local name="$1"
    local cmd="$2"

    echo -e "${YELLOW}Test: $name${NC}"
    echo -e "  Command: $NACTL $cmd"
    echo "  Output:"

    if eval "$NACTL $cmd" 2>&1 | sed 's/^/    /'; then
        echo -e "  Result: ${GREEN}PASSED${NC}"
        ((PASSED++))
    else
        local exit_code=$?
        echo -e "  Result: ${RED}FAILED (exit code: $exit_code)${NC}"
        ((FAILED++))
    fi
    echo ""
}

echo_manual_test() {
    local name="$1"
    local cmd="$2"
    local note="$3"

    echo -e "${YELLOW}Manual Test: $name${NC}"
    echo -e "  ${RED}NOTE: $note${NC}"
    echo -e "  Command to run: ${GREEN}sudo $NACTL $cmd${NC}"
    echo ""
}

# ============================================
# SAFE TESTS - Run automatically
# ============================================

echo -e "${BLUE}--- SAFE TESTS (Automatic) ---${NC}"
echo ""

# Version and help
run_test "Version" "--version"
run_test "Help" "--help"

# Status command
run_test "Status (human)" "status"
run_test "Status (JSON)" "status --json"
run_test "Status (pretty JSON)" "status --json --pretty"

# Ping command
run_test "Ping google.com" "ping google.com --count 2"
run_test "Ping (JSON)" "ping 8.8.8.8 --count 2 --json"
run_test "Ping localhost" "ping 127.0.0.1 --count 1"

# Trace command (limited hops for speed)
run_test "Trace (short)" "trace google.com --max-hops 3"
run_test "Trace (JSON)" "trace 8.8.8.8 --max-hops 3 --json"
run_test "Trace (with timeout)" "trace google.com --max-hops 3 --timeout 15000"

# Wi-Fi scan (requires Location Services)
echo -e "${YELLOW}Test: Wi-Fi Scan${NC}"
echo "  Note: Requires Location Services permission"
echo -e "  Command: $NACTL wifi scan"
if $NACTL wifi scan > /dev/null 2>&1; then
    echo -e "  Result: ${GREEN}PASSED${NC}"
    ((PASSED++))
else
    exit_code=$?
    if [ $exit_code -eq 7 ]; then
        echo -e "  Result: ${YELLOW}SKIPPED (Location Services denied - exit code 7)${NC}"
    else
        echo -e "  Result: ${RED}FAILED (exit code: $exit_code)${NC}"
        ((FAILED++))
    fi
fi
echo ""

run_test "Wi-Fi Scan (JSON)" "wifi scan --json"

# Proxy get
run_test "Proxy Get" "proxy get"
run_test "Proxy Get (JSON)" "proxy get --json"

# DNS subcommands help
run_test "DNS Help" "dns --help"
run_test "Stack Help" "stack --help"
run_test "Wi-Fi Help" "wifi --help"
run_test "Proxy Help" "proxy --help"

# ============================================
# DISRUPTIVE TESTS - Echo for manual execution
# ============================================

echo -e "${BLUE}--- DISRUPTIVE TESTS (Manual) ---${NC}"
echo -e "${RED}These commands may temporarily disrupt network connectivity.${NC}"
echo -e "${RED}Run manually with sudo when ready.${NC}"
echo ""

echo_manual_test "DNS Flush" "dns flush" "Clears DNS cache - safe but requires sudo"
echo_manual_test "DNS Set Custom" "dns set 1.1.1.1 1.0.0.1" "Changes DNS servers - will affect name resolution"
echo_manual_test "DNS Reset" "dns reset" "Resets DNS to DHCP - run after DNS Set test"
echo_manual_test "Wi-Fi Forget" "wifi forget 'TestNetwork'" "Removes saved network - replace 'TestNetwork' with actual SSID"
echo_manual_test "Stack Reset (Soft)" "stack reset --level soft" "Restarts network adapter - temporary connectivity loss"
echo_manual_test "Stack Reset (Hard)" "stack reset --level hard" "Removes network config files - REQUIRES REBOOT"
echo_manual_test "Proxy Clear" "proxy clear" "Clears all proxy settings - only if proxies are configured"

# ============================================
# JSON Output Validation
# ============================================

echo -e "${BLUE}--- JSON OUTPUT VALIDATION ---${NC}"
echo ""

echo -e "${YELLOW}Test: Validate JSON output structure${NC}"
json_output=$($NACTL status --json 2>/dev/null)
if echo "$json_output" | python3 -c "import sys, json; d=json.load(sys.stdin); assert 'success' in d" 2>/dev/null; then
    echo -e "  JSON structure: ${GREEN}VALID${NC}"
    ((PASSED++))
else
    echo -e "  JSON structure: ${RED}INVALID${NC}"
    ((FAILED++))
fi
echo ""

# ============================================
# Summary
# ============================================

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "  Passed: ${GREEN}$PASSED${NC}"
echo -e "  Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All automatic tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Check output above.${NC}"
    exit 1
fi

#!/bin/bash
# Monobash test runner - actually tests the monobash shell
# Usage: bash run_monobash_tests.sh [path-to-monobash]

SHELL="${1:-./zig-out/bin/monobash}"
PASS=0
FAIL=0

pass() { echo "✓ PASS: $1"; ((PASS++)); }
fail() { echo "✗ FAIL: $1 (expected exit=$2 got=$3)"; ((FAIL++)); }

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$name"
    else
        fail "$name" "$expected" "$actual"
    fi
}

check_exit() {
    local name="$1" expected="$2"
    "$SHELL" -c "exit $expected" 2>/dev/null
    local got=$?
    if [[ $got -eq $expected ]]; then
        pass "$name"
    else
        fail "$name" "$expected" "$got"
    fi
}

check_output() {
    local name="$1" expected="$2" cmd="$3"
    local got=$("$SHELL" -c "$cmd" 2>/dev/null)
    if [[ "$got" == "$expected" ]]; then
        pass "$name"
    else
        echo "✗ FAIL: $name"
        echo "  Expected output: '$expected'"
        echo "  Got output:      '$got'"
        ((FAIL++))
    fi
}

echo "========================================"
echo "Monobash Test Suite"
echo "Testing: $SHELL"
echo "========================================"

echo ""
echo "--- 1. Basic Exit Codes ---"
"$SHELL" -c "true" 2>/dev/null; check "true exits 0" 0 $?
"$SHELL" -c "false" 2>/dev/null; check "false exits 1" 1 $?
"$SHELL" -c "exit 42" 2>/dev/null; check "exit 42" 42 $?
"$SHELL" -c "exit 0" 2>/dev/null; check "exit 0" 0 $?
"$SHELL" -c "exit 255" 2>/dev/null; check "exit 255" 255 $?
"$SHELL" -c "nonexistent_cmd_xyz" 2>/dev/null; check "nonexistent returns 127" 127 $?

echo ""
echo "--- 2. echo ---"
check_output "echo hello" "hello" "echo hello"
check_output "echo hello world" "hello world" "echo hello world"
check_output "echo 'hello   world'" "hello   world" "echo 'hello   world'"
check_output "echo with spaces" "a b c" "echo a b c"
check_output "echo \$HOME" "$HOME" 'echo $HOME'
check_output "echo x\$HOME y" "x${HOME} y" 'echo x$HOME y'

echo ""
echo "--- 3. true/false ---"
"$SHELL" -c "true" 2>/dev/null; check "true" 0 $?
"$SHELL" -c "false" 2>/dev/null; check "false" 1 $?

echo ""
echo "--- 4. cd/pwd ---"
orig_dir=$(pwd)
tmp_dir=$("$SHELL" -c "cd /tmp && pwd" 2>/dev/null)
check "cd /tmp && pwd" "/tmp" "$tmp_dir"

echo ""
echo "--- 5. Variable Assignment ---"
"$SHELL" -c "x=5 exit 0" 2>/dev/null; check "simple var assign exit" 0 $?

echo ""
echo "--- 6. Control Flow (if/elif/else) ---"
check_output "if true" "pass" "if true; then echo pass; fi"
check_output "if false with else" "pass" "if false; then echo fail; else echo pass; fi"
check_output "if false, elif true" "pass" "if false; then echo fail; elif true; then echo pass; else echo fail; fi"
check_output "if false, elif false, else" "else_ok" "if false; then echo fail; elif false; then echo fail; else echo else_ok; fi"

echo ""
echo "========================================"
echo "Results: $PASS passed, $FAIL failed"
echo "========================================"

exit $FAIL

#!/usr/bin/env bash
# ==============================================================================
# Applet comparison test runner
# Tests each monobash NOEXEC applet against the system binary.
#
# Usage:
#   bash tests/applet-test.sh                    # run all applet tests
#   bash tests/applet-test.sh cat                # run tests for specific applet
#   bash tests/applet-test.sh --pod              # run inside K8s pod
#   SHELL=./zig-out/bin/monobash bash tests/applet-test.sh
# ==============================================================================

SHELL="${SHELL:-./zig-out/bin/monobash}"
TEST_DIR="$(cd "$(dirname "$0")" && pwd)/applets"
POD="${POD:-monobash-tester}"
PASS=0
FAIL=0
TOTAL=0
SKIP=0

[[ "$1" == "--pod" ]] && { POD_MODE=true; shift; } || POD_MODE=false
FILTER="$1"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); ((TOTAL++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); ((TOTAL++)); }
skip() { echo -e "  ${YELLOW}○${NC} $1"; ((SKIP++)); ((TOTAL++)); }

run_in_pod() {
    kubectl exec "$POD" -- /bin/bash -c "$1" 2>/dev/null
}

run_test() {
    local applet="$1" cmd="$2" expected="$3"
    local app_out app_exit sys_out sys_exit

    if $POD_MODE; then
        app_out=$(run_in_pod "SHELL=/mnt/monobash/zig-out/bin/monobash /mnt/monobash/zig-out/bin/monobash -c \"$cmd\" 2>/dev/null; echo \"EXIT=\$?\"")
        sys_out=$(run_in_pod "/usr/bin/$applet $cmd 2>/dev/null; echo \"EXIT=\$?\"")
    else
        app_out=$("$SHELL" -c "$cmd" 2>/dev/null; echo "EXIT=$?")
        sys_out=$(/usr/bin/"$applet" $cmd 2>/dev/null; echo "EXIT=$?")
    fi

    local app_stdout=$(echo "$app_out" | sed '$d')
    local app_exit=$(echo "$app_out" | grep "EXIT=" | sed 's/EXIT=//')
    local sys_stdout=$(echo "$sys_out" | sed '$d')
    local sys_exit=$(echo "$sys_out" | grep "EXIT=" | sed 's/EXIT=//')

    if [[ "$app_stdout" == "$sys_stdout" && "$app_exit" == "$sys_exit" ]]; then
        ok "$applet: $expected"
        return 0
    else
        local detail=""
        [[ "$app_stdout" != "$sys_stdout" ]] && detail="out: sys='$sys_stdout' mono='$app_stdout'"
        [[ "$app_exit" != "$sys_exit" ]] && detail="$detail exit: sys=$sys_exit mono=$app_exit"
        fail "$applet: $expected [$detail]"
        return 1
    fi
}

# Parse a test file and run each test
run_file() {
    local file="$1"
    local basename=$(basename "$file" .tests)
    [[ -n "$FILTER" && "$basename" != *"$FILTER"* ]] && return
    echo -e "\n${CYAN}═══ ${basename} ═══${NC}"

    local applet="" cmd="" expected=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^@(.*) ]]; then
            # Run previous test if we have one
            if [[ -n "$applet" && -n "$cmd" ]]; then
                run_test "$applet" "$cmd" "$expected"
            fi
            # Parse: @APPLET description
            local rest="${BASH_REMATCH[1]}"
            applet="${rest%% *}"
            expected="${rest#* }"
            cmd=""
        elif [[ -n "$applet" && -n "$line" && ! "$line" =~ ^# ]]; then
            [[ -z "$cmd" ]] && cmd="$line" || cmd="$cmd"$'\n'"$line"
        fi
    done < "$file"
    # Last test
    if [[ -n "$applet" && -n "$cmd" ]]; then
        run_test "$applet" "$cmd" "$expected"
    fi
}

echo "========================================"
echo "Monobash Applet Test Suite"
echo "Monobash: $SHELL"
echo "Mode: $($POD_MODE && echo 'pod' || echo 'local')"
echo "========================================"

for f in "$TEST_DIR"/*.tests; do
    [[ -f "$f" ]] || continue
    run_file "$f"
done

echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  RESULTS${NC}"
echo -e "${CYAN}========================================${NC}"
echo "  Total  : $TOTAL"
echo -e "  Passed : ${GREEN}$PASS${NC}"
echo -e "  Failed : ${RED}$FAIL${NC}"
[[ $SKIP -gt 0 ]] && echo -e "  Skipped: ${YELLOW}$SKIP${NC}"
echo ""

exit $FAIL

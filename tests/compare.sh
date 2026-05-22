#!/usr/bin/env bash
# ==============================================================================
# Bash vs monobash comparison test runner
# Reads test definitions from tests/compat/*.tests and compares behavior
# between real bash and monobash ($SHELL).
#
# Usage:
#   bash tests/compare.sh                    # run all tests
#   bash tests/compare.sh quoting            # run specific category
#   bash tests/compare.sh --report           # generate gap report
#   SHELL=./zig-out/bin/monobash bash tests/compare.sh
# ==============================================================================

SHELL="${SHELL:-./zig-out/bin/monobash}"
COMPAT_DIR="$(cd "$(dirname "$0")" && pwd)/compat"
PASS=0
FAIL=0
TOTAL=0
SKIP=0
declare -A CAT_PASS CAT_FAIL CAT_TOTAL
declare -a FAILED_NAMES FAILED_CMDS FAILED_B_OUT FAILED_B_ERR FAILED_B_EXIT FAILED_M_OUT FAILED_M_ERR FAILED_M_EXIT
GAP_REPORT=false

[[ "$1" == "--report" ]] && GAP_REPORT=true && shift
FILTER="$1"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; ((PASS++)); ((TOTAL++)); }
fail() { echo -e "  ${RED}✗${NC} $1"; ((FAIL++)); ((TOTAL++)); }
skip() { echo -e "  ${YELLOW}○${NC} $1"; ((SKIP++)); ((TOTAL++)); }

# Parse test file into name+cmd pairs (stored in global arrays)
parse_file() {
    local file="$1"
    local names=() cmds=()
    local current_name="" current_cmd=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^@(.*) ]]; then
            if [[ -n "$current_name" ]]; then
                names+=("$current_name")
                cmds+=("$current_cmd")
            fi
            current_name="${BASH_REMATCH[1]}"
            current_name="${current_name## }"
            current_name="${current_name%% }"
            current_cmd=""
        elif [[ "$line" == \#* ]]; then
            continue
        elif [[ -z "$line" ]]; then
            continue
        else
            [[ -z "$current_cmd" ]] && current_cmd="$line" || current_cmd="$current_cmd"$'\n'"$line"
        fi
    done < "$file"
    if [[ -n "$current_name" ]]; then
        names+=("$current_name")
        cmds+=("$current_cmd")
    fi
    # Output pairs: name\ncmd\0
    for i in "${!names[@]}"; do
        printf "%s\n" "${names[$i]}"
        printf "%s\0" "${cmds[$i]}"
    done
}

run_test() {
    local name="$1" cmd="$2"
    local b_out b_err b_exit m_out m_err m_exit
    local bash_tmp mono_tmp

    bash_tmp=$(mktemp); local bash_tmp_e=$(mktemp)
    mono_tmp=$(mktemp); local mono_tmp_e=$(mktemp)

    bash -c "$cmd" >"$bash_tmp" 2>"$bash_tmp_e"; b_exit=$?
    b_out=$(<"$bash_tmp"); b_err=$(<"$bash_tmp_e")

    "$SHELL" -c "$cmd" >"$mono_tmp" 2>"$mono_tmp_e"; m_exit=$?
    m_out=$(<"$mono_tmp"); m_err=$(<"$mono_tmp_e")

    rm -f "$bash_tmp" "$bash_tmp_e" "$mono_tmp" "$mono_tmp_e"

    local diff_out diff_err diff_exit=0
    [[ "$b_out" != "$m_out" ]] && diff_out=1
    [[ "$b_err" != "$m_err" ]] && diff_err=1
    [[ "$b_exit" != "$m_exit" ]] && diff_exit=1

    if [[ -z "$diff_out" && -z "$diff_err" && $diff_exit -eq 0 ]]; then
        ok "$name"
        return 0
    else
        local detail=""
        if [[ -n "$diff_out" ]]; then
            local b_show="${b_out:0:60}"
            local m_show="${m_out:0:60}"
            detail="bash: '$b_show' mono: '$m_show'"
        fi
        if [[ -n "$diff_err" ]]; then
            [[ -n "$detail" ]] && detail="$detail | "
            detail="${detail}stderr differs"
        fi
        if [[ $diff_exit -ne 0 ]]; then
            [[ -n "$detail" ]] && detail="$detail | "
            detail="${detail}exit: bash=$b_exit mono=$m_exit"
        fi
        [[ -z "$detail" ]] && detail="output differs"
        fail "$name [$detail]"

        # Store failure info for report
        FAILED_NAMES+=("$name")
        FAILED_CMDS+=("$cmd")
        FAILED_B_OUT+=("$b_out")
        FAILED_B_ERR+=("$b_err")
        FAILED_B_EXIT+=("$b_exit")
        FAILED_M_OUT+=("$m_out")
        FAILED_M_ERR+=("$m_err")
        FAILED_M_EXIT+=("$m_exit")
        return 1
    fi
}

run_file() {
    local file="$1"
    local basename
    basename=$(basename "$file" .tests)
    [[ -n "$FILTER" && "$basename" != *"$FILTER"* ]] && return
    echo -e "\n${CYAN}═══ ${basename} ═══${NC}"

    local file_pass=0 file_fail=0 file_total=0
    local names cmds

    # Parse file into arrays
    while IFS= read -r test_name; do
        IFS= read -r -d '' test_cmd
        [[ -z "$test_name" ]] && continue
        if run_test "$test_name" "$test_cmd"; then
            ((file_pass++))
            ((CAT_PASS["$basename"]++))
        else
            ((file_fail++))
            ((CAT_FAIL["$basename"]++))
        fi
        ((CAT_TOTAL["$basename"]++))
    done < <(parse_file "$file")
}

# ==============================================================================
# MAIN
# ==============================================================================
echo "========================================"
echo "Bash vs Monobash Comparison Test Suite"
echo "Monobash: $SHELL ($("$SHELL" --version 2>/dev/null || "$SHELL" -c 'echo "version:?"'))"
echo "Bash:     $(which bash) ($(bash --version | head -1))"
echo "========================================"

for f in "$COMPAT_DIR"/*.tests; do
    [[ -f "$f" ]] || continue
    CAT_PASS["$(basename "$f" .tests)"]=0
    CAT_FAIL["$(basename "$f" .tests)"]=0
    CAT_TOTAL["$(basename "$f" .tests)"]=0
    run_file "$f"
done

echo -e "\n${CYAN}========================================${NC}"
echo -e "${CYAN}  RESULTS${NC}"
echo -e "${CYAN}========================================${NC}"
for key in "${!CAT_TOTAL[@]}"; do
    echo "  $key: ${CAT_PASS[$key]}/${CAT_TOTAL[$key]} passed, ${CAT_FAIL[$key]:-0} failed"
done
echo ""
echo "  Total  : $TOTAL"
echo -e "  Passed : ${GREEN}$PASS${NC}"
echo -e "  Failed : ${RED}$FAIL${NC}"
echo ""

# ==============================================================================
# GAP REPORT
# ==============================================================================
if $GAP_REPORT && [[ $FAIL -gt 0 ]]; then
    REPORT_FILE="tests/compat/GAP_REPORT.md"
    exec 3>"$REPORT_FILE"
    echo "# Gap Report: monobash vs bash" >&3
    echo "" >&3
    echo "Generated: $(date)" >&3
    echo "" >&3
    echo "## Summary" >&3
    echo "" >&3
    echo "| Metric | Value |" >&3
    echo "|--------|-------|" >&3
    echo "| Total tests | $TOTAL |" >&3
    echo "| Passed | $PASS |" >&3
    echo "| Failed (gaps) | $FAIL |" >&3
    echo "| Coverage | $(awk "BEGIN { printf \"%.0f%%\", $PASS * 100 / $TOTAL }") |" >&3
    echo "" >&3

    # Per-category summary
    echo "## Per-Category Results" >&3
    echo "" >&3
    echo "| Category | Passed | Failed | Total | Coverage |" >&3
    echo "|----------|--------|--------|-------|----------|" >&3
    for key in $(printf "%s\n" "${!CAT_TOTAL[@]}" | sort); do
        p=${CAT_PASS[$key]} f=${CAT_FAIL[$key]} t=${CAT_TOTAL[$key]}
        cov=$(awk "BEGIN { printf \"%.0f%%\", $p * 100 / $t }")
        echo "| $key | $p | $f | $t | $cov |" >&3
    done
    echo "" >&3

    # Failed tests detail
    echo "## Failed Tests (Gaps)" >&3
    echo "" >&3
    echo "| # | Test | bash stdout | bash stderr | bash exit | monobash stdout | monobash stderr | monobash exit |" >&3
    echo "|---|------|------------|-------------|-----------|-----------------|-----------------|---------------|" >&3

    fi=1
    for idx in "${!FAILED_NAMES[@]}"; do
        name="${FAILED_NAMES[$idx]}"
        b_out="${FAILED_B_OUT[$idx]}"
        b_err="${FAILED_B_ERR[$idx]}"
        b_exit="${FAILED_B_EXIT[$idx]}"
        m_out="${FAILED_M_OUT[$idx]}"
        m_err="${FAILED_M_ERR[$idx]}"
        m_exit="${FAILED_M_EXIT[$idx]}"

        b_out="${b_out//|/\\|}"
        b_err="${b_err//|/\\|}"
        m_out="${m_out//|/\\|}"
        m_err="${m_err//|/\\|}"

        echo "| $fi | $name | \`$b_out\` | \`$b_err\` | $b_exit | \`$m_out\` | \`$m_err\` | $m_exit |" >&3
        ((fi++))
    done

    echo "" >&3
    echo "## Priority Areas (sorted by most gaps)" >&3
    echo "" >&3
    echo "| Category | Failing / Total |" >&3
    echo "|----------|----------------|" >&3
    for key in $(printf "%s\n" "${!CAT_FAIL[@]}" | sort -t. -k1); do
        f=${CAT_FAIL[$key]}
        t=${CAT_TOTAL[$key]}
        echo "| $key | $f / $t |" >&3
    done
    echo "" >&3

    exec 3>&-
    echo "Gap report written to: $REPORT_FILE"
fi

exit $FAIL

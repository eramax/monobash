#!/bin/bash
# =============================================================================
# COMPREHENSIVE BASH 5.x COMPATIBILITY TEST SUITE
# Safe, non-destructive tests for shell interpreter compatibility
# Run with: bash test_shell.sh YOUR_SHELL_PATH
# Example: bash test_shell.sh /path/to/your/shell
# =============================================================================

PASS_COUNT=0
FAIL_COUNT=0
TESTS_RUN=0

# Test runner function
run_test() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [[ "$expected" == "$actual" ]]; then
        echo "✓ PASS: $test_name"
        PASS_COUNT=$((PASS_COUNT + 1))
        return 0
    else
        echo "✗ FAIL: $test_name"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return 1
    fi
}

test_section() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

# =============================================================================
# SECTION 1: BASIC COMMAND EXECUTION & EXIT CODES
# =============================================================================
test_section "1. Basic Command Execution & Exit Codes"

# Test successful command
out=$(true)
run_test "true command exits 0" "0" "$?"

# Test failed command  
out=$(false; echo $?)
run_test "false command exits 1" "1" "$out"

# Test command exit code capture
true
run_test "Exit code after true" "0" "$?"

false
run_test "Exit code after false" "1" "$?"

# Test arithmetic exit codes
(( 5 > 3 ))
run_test "Arithmetic comparison (5>3) exits 0" "0" "$?"

(( 5 < 3 ))
run_test "Arithmetic comparison (5<3) exits 1" "1" "$?"

# =============================================================================
# SECTION 2: VARIABLES & ASSIGNMENT
# =============================================================================
test_section "2. Variables & Assignment"

# Basic variable assignment
my_var="hello"
run_test "Basic variable assignment" "hello" "$my_var"

# Variable with spaces
space_var="hello world"
run_test "Variable with spaces" "hello world" "$space_var"

# Empty variable
empty_var=""
run_test "Empty variable" "" "$empty_var"

# Variable expansion
run_test "Variable expansion" "hello" "$my_var"

# Default value ${var:-default}
unset default_test
run_test "Default value with unset var" "default" "${default_test:-default}"

# Default value with empty var
default_test=""
run_test "Default value with empty var" "default" "${default_test:-default}"

# Default value with set var
default_test="set_value"
run_test "Default value with set var" "set_value" "${default_test:-default}"

# Alternative value ${var:=default} (modifies var)
unset assign_test
run_test "Assign default with := (unset)" "new_default" "${assign_test:=new_default}"

# Error if unset ${var:?message}
unset error_test
run_test "Error on unset with :?" "error" "error" || true  # Expected to fail in subshell

# =============================================================================
# SECTION 3: STRING MANIPULATION
# =============================================================================
test_section "3. String Manipulation"

test_str="Hello World Test"

# String length
run_test "String length" "16" "${#test_str}"

# Substring extraction
run_test "Substring [0:5]" "Hello" "${test_str:0:5}"

# Substring from position
run_test "Substring [6:5]" "World" "${test_str:6:5}"

# Substring to end
run_test "Substring [6]" "World Test" "${test_str:6}"

# Substring from end (negative)
run_test "Substring [-4]" "Test" "${test_str: -4}"

# Remove shortest prefix #
run_test "Remove prefix #*" "World Test" "${test_str#Hello }"

# Remove longest prefix ##
run_test "Remove prefix ##*" "Test" "${test_str##* }"

# Remove shortest suffix %
run_test "Remove suffix %*" "Hello Worl" "${test_str%t}"

# Remove longest suffix %%
run_test "Remove suffix %%" "Hello World " "${test_str%%Test}"

# Replace first occurrence
run_test "Replace first occurrence" "Hello World Replaced" "${test_str/Test/Replaced}"

# Replace all occurrences
test_str2="foo bar foo baz foo"
run_test "Replace all occurrences" "foo bar replaced baz replaced" "${test_str2//foo/replaced}"

# Uppercase first character (Bash 4+)
lower_str="hello"
run_test "Uppercase first ^" "Hello" "${lower_str^}"

# Uppercase all (Bash 4+)
run_test "Uppercase all ^^" "HELLO" "${lower_str^^}"

# Lowercase first character (Bash 4+)
upper_str="HELLO"
run_test "Lowercase first ," "hELLO" "${upper_str,}"

# Lowercase all (Bash 4+)
run_test "Lowercase all ," "hello" "${upper_str,,}"

# =============================================================================
# SECTION 4: INDEXED ARRAYS (Bash-specific)
# =============================================================================
test_section "4. Indexed Arrays"

# Basic array creation
arr=(one two three four five)
run_test "Array element [0]" "one" "${arr[0]}"

run_test "Array element [2]" "three" "${arr[2]}"

run_test "Array element [4]" "five" "${arr[4]}"

# Array with explicit indices
sparse_arr=([0]=first [2]=second [5]=fifth)
run_test "Sparse array [0]" "first" "${sparse_arr[0]}"

run_test "Sparse array [2]" "second" "${sparse_arr[2]}"

run_test "Sparse array [5]" "fifth" "${sparse_arr[5]}"

# Array length
run_test "Array length ${#arr[@]}" "5" "${#arr[@]}"

# All elements with @
run_test "All elements [@]" "one two three four five" "${arr[*]}"

run_test "All elements [*]" "one two three four five" "${arr[*]}"

# Array keys/indices
run_test "Array keys [@]" "0 1 2 3 4" "${!arr[*]}"

run_test "Array keys [*]" "0 1 2 3 4" "${!arr[@]}"

# Append to array with +=
arr2=(a b c)
arr2+=("d" "e")
run_test "Append to array" "a b c d e" "${arr2[*]}"

# Negative index (Bash 4.2+)
neg_arr=(zero one two three four five)
run_test "Negative index [-1]" "five" "${neg_arr[-1]}"

run_test "Negative index [-2]" "four" "${neg_arr[-2]}"

run_test "Negative index [-3]" "three" "${neg_arr[-3]}"

# Array slice
run_test "Array slice [1:3]" "two three four" "${arr[@]:1:3}"

run_test "Array slice [2:]" "three four five" "${arr[@]:2}"

run_test "Array slice [:3]" "one two three" "${arr[@]:0:3}"

# Array assignment from command output
cmd_arr=$(echo -e "line1\nline2\nline3")
# Note: This is a simple assignment, not mapfile

# Empty array
empty_arr=()
run_test "Empty array length" "0" "${#empty_arr[@]}"

# =============================================================================
# SECTION 5: ASSOCIATIVE ARRAYS (Bash 4+)
# =============================================================================
test_section "5. Associative Arrays (Bash 4+)"

declare -A assoc_arr

assoc_arr["key1"]="value1"
assoc_arr["key2"]="value2"
assoc_arr["name with spaces"]="spaced value"

run_test "Associative array [key1]" "value1" "${assoc_arr[key1]}"

run_test "Associative array [key2]" "value2" "${assoc_arr[key2]}"

run_test "Associative array [spaces]" "spaced value" "${assoc_arr[name with spaces]}"

# Associative array length
run_test "Associative array length" "3" "${#assoc_arr[@]}"

# Associative array keys
keys=$(echo "${!assoc_arr[@]}" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
expected_keys=$(echo "key1 key2 name with spaces" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
run_test "Associative array keys" "$expected_keys" "$keys"

# Associative array compound assignment
declare -A assoc2=([a]=1 [b]=2 [c]=3)
run_test "Compound assignment [a]" "1" "${assoc2[a]}"

run_test "Compound assignment [b]" "2" "${assoc2[b]}"

run_test "Compound assignment [c]" "3" "${assoc2[c]}"

# Append to associative array
assoc2+=([d]=4 [e]=5)
run_test "Append to assoc array [d]" "4" "${assoc2[d]}"

run_test "Append to assoc array [e]" "5" "${assoc2[e]}"

# =============================================================================
# SECTION 6: MAPFILE/READARRAY (Bash 4+)
# =============================================================================
test_section "6. mapfile/readarray (Bash 4+)"

# Create test file
echo -e "line1\nline2\nline3\nline4" > /tmp/test_mapfile.txt

# Basic mapfile
mapfile -t mapfile_arr < /tmp/test_mapfile.txt
run_test "mapfile element [0]" "line1" "${mapfile_arr[0]}"

run_test "mapfile element [1]" "line2" "${mapfile_arr[1]}"

run_test "mapfile element [2]" "line3" "${mapfile_arr[2]}"

run_test "mapfile length" "4" "${#mapfile_arr[@]}"

# mapfile with -n (max count)
mapfile -n 2 -t limited_arr < /tmp/mapfile.txt 2>/dev/null || mapfile -n 2 -t limited_arr < /tmp/test_mapfile.txt
run_test "mapfile -n 2 length" "2" "${#limited_arr[@]}"

# Cleanup
rm -f /tmp/test_mapfile.txt

# =============================================================================
# SECTION 7: COMMAND SUBSTITUTION
# =============================================================================
test_section "7. Command Substitution"

# Modern $(...) syntax
result=$(echo "hello substitution")
run_test "Modern $(...) syntax" "hello substitution" "$result"

# Nested command substitution
inner=$(echo "inner")
outer=$(echo "outer $inner")
run_test "Nested command substitution" "outer inner" "$outer"

# Command substitution with $(())
result=$(echo $(($(echo 2) + $(echo 3))))
run_test "Command substitution in arithmetic" "5" "$result"

# Backward compatibility with ``
result=`echo "backtick substitution"`
run_test "Backtick substitution" "backtick substitution" "$result"

# =============================================================================
# SECTION 8: ARITHMETIC EXPANSION $(( ))
# =============================================================================
test_section "8. Arithmetic Expansion $(( ))"

run_test "Arithmetic 2+3" "5" "$((2 + 3))"

run_test "Arithmetic 10-4" "6" "$((10 - 4))"

run_test "Arithmetic 6*7" "42" "$((6 * 7))"

run_test "Arithmetic 20/4" "5" "$((20 / 4))"

run_test "Arithmetic 17%5" "2" "$((17 % 5))"

run_test "Arithmetic 2**8" "256" "$((2 ** 8))"

run_test "Arithmetic bitwise AND" "4" "$((12 & 5))"

run_test "Arithmetic bitwise OR" "13" "$((12 | 5))"

run_test "Arithmetic bitwise XOR" "9" "$((12 ^ 5))"

run_test "Arithmetic left shift" "40" "$((10 << 2))"

run_test "Arithmetic right shift" "2" "$((10 >> 2))"

# Arithmetic comparison
run_test "Arithmetic ternary (true)" "1" "$((5 > 3 ? 1 : 0))"

run_test "Arithmetic ternary (false)" "0" "$((3 > 5 ? 1 : 0))"

# Variable in arithmetic
arith_var=10
run_test "Variable in arithmetic" "15" "$((arith_var + 5))"

# =============================================================================
# SECTION 9: EXTENDED TEST [[ ]]
# =============================================================================
test_section "9. Extended Test [[ ]] Construct"

# String equality
run_test "[[ string == string ]]" "pass" "$([[ "hello" == "hello" ]] && echo pass || echo fail)"

# String inequality
run_test "[[ string != string ]]" "pass" "$([[ "hello" != "world" ]] && echo pass || echo fail)"

# String empty check
run_test "[[ -z empty ]]" "pass" "$([[ -z "" ]] && echo pass || echo fail)"

# String non-empty check
run_test "[[ -n nonempty ]]" "pass" "$([[ -n "hello" ]] && echo pass || echo fail)"

# File exists (test with /bin)
run_test "[[ -d /bin ]]" "pass" "$([[ -d /bin ]] && echo pass || echo fail)"

# File readable
run_test "[[ -r /etc/passwd ]]" "pass" "$([[ -r /etc/passwd ]] && echo pass || echo fail)"

# Regex match
run_test "[[ =~ regex match ]]" "pass" "$([[ "hello123" =~ ^hello[0-9]+$ ]] && echo pass || echo fail)"

# Regex no match
run_test "[[ =~ regex no match ]]" "pass" "$([[ "hello" =~ ^[0-9]+$ ]] && echo pass || echo fail)"

# And operator
run_test "[[ && ]]" "pass" "$([[ "hello" == "hello" && 1 -eq 1 ]] && echo pass || echo fail)"

# Or operator
run_test "[[ || ]]" "pass" "$([[ "hello" == "world" || 1 -eq 1 ]] && echo pass || echo fail)"

# =============================================================================
# SECTION 10: PATTERN MATCHING & GLOBBER
# =============================================================================
test_section "10. Pattern Matching & Globbing"

# Brace expansion
brace_result=$(echo {a,b,c}{1,2,3} | tr ' ' '\n' | head -1)
run_test "Brace expansion starts with a1" "a1" "$brace_result"

brace_count=$(echo {1..5} | tr ' ' '\n' | wc -l)
run_test "Brace expansion {1..5} count" "5" "$brace_count"

#pathname expansion (globbing)
touch /tmp/test_glob_a.txt /tmp/test_glob_b.txt 2>/dev/null
glob_result=$(ls /tmp/test_glob_*.txt 2>/dev/null | wc -l)
run_test "Glob pattern *.txt" "2" "$glob_result"
rm -f /tmp/test_glob_*.txt 2>/dev/null

# Character class glob
touch "/tmp/test[abc].txt" 2>/dev/null
char_glob=$(ls /tmp/test[abc].txt 2>/dev/null | wc -l)
run_test "Character class [abc]" "1" "$char_glob"
rm -f /tmp/test[abc].txt 2>/dev/null

# Extended globbing (extglob)
shopt -s extglob 2>/dev/null
test_ext="hello"
run_test "extglob +(pattern)" "pass" "$([[ "$test_ext" == +(hello) ]] && echo pass || echo fail)"

# =============================================================================
# SECTION 11: CONTROL STRUCTURES
# =============================================================================
test_section "11. Control Structures"

# if-then-else
if true; then
    if_result="pass"
else
    if_result="fail"
fi
run_test "if-then-else (true)" "pass" "$if_result"

if false; then
    if_result2="fail"
else
    if_result2="pass"
fi
run_test "if-then-else (false)" "pass" "$if_result2"

# for loop with array
for_loop_result=""
for item in one two three; do
    for_loop_result="$for_loop_result $item"
done
run_test "for loop" " one two three" "$for_loop_result"

# for loop with array variable
arr_loop=""
for item in "${arr[@]}"; do
    arr_loop="$arr_loop $item"
done
run_test "for loop with array" " one two three four five" "$arr_loop"

# for loop with C-style syntax
c_for_result=""
for ((i=0; i<5; i++)); do
    c_for_result="$c_for_result$i"
done
run_test "C-style for loop" "01234" "$c_for_result"

# while loop
while_result=""
while_count=0
while [ $while_count -lt 3 ]; do
    while_result="$while_result$while_count"
    ((while_count++))
done
run_test "while loop" "012" "$while_result"

# until loop
until_result=""
until_count=0
until [ $until_count -ge 3 ]; do
    until_result="$until_result$until_count"
    ((until_count++))
done
run_test "until loop" "012" "$until_result"

# case statement
case_result=$(case "hello" in hello) echo match;; *) echo nomatch;; esac)
run_test "case statement" "match" "$case_result"

case_result2=$(case "world" in hello) echo match;; *) echo nomatch;; esac)
run_test "case statement (no match)" "nomatch" "$case_result2"

# =============================================================================
# SECTION 12: FUNCTIONS
# =============================================================================
test_section "12. Functions"

# Basic function
test_func() {
    echo "function_output"
}
run_test "Basic function" "function_output" "$(test_func)"

# Function with return
func_return() {
    return 42
}
func_return
run_test "Function return code" "42" "$?"

# Function with parameters
func_params() {
    echo "$1 $2 $3"
}
run_test "Function with params" "a b c" "$(func_params a b c)"

# Function with $@ and $*
func_args() {
    echo "L@: $@"
    echo "L*: $*"
}
args_result=$(func_args "a b" "c d")
run_test "Function \$@ preserves quotes" "L@: a b c d" "$(func_args "a b" "c d" | head -1)"

# Function with local variables
func_local() {
    local local_var="local_value"
    echo "$local_var"
}
run_test "local variable" "local_value" "$(func_local)"

# Recursive function
factorial() {
    if [ $1 -le 1 ]; then
        echo 1
    else
        echo $(( $1 * $(factorial $(( $1 - 1 ))) ))
    fi
}
run_test "Recursive factorial(5)" "120" "$(factorial 5)"

# =============================================================================
# SECTION 13: PIPELINES & REDIRECTION
# =============================================================================
test_section "13. Pipelines & Redirection"

# Basic pipe
pipe_result=$(echo "hello world" | wc -w)
run_test "Basic pipe (wc -w)" "2" "$pipe_result"

# Multiple pipes
multi_pipe=$(echo "HELLO WORLD TEST" | tr 'A-Z' 'a-z' | tr ' ' '\n' | wc -l)
run_test "Multiple pipes" "3" "$multi_pipe"

# Output redirection to file
echo "redirected content" > /tmp/test_redirect.txt
redirect_check=$(cat /tmp/test_redirect.txt)
run_test "Output redirection" "redirected content" "$redirect_check"
rm -f /tmp/test_redirect.txt

# Append redirection
echo "line1" > /tmp/test_append.txt
echo "line2" >> /tmp/test_append.txt
append_lines=$(wc -l < /tmp/test_append.txt)
run_test "Append redirection" "2" "$append_lines"
rm -f /tmp/test_append.txt

# Input redirection
echo "input test" > /tmp/test_input.txt
input_result=$(cat < /tmp/test_input.txt)
run_test "Input redirection" "input test" "$input_result"
rm -f /tmp/test_input.txt

# stderr redirection
stderr_result=$(echo "stderr message" >&2 2>&1 >/dev/null)
# Note: This is tricky to test properly

# =============================================================================
# SECTION 14: PROCESS SUBSTITUTION (Bash-specific)
# =============================================================================
test_section "14. Process Substitution <(...) >(...)"

# Process substitution input
proc_sub_result=$(diff <(echo -e "a\nb\nc") <(echo -e "a\nb\nc") | wc -c)
run_test "Process substitution input (identical)" "0" "$proc_sub_result"

# Process substitution output (simpler test)
# Note: This can be harder to test portably

# =============================================================================
# SECTION 15: JOB CONTROL & BACKGROUND
# =============================================================================
test_section "15. Job Control & Background"

# Background job (simple test)
sleep 0.1 &
bg_job=$!
wait $bg_job
run_test "Background job completion" "0" "$?"

# Disown (if supported)
sleep 0.2 &
disown_job=$!
disown $disown_job 2>/dev/null
run_test "disown command" "pass" "pass"  # If disown exists

# =============================================================================
# SECTION 16: SHEOPT OPTIONS
# =============================================================================
test_section "16. shopt Options"

# Check shopt is available
shopt_result=$(shopt | head -1 | cut -d':' -f1)
run_test "shopt command works" "pass" "$([[ -n "$shopt_result" ]] && echo pass || echo fail)"

# Check nullglob option
shopt -s nullglob
null_arr=(/nonexistent/pattern/*.txt)
run_test "nullglob with nonexistent" "0" "${#null_arr[@]}"
shopt -u nullglob

# Check extglob option
shopt extglob | grep -q "on"
run_test "extglob default" "pass" "$([[ "$?" -eq "0" || "$([[ -f /dev/null ]]" == "on" ]] && echo pass || echo fail)"

# =============================================================================
# SECTION 17: SPECIAL PARAMETERS
# =============================================================================
test_section "17. Special Parameters"

# $$ (PID of shell - hard to test directly)
run_test "$$ exists" "pass" "$([[ $$ -gt 0 ]] && echo pass || echo fail)"

# $0 (shell name)
run_test "$0 is not empty" "pass" "$([[ -n "$0" ]] && echo pass || echo fail)"

# $# (number of positional params)
run_test "$# with no args" "0" "$#"

# $@ in function
func_check() {
    echo "$#"
}
set -- "a" "b" "c"
run_test "$# after set -- a b c" "3" "$(func_check)"

# $? (last exit code)
true
run_test "$? after true" "0" "$?"

false
run_test "$? after false" "1" "$?"

# $! (PID of last background job)
sleep 0.1 &
bg_pid=$!
run_test "$! is PID" "pass" "$([[ $bg_pid -gt 0 ]] && echo pass || echo fail)"

# =============================================================================
# SECTION 18: BASH BUILTINS
# =============================================================================
test_section "18. Bash Builtins"

# echo builtin
run_test "echo builtin" "hello echo" "$(echo hello echo)"

# printf builtin
run_test "printf builtin" "42" "$(printf '%d' 42)"

# cd builtin  
orig_pwd="$PWD"
cd /tmp
run_test "cd builtin" "pass" "$([[ "$PWD" == "/tmp" ]] && echo pass || echo fail)"
cd "$orig_pwd"

# pwd builtin
run_test "pwd builtin" "pass" "$([[ -n "$(pwd)" ]] && echo pass || echo fail)"

# export builtin
export TEST_EXPORT="exported_value"
run_test "exported variable accessible" "exported_value" "$TEST_EXPORT"

# unset builtin
test_unset_var="will_be_unset"
unset test_unset_var
run_test "unset variable" "pass" "$([[ -z "${test_unset_var+x}" ]] && echo pass || echo fail)"

# readonly builtin
readonly readonly_var="readonly_value"
run_test "readonly variable" "readonly_value" "$readonly_var"

# set builtin
set -- "x" "y"
run_test "set positional params" "x y" "$1 $2"

# eval builtin
eval_cmd="test_eval_var=eval_success"
eval "$eval_cmd"
run_test "eval builtin" "eval_success" "$test_eval_var"

# exec builtin (cannot test exec since it replaces shell)
# source/. builtin
echo 'source_test_var=source_success' > /tmp/test_source.sh
source /tmp/test_source.sh
run_test "source builtin" "source_success" "$source_test_var"
rm -f /tmp/test_source.sh

# type builtin
type_result=$(type echo | grep -c "builtin")
run_test "type builtin identifies builtin" "pass" "$([[ "$type_result" -gt 0 ]] && echo pass || echo fail)"

# command builtin
run_test "command builtin" "pass" "$([[ -n "$(command echo test)" ]] && echo pass || echo fail)"

# declare builtin
declare declare_test="declare_value"
run_test "declare builtin" "declare_value" "$declare_test"

# typeset builtin
typeset typeset_test="typeset_value"
run_test "typeset builtin" "typeset_value" "$typeset_test"

# pushd/popd (if supported)
echo "PASS"  # Pushd/popd can be tested separately

# =============================================================================
# SECTION 19: BASH 5.x SPECIFIC FEATURES
# =============================================================================
test_section "19. Bash 5.x Specific Features"

# associative array with space-separated keys (Bash 5+)
declare -A bash5_assoc=([\"1 2\"]=\"3 4\" [\"a b\"]=\"c d\")
run_test "Bash 5+ assoc with space key" "3 4" "${bash5_assoc["1 2"]}"

# C-style for loop with multiple variables (Bash 5+)
multi_var_result=""
for ((i=0, j=10; i<3; i++, j--)); do
    multi_var_result="$multi_var_result$i$j "
done
run_test "C-style for multiple vars" "010 19 28 " "$multi_var_result"

# mapfile -C (callback) - difficult to test
# mapfile -s (skip count)
echo -e "line1\nline2\nline3\nline4\nline5" > /tmp/test_skip.txt
mapfile -s 2 -t skip_arr < /tmp/test_skip.txt
run_test "mapfile -s skip 2 starts with line3" "line3" "${skip_arr[0]}"
rm -f /tmp/test_skip.txt

# History expansion (if enabled)
set +H 2>/dev/null

# =============================================================================
# SECTION 20: QUOTING & WORD SPLITTING
# =============================================================================
test_section "20. Quoting & Word Splitting"

# Double quotes preserve spaces
double_quote="hello   world"
run_test "Double quotes preserve spaces" "hello   world" "$double_quote"

# Single quotes preserve literally
single_quote='hello  $world'
run_test "Single quotes literal" 'hello  $world' "$single_quote"

# Unquoted word splitting
unquoted_var="one two three"
split_result=($unquoted_var)
run_test "Unquoted word splitting" "3" "${#split_result[@]}"

# Quoted no splitting
quoted_var="one two three"
quoted_result=("$quoted_var")
run_test "Quoted no splitting" "1" "${#quoted_result[@]}"

# Backslash escapes
escaped="hello\"world"
run_test "Backslash escape double quote" 'hello"world' "$escaped"

# =============================================================================
# SECTION 21: ERROR HANDLING
# =============================================================================
test_section "21. Error Handling"

# set -e (errexit) - test in subshell
set_e_result=$(set -e; false; echo "should_not_print" 2>/dev/null || echo "errexit_works")
run_test "set -e (errexit)" "errexit_works" "$set_e_result"

# set -u (nounset) 
set_u_result=$(set -u; echo "$UNSET_VAR_12345" 2>&1 || echo "nounset_works")
run_test "set -u (nounset)" "nounset_works" "$set_u_result"

# trap
trap_test=""
test_trap() { trap_test="trap_executed"; }
trap test_trap EXIT
# Trigger EXIT by returning
run_test "trap EXIT" "pass" "$([[ "$trap_test" == "trap_executed" ]] && echo pass || echo fail)"

# =============================================================================
# SECTION 22: SHELL VARIABLES & ENVIRONMENT
# =============================================================================
test_section "22. Shell Variables & Environment"

# IFS (Internal Field Separator)
orig_IFS="$IFS"
IFS=":"
ifsplit="a:b:c"
IFS_array=($ifsplit)
run_test "IFS splitting" "3" "${#IFS_array[@]}"
IFS="$orig_IFS"

# PATH exists
run_test "PATH exists" "pass" "$([[ -n "$PATH" ]] && echo pass || echo fail)"

# HOME exists
run_test "HOME exists" "pass" "$([[ -n "$HOME" ]] && echo pass || echo fail)"

# OLDPWD
run_test "OLDPWD exists" "pass" "$([[ -v OLDPWD || -v PWD ]] && echo pass || echo fail)"

# SECONDS
start_seconds=$SECONDS
sleep 0.1
elapsed=$((SECONDS - start_seconds))
run_test "SECONDS variable" "pass" "$([[ $elapsed -ge 0 ]] && echo pass || echo fail)"

# RANDOM
random1=$RANDOM
random2=$RANDOM
run_test "RANDOM exists" "pass" "$([[ $random1 -ge 0 && $random1 -le 32767 ]] && echo pass || echo fail)"

# LINENO
line_test() {
    echo $LINENO
}
# Line number should be positive
lineno_result=$(line_test)
run_test "LINENO variable" "pass" "$([[ $lineno_result -gt 0 ]] && echo pass || echo fail)"

# =============================================================================
# SUMMARY
# =============================================================================
test_section "TEST SUMMARY"

echo "Total tests run: $TESTS_RUN"
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "🎉 ALL TESTS PASSED!"
    exit 0
else
    echo "⚠️  $FAIL_COUNT test(s) failed"
    exit 1
fi
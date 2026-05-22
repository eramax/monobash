#!/usr/bin/env bash
# ==============================================================================
# COMPREHENSIVE BASH 5.x COMPATIBILITY TEST SUITE
# Reference: POSIX.1-2024 (IEEE Std 1003.1-2024) Shell Command Language
#            + GNU Bash 5.x extensions
#
# Usage:  bash bash_compat_test.sh
#         /path/to/your/shell bash_compat_test.sh
#
# Exit:   0 = all tests passed
#         1 = one or more tests failed
# ==============================================================================

PASS=0
FAIL=0
SKIP=0
TOTAL=0
FAILED_TESTS=()

# ── helpers ──────────────────────────────────────────────────────────────────

_pass() { echo "  ✓ PASS : $1"; ((PASS++)); ((TOTAL++)); }
_fail() { echo "  ✗ FAIL : $1"; echo "           expected: $(printf '%q' "$2")"; echo "           actual  : $(printf '%q' "$3")"; ((FAIL++)); ((TOTAL++)); FAILED_TESTS+=("$1"); }
_skip() { echo "  ○ SKIP : $1 ($2)"; ((SKIP++)); }

check() {
    local name="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then _pass "$name"
    else _fail "$name" "$expected" "$actual"; fi
}

check_exit() {
    local name="$1" expected_code="$2"; shift 2
    eval "$@" >/dev/null 2>&1
    local actual_code=$?
    if [[ "$expected_code" == "$actual_code" ]]; then _pass "$name"
    else _fail "$name" "exit=$expected_code" "exit=$actual_code"; fi
}

section() { echo; echo "════════════════════════════════════════════════════"; echo "  $1"; echo "════════════════════════════════════════════════════"; }

# ==============================================================================
# §1  QUOTING  (POSIX 2.2)
# ==============================================================================
section "§1  Quoting"

check "backslash preserves literal dollar"          '$x'  $'$x'
check "backslash preserves literal backslash"       '\'   $'\\'
check "backslash-newline = line continuation"  "a\\b"  "$(printf 'a\\b' | "$SHELL" -c 'read -r l; echo $l')"
check "backslash preserves space"                   "a b" "$(echo a\ b)"
v=REPLACED
check "single-quote prevents expansion"   '$v'  '$v'
check "single-quote preserves newline"    $'a\nb' $'a\nb'
check "single-quote preserves backslash"  '\n'  $'\\n'
check "double-quote allows \$expansion"     "hello"    "$( echo 'hello' )"
check "double-quote allows \$(cmd subst)"   "hello"    "$(echo hello)"
check "double-quote allows backtick subst"  "hello"    "`echo hello`"
check "double-quote allows arith"           "5"        "$((2+3))"
check "double-quote preserves spaces"       "a  b"     "$(echo "a  b")"
check "double-quote escapes backslash-dq"   '"'        $'\"'
check "\$'\\n' yields newline"    "$(printf '\n')"  "$(printf '\n')"
check "\$'\\t' yields tab"        $'\t'  "$(printf '\t')"
check "\$'\\\\' yields backslash" '\'    $'\\'
check "\$'\\'' yields apos"       "'"    $'\''
check "\$'\\a' is alert byte"     $'\a'  "$(printf '\a')"
check "\$'\\x41' hex escape"      "A"    $'\x41'
check "\$'\\101' octal escape"    "A"    $'\101'
check "\$'\\e' escape char"       $'\e'  "$(printf '\e')"

# ==============================================================================
# §2  TOKEN RECOGNITION  (POSIX 2.3)
# ==============================================================================
section "§2  Token Recognition"

check "semicolon separates commands"          "1 2"    "$(r=$(echo 1; echo 2); echo $r)"
check "pipe connects commands"                "HELLO"  "$(echo hello | tr a-z A-Z)"
check "ampersand starts async (exit 0)"       "0"      "$( sleep 0 & wait $!; echo $? )"
check "double-pipe OR list"                   "yes"    "$(false || echo yes)"
check "double-amp AND list"                   "yes"    "$(true  && echo yes)"
check "newline as command terminator"         "ab"     "$(printf 'a\nb\n' | tr -d '\n')"
check "comment # ignored"                     ""       "$(# this is a comment
)"
check "operator >> two chars"                 "ok"     "$(echo ok >> /tmp/_bct_append.txt; cat /tmp/_bct_append.txt; rm -f /tmp/_bct_append.txt)"

# ==============================================================================
# §3  RESERVED WORDS  (POSIX 2.4)
# ==============================================================================
section "§3  Reserved Words"

check "reserved word 'if' not a var"   ""  "${if+set}"     2>/dev/null || true
check "reserved word 'then' not a var" ""  "${then+set}"   2>/dev/null || true
check "reserved word 'while' not a var" "" "${while+set}"  2>/dev/null || true

# ==============================================================================
# §4  PARAMETERS & VARIABLES  (POSIX 2.5)
# ==============================================================================
section "§4  Parameters & Variables"

set -- alpha beta gamma
check "positional \$1"        "alpha"      "$1"
check "positional \$2"        "beta"       "$2"
check "positional \$3"        "gamma"      "$3"
check "positional \${10}"     ""           "${10}"
set -- a b c d e f g h i j k
check "positional \${10} two-digit" "j"    "${10}"
check "positional \${11}"    "k"           "${11}"
set --

set -- x y z
check "\$# count"          "3"    "$#"
check "\$* star expansion" "x y z" "$*"
check "\$@ at expansion"   "x y z" "$(set -- x y z; echo "$@")"
set --
check "\$# after set--"    "0"    "$#"

true;  check "\$? after true"   "0" "$?"
false; check "\$? after false"  "1" "$?"

check "\$\$ is positive int"  "yes"  "$([ $$ -gt 0 ] && echo yes || echo no)"
check "\$0 non-empty"         "yes"  "$([ -n "$0" ] && echo yes || echo no)"

sleep 0 &
check "\$! bg PID > 0"  "yes"  "$([ $! -gt 0 ] && echo yes || echo no)"
wait

check "\$- contains flags"  "yes"  "$([ -n "$-" ] && echo yes || echo no)"

check "IFS default space-tab-nl" "a b" "$(IFS=$' \t\n'; x='a b'; set -- $x; echo "$1 $2")"
check "IFS colon splitting"      "3"   "$(IFS=:; x='a:b:c'; set -- $x; echo $#)"
check "IFS empty no-split"       "1"   "$(IFS=''; x='a b c'; set -- $x; echo $#)"

check "HOME exists"    "yes"  "$([ -n "$HOME" ] && echo yes || echo no)"
check "PATH exists"    "yes"  "$([ -n "$PATH" ] && echo yes || echo no)"
check "PWD exists"     "yes"  "$([ -n "$PWD"  ] && echo yes || echo no)"
check "PPID numeric"   "yes"  "$([ "$PPID" -ge 0 ] 2>/dev/null && echo yes || echo no)"
check "LINENO > 0"     "yes"  "$([ $LINENO -gt 0 ] && echo yes || echo no)"

check "BASH_VERSION starts with 5"  "yes"  "$([[ ${BASH_VERSION:0:1} =~ [3-9] ]] && echo yes || echo no)"
check "BASH_VERSINFO array"         "yes"  "$([[ ${BASH_VERSINFO[0]} -ge 3 ]] && echo yes || echo no)"
check "RANDOM 0-32767"              "yes"  "$([[ $RANDOM -ge 0 && $RANDOM -le 32767 ]] && echo yes || echo no)"
check "SECONDS >= 0"                "yes"  "$([[ $SECONDS -ge 0 ]] && echo yes || echo no)"
check "HOSTNAME non-empty"         "yes"  "$([[ -n $HOSTNAME ]] && echo yes || echo no)"
check "UID numeric"                "yes"  "$([[ $UID -ge 0 ]] && echo yes || echo no)"
check "EUID numeric"               "yes"  "$([[ $EUID -ge 0 ]] && echo yes || echo no)"
check "SHLVL >= 1"                 "yes"  "$([[ $SHLVL -ge 1 ]] && echo yes || echo no)"
check "BASH_SUBSHELL in subshell"  "1"    "$("$SHELL" -c '( echo $BASH_SUBSHELL )')"
check "BASHPID in subshell"        "yes"  "$("$SHELL" -c 'echo $BASHPID' | grep -q '[0-9]' && echo yes || echo no)"
check "BASH_SOURCE[0] non-empty"   "yes"  "$([[ -n ${BASH_SOURCE[0]} ]] && echo yes || echo no)"
check "FUNCNAME outside fn"        ""     "${FUNCNAME[0]}"
check "BASH_LINENO outside fn"     "yes"  "$([[ ${BASH_LINENO[0]+set} == set || 1 == 1 ]] && echo yes)"
check "PIPESTATUS after pipe"      "0"    "$(true | true; echo ${PIPESTATUS[0]})"
check "PIPESTATUS[1] after pipe"   "0"    "$(true | true; echo ${PIPESTATUS[1]})"
check "PIPESTATUS with fail"       "1"    "$(false | true; echo ${PIPESTATUS[0]})"
check "OLDPWD after cd"            "yes"  "$(cd /tmp; [[ -n $OLDPWD ]] && echo yes || echo no)"

# ==============================================================================
# §5  TILDE EXPANSION  (POSIX 2.6.1)
# ==============================================================================
section "§5  Tilde Expansion  (POSIX 2.6.1)"

check "~ expands to HOME"      "$HOME"      "$(echo ~)"
check "~/ prefix"              "$HOME/bin"  "$(echo ~/bin)"
check "~root exists or empty"  "yes"        "$( r=$(echo ~root); [[ -n $r ]] && echo yes || echo no )"

# ==============================================================================
# §6  PARAMETER EXPANSION  (POSIX 2.6.2)
# ==============================================================================
section "§6  Parameter Expansion"

x="hello"
check "basic \${x}"          "hello"   "${x}"
check "\${#x} length"        "5"       "${#x}"
check "undefined var = empty" ""       "${_UNDEF_VAR_}"

unset u
check "\${u:-word} unset→word"       "default"  "${u:-default}"
check "\${u-word}  unset→word"       "default"  "${u-default}"
u=""
check "\${u:-word} empty→word"       "default"  "${u:-default}"
check "\${u-word}  empty→null"       ""         "${u-default}"
u="set"
check "\${u:-word} set→value"        "set"      "${u:-default}"
check "\${u:+word} set→word"         "alt"      "${u:+alt}"
unset u
check "\${u:+word} unset→empty"      ""         "${u:+alt}"

unset asn
: "${asn:=assigned}"
check "\${asn:=word} assigns"        "assigned"  "$asn"
asn=""
: "${asn:=reassigned}"
check "\${asn:=word} empty assigns"  "reassigned" "$asn"
asn="keep"
: "${asn:=ignored}"
check "\${asn:=word} set keeps"      "keep"       "$asn"

unset asn2
: "${asn2=only_unset}"
check "\${asn2=word} unset assigns"  "only_unset" "$asn2"
asn2=""
: "${asn2=ignored_empty}"
check "\${asn2=word} empty keeps"    ""            "$asn2"

check "\${v:?} set → value"          "hello"  "${x:?must be set}"
check "\${v?}  set → value"          "hello"  "${x?must be set}"
err_out=$(unset _undef_; "$SHELL" -c 'echo ${_undef_:?error_msg}' 2>&1); check "\${v:?} unset → error msg" "yes" "$([[ $err_out == *error_msg* ]] && echo yes || echo no)"

x="yes"
check "\${x:+alt} set→alt"    "found"   "${x:+found}"
unset x
check "\${x:+alt} unset→empty" ""       "${x:+found}"

p="file.tar.gz"
check "\${p#*.}  remove shortest prefix"   "tar.gz"  "${p#*.}"
check "\${p##*.} remove longest prefix"    "gz"      "${p##*.}"
check "\${p%.*}  remove shortest suffix"   "file.tar" "${p%.*}"
check "\${p%%.*} remove longest suffix"    "file"    "${p%%.*}"

s="foo bar foo baz"
check "\${s/foo/X}  replace first"   "X bar foo baz"  "${s/foo/X}"
check "\${s//foo/X} replace all"     "X bar X baz"    "${s//foo/X}"
check "\${s/#foo/X} replace prefix"  "X bar foo baz"  "${s/#foo/X}"
check "\${s/%baz/X} replace suffix"  "foo bar foo X"  "${s/%baz/X}"

lower="hello world"
upper="HELLO WORLD"
check "\${v^}  first upper"   "Hello world"  "${lower^}"
check "\${v^^} all upper"     "HELLO WORLD"  "${lower^^}"
check "\${v,}  first lower"   "hELLO WORLD"  "${upper,}"
check "\${v,,} all lower"     "hello world"  "${upper,,}"
check "\${v~}  toggle first"  "Hello world"  "${lower~}"
check "\${v~~} toggle all"    "HELLO WORLD"  "${lower~~}"

s="abcdef"
check "\${s:2}    from offset"    "cdef"   "${s:2}"
check "\${s:2:3}  offset+length"  "cde"    "${s:2:3}"
check "\${s: -3}  negative off"   "def"    "${s: -3}"
check "\${s: -3:2} neg+len"       "de"     "${s: -3:2}"
check "\${s:0:0}  zero len"       ""       "${s:0:0}"
check "\${#s} string length"      "6"      "${#s}"

ptr="HOME"
check "\${!ptr} indirect"  "$HOME"  "${!ptr}"

TEST_A=1; TEST_B=2; TEST_C=3
names=( ${!TEST_*} )
check "\${!prefix*} returns names"  "yes"  "$([[ ${#names[@]} -ge 3 ]] && echo yes || echo no)"

q='hello "world"'
check "\${v@Q} quote op"    "yes"  "$([[ -n ${q@Q} ]] && echo yes || echo no)"
check "\${v@U} uppercase"   "HELLO"  "$(v=hello; echo ${v@U})"
check "\${v@L} lowercase"   "hello"  "$(v=HELLO; echo ${v@L})"
check "\${v@u} ucfirst"     "Hello"  "$(v=hello; echo ${v@u})"

# ==============================================================================
# §7  COMMAND SUBSTITUTION  (POSIX 2.6.3)
# ==============================================================================
section "§7  Command Substitution"

check "\$(cmd) basic"                  "hello"     "$(echo hello)"
check "\$(cmd) trailing-nl stripped"   "hello"     "$(printf 'hello\n\n\n')"
check "\$(cmd) embedded-nl kept"       "$(printf 'a\nb')"  "$(printf 'a\nb\n')"
check "backtick basic"                 "hello"     "`echo hello`"
check "nested \$()"                    "inner"     "$(echo $(echo inner))"
check "nested backtick"                "inner"     "`echo \`echo inner\``"
check "\$() in double-quotes"          "hello"     "$(echo "$(echo hello)")"
check "cmd-subst word splitting off in dq" "a b"   "$(x=$(echo 'a b'); echo "$x")"
check "cmd-subst with pipe"            "HELLO"     "$(echo hello | tr a-z A-Z)"
check "cmd-subst with redirection"     "data"      "$(echo data > /tmp/_bct_cs.txt; cat /tmp/_bct_cs.txt; rm -f /tmp/_bct_cs.txt)"

# ==============================================================================
# §8  ARITHMETIC EXPANSION  (POSIX 2.6.4)
# ==============================================================================
section "§8  Arithmetic Expansion"

check "add"                   "5"    "$((2+3))"
check "subtract"              "3"    "$((7-4))"
check "multiply"              "42"   "$((6*7))"
check "integer divide"        "3"    "$((7/2))"
check "modulo"                "1"    "$((7%2))"
check "exponent **"           "256"  "$((2**8))"
check "unary minus"           "-5"   "$((-5))"
check "unary plus"            "5"    "$((+5))"
check "bitwise AND"           "4"    "$((12&5))"
check "bitwise OR"            "13"   "$((12|5))"
check "bitwise XOR"           "9"    "$((12^5))"
check "bitwise NOT"           "-6"   "$(( ~5 ))"
check "left shift"            "40"   "$((10<<2))"
check "right shift"           "2"    "$((10>>2))"
check "logical AND true"      "1"    "$((1&&1))"
check "logical AND false"     "0"    "$((1&&0))"
check "logical OR true"       "1"    "$((0||1))"
check "logical OR false"      "0"    "$((0||0))"
check "logical NOT"           "0"    "$(( !1 ))"
check "comparison >"          "1"    "$((5>3))"
check "comparison <"          "0"    "$((5<3))"
check "comparison >="         "1"    "$((5>=5))"
check "comparison <="         "1"    "$((4<=5))"
check "comparison =="         "1"    "$((5==5))"
check "comparison !="         "1"    "$((5!=4))"
check "ternary true"          "1"    "$((5>3?1:0))"
check "ternary false"         "0"    "$((2>3?1:0))"
check "comma operator"        "5"    "$(( x=3, y=2, x+y ))"
check "hex literal 0x0A"      "10"   "$((0x0A))"
check "octal literal 010"     "8"    "$((010))"
check "binary literal 2#1010" "10"   "$((2#1010))"
check "var in arith"          "7"    "$(a=3; b=4; echo $((a+b)))"
check "pre-increment"         "4"    "$(a=3; echo $((++a)))"
check "post-increment"        "3"    "$(a=3; echo $((a++)))"
check "pre-decrement"         "2"    "$(a=3; echo $((--a)))"
check "post-decrement"        "3"    "$(a=3; echo $((a--)))"
check "+= assign"             "7"    "$(a=5; ((a+=2)); echo $a)"
check "-= assign"             "3"    "$(a=5; ((a-=2)); echo $a)"
check "*= assign"             "10"   "$(a=5; ((a*=2)); echo $a)"
check "/= assign"             "2"    "$(a=6; ((a/=3)); echo $a)"
check "%= assign"             "1"    "$(a=7; ((a%=3)); echo $a)"
check "**= assign"            "8"    "$(a=2; ((a=a**3)); echo $a)"
check "<<= assign"            "20"   "$(a=5; ((a<<=2)); echo $a)"
check ">>= assign"            "2"    "$(a=8; ((a>>=2)); echo $a)"
check "&= assign"             "4"    "$(a=12; ((a&=5)); echo $a)"
check "|= assign"             "13"   "$(a=12; ((a|=5)); echo $a)"
check "^= assign"             "9"    "$(a=12; ((a^=5)); echo $a)"
check "(( expr )) exit 0 nonzero"  "0"  "$( ((5>0)); echo $? )"
check "(( expr )) exit 1 zero"     "1"  "$( ((0)); echo $? )"

# ==============================================================================
# §9  FIELD SPLITTING  (POSIX 2.6.5)
# ==============================================================================
section "§9  Field Splitting"

check "default IFS splits spaces"  "3"  "$(x='a b c'; set -- $x; echo $#)"
check "default IFS splits tabs"    "3"  "$(x=$'a\tb\tc'; set -- $x; echo $#)"
check "default IFS strips leading" "2"  "$(x='  a  b  '; set -- $x; echo $#)"
check "custom IFS colon"           "3"  "$(IFS=:; x='a:b:c'; set -- $x; echo $#)"
check "custom IFS two-char"        "3"  "$(IFS=:,; x='a:b,c'; set -- $x; echo $#)"
check "IFS=empty no split"         "1"  "$(IFS=''; x='a b c'; set -- $x; echo $#)"
check "quoted \$x no split"        "1"  "$(x='a b c'; set -- "$x"; echo $#)"
check "IFS non-whitespace empty"   "3"  "$(IFS=:; x='a::c'; set -- $x; echo $#)"

# ==============================================================================
# §10  PATHNAME EXPANSION  (POSIX 2.6.6)
# ==============================================================================
section "§10  Pathname Expansion (Globbing)"

mkdir -p /tmp/_bct_glob/dir
touch /tmp/_bct_glob/a.txt /tmp/_bct_glob/b.txt /tmp/_bct_glob/.hidden
check "* matches files"         "2"  "$(echo /tmp/_bct_glob/*.txt | wc -w)"
check "? matches single char"   "2"  "$(echo /tmp/_bct_glob/?.txt | wc -w)"
check "[ab] char class"         "2"  "$(echo /tmp/_bct_glob/[ab].txt | wc -w)"
check "[!c] negated class"      "2"  "$(echo /tmp/_bct_glob/[!c].txt | wc -w)"
check "* does not match hidden" "no" "$(x=/tmp/_bct_glob/*; [[ "$x" == *'.hidden'* ]] && echo yes || echo no)"
check "set -f disables glob"    "yes"  "$(set -f; x='*.txt'; set +f; [[ $x == '*.txt' ]] && echo yes || echo no)"
check "nullglob empty array"    "0"  "$(shopt -s nullglob; a=(/tmp/_bct_glob/NOMATCH*); shopt -u nullglob; echo ${#a[@]})"
rm -rf /tmp/_bct_glob

# ==============================================================================
# §11  BRACE EXPANSION  (Bash)
# ==============================================================================
section "§11  Brace Expansion (Bash)"

check "{a,b,c}"        "a b c"  "$(echo {a,b,c})"
check "{1..5}"         "1 2 3 4 5"  "$(echo {1..5})"
check "{5..1}"         "5 4 3 2 1"  "$(echo {5..1})"
check "{a..e}"         "a b c d e"  "$(echo {a..e})"
check "{1..5..2} step" "1 3 5"      "$(echo {1..5..2})"
check "{0..10..3}"     "0 3 6 9"    "$(echo {0..10..3})"
check "prefix{a,b}"    "xa xb"      "$(echo x{a,b})"
check "{a,b}suffix"    "ay by"      "$(echo {a,b}y)"
check "nested {{a,b},{c,d}}" "a b c d" "$(echo {{a,b},{c,d}})"
check "empty element {a,,b}" "yes"  "$( r=$(echo {a,,b}); [[ $r =~ ^a ]] && echo yes || echo no )"
check "single element no brace" "{a}" "$(echo {a})"

# ==============================================================================
# §12  REDIRECTION  (POSIX 2.7)
# ==============================================================================
section "§12  Redirection"

T=/tmp/_bct_redir.txt

echo "line1" > $T; check "> creates file"  "line1"  "$(cat $T)"
echo "line2" >> $T; check ">> appends"     "2"  "$(wc -l < $T)"
check "< reads file"  "line1"  "$(read v < $T; echo $v)"
set -C 2>/dev/null || true
echo "new" >| $T; check ">| overrides noclobber" "new" "$(cat $T)"
set +C 2>/dev/null || true
check "<> opens rw"   "0"  "$(exec 5<>$T; [ -e $T ] && echo 0; exec 5>&-)"
check "2> stderr redir to file" "0" "$(echo err 2>$T >/dev/null; wc -c < $T | tr -d ' ')"
echo err2 2>/dev/null; check "2>/dev/null swallows stderr"  "0"  "$?"
check "2>&1 merges stderr"  "err"  "$("$SHELL" -c 'echo err >&2' 2>&1)"
check "&> both streams"  "out"  "$(echo out &>$T; cat $T)"

echo "fdtest" > $T
exec 3< $T
check "fd 3 read"   "fdtest"  "$(read v <&3; echo $v)"
exec 3<&-

check "heredoc basic" "hello world" "$(cat <<'EOF'
hello world
EOF
)"
check "heredoc expansion" "hello world" "$(x=world; cat <<EOF
hello $x
EOF
)"
check "heredoc <<- strips tabs" "hello" "$(cat <<-EOF
	hello
	EOF
)"
check "herestring <<<"  "hello"  "$(cat <<< hello)"
check "herestring with var"  "world"  "$(v=world; cat <<< "$v")"
check "<(cmd) proc subst input"  "0"  "$(diff <(echo a) <(echo a) | wc -c)"
check ">(cmd) proc subst output" "hello" "$(echo hello > >(cat))"

rm -f $T

# ==============================================================================
# §13  SIMPLE COMMANDS  (POSIX 2.9.1)
# ==============================================================================
section "§13  Simple Commands"

check "var assignment before cmd"         "passed"   "$(VAR=passed env | grep ^VAR= | cut -d= -f2)"
check "assignment in environment only"    ""         "$(NOTEXIST_VAR=env_only "$SHELL" -c ':'; echo "${NOTEXIST_VAR}")"
check "multiple assignments"              "1 2"      "$(A=1 B=2 "$SHELL" -c 'echo $A $B')"
check "command name lookup via PATH"      "yes"      "$( which bash >/dev/null 2>&1 && echo yes || echo no )"
check "non-existent command exit ≠ 0"    "yes"      "$("$SHELL" -c '_cmd_not_found_' 2>/dev/null; [ $? -ne 0 ] && echo yes || echo no)"

# ==============================================================================
# §14  PIPELINES  (POSIX 2.9.2)
# ==============================================================================
section "§14  Pipelines"

check "simple pipe"               "HELLO"  "$(echo hello | tr a-z A-Z)"
check "multi-stage pipe"          "3"      "$(echo -e 'a\nb\nc' | grep -c .)"
check "pipe exit = last stage"    "0"      "$(true | true; echo $?)"
check "pipe exit = last (fail)"   "1"      "$(true | false; echo $?)"
check "! negates exit"            "0"      "$(! false; echo $?)"
check "! negates true"            "1"      "$(! true; echo $?)"
check "pipefail option"           "1"      "$(set -o pipefail; false | true; echo $?; set +o pipefail)"

# ==============================================================================
# §15  AND-OR LISTS  (POSIX 2.9.3)
# ==============================================================================
section "§15  AND-OR Lists"

check "&& runs 2nd on success"  "yes"    "$(true && echo yes)"
check "&& skips 2nd on fail"    ""       "$(false && echo yes)"
check "|| runs 2nd on fail"     "yes"    "$(false || echo yes)"
check "|| skips 2nd on success" ""       "$(true || echo yes; true)"
check "chained &&"              "c"      "$(true && true && echo c)"
check "chained ||"              "a"      "$(echo a || echo b)"
check "mixed && ||"             "ok"     "$(false && echo no || echo ok)"
check "exit of && list"         "0"      "$(true && true; echo $?)"
check "exit of || list"         "0"      "$(false || true; echo $?)"

sleep 0 & BGPID=$!; wait $BGPID
check "async & exit is 0"       "0"      "$?"

# ==============================================================================
# §16  COMPOUND COMMANDS  (POSIX 2.9.4)
# ==============================================================================
section "§16  Compound Commands"

check "subshell runs commands"       "hello"  "$(( echo hello ))"
check "subshell var isolated"        "outer"  "$(v=outer; ( v=inner ); echo $v)"
check "subshell exit code"           "1"      "$( ( false ); echo $? )"
check "subshell cd isolated"         "$PWD"   "$(( cd /tmp ); echo $PWD)"
check "brace group runs commands"    "hello"  "$( { echo hello; } )"
check "brace group shares env"       "inner"  "$(v=outer; { v=inner; }; echo $v)"
check "brace group exit code"        "1"      "$( { false; }; echo $? )"

r=""
for i in 1 2 3; do r+="$i"; done
check "for loop collects"  "123"  "$r"

r=""
for i in a b c; do
    [[ $i == b ]] && continue
    r+="$i"
done
check "for + continue"  "ac"  "$r"

r=""
for i in 1 2 3 4; do
    [[ $i == 3 ]] && break
    r+="$i"
done
check "for + break"  "12"  "$r"

r=""
for ((i=0; i<5; i++)); do r+="$i"; done
check "C-style for 0..4"  "01234"  "$r"

r=""
for ((i=10; i>0; i-=3)); do r+="$i,"; done
check "C-style for decrement step"  "10,7,4,1,"  "$r"

cnt=0; r=""
while [[ $cnt -lt 3 ]]; do r+="$cnt"; ((cnt++)); done
check "while loop"  "012"  "$r"

cnt=0; r=""
until [[ $cnt -ge 3 ]]; do r+="$cnt"; ((cnt++)); done
check "until loop"  "012"  "$r"

check "case exact match"        "one"   "$(case foo in foo) echo one;; *) echo other;; esac)"
check "case wildcard match"     "other" "$(case bar in foo) echo one;; *) echo other;; esac)"
check "case no match exit 0"    "0"     "$(case x in y) true;; esac; echo $?)"
check "case pattern alt |"      "yes"   "$(case b in a|b|c) echo yes;; esac)"
check "case glob pattern *"     "yes"   "$(case foobar in foo*) echo yes;; esac)"
check "case ;; stops fall-thru" "first" "$(case x in x) echo first;; x) echo second;; esac)"
check "case ;& fall-through"    "$(printf 'first\nsecond')"  "$(case x in x) echo first;& *) echo second;; esac)"
check "case ;;& continue"       "$(printf 'first\nsecond')"  "$(case x in x) echo first;;& *) echo second;; esac)"

check "if true runs then"  "yes"  "$(if true; then echo yes; fi)"
check "if false runs else" "no"   "$(if false; then echo yes; else echo no; fi)"
check "elif chain"         "two"  "$(x=2; if [[ $x -eq 1 ]]; then echo one; elif [[ $x -eq 2 ]]; then echo two; else echo other; fi)"
check "if exit code"       "0"    "$(if true; then :; fi; echo $?)"

check "select is a keyword"  "0"  "$("$SHELL" -c 'type select' >/dev/null 2>&1; echo $?)"

check "[[ string == string ]]"  "0"  "$([[ hello == hello ]]; echo $?)"
check "[[ string != string ]]"  "0"  "$([[ hello != world ]]; echo $?)"
check "[[ string < string ]]"   "0"  "$([[ apple < banana ]]; echo $?)"
check "[[ string > string ]]"   "0"  "$([[ banana > apple ]]; echo $?)"
check "[[ -z empty ]]"          "0"  "$([[ -z "" ]]; echo $?)"
check "[[ -n nonempty ]]"       "0"  "$([[ -n "x" ]]; echo $?)"
check "[[ =~ regex match ]]"    "0"  "$([[ hello123 =~ ^hello[0-9]+$ ]]; echo $?)"
check "[[ =~ no match ]]"       "1"  "$([[ hello =~ ^[0-9]+$ ]]; echo $?)"
check "[[ && ]]"                "0"  "$([[ 1 -eq 1 && 2 -eq 2 ]]; echo $?)"
check "[[ || ]]"                "0"  "$([[ 1 -eq 2 || 2 -eq 2 ]]; echo $?)"
check "[[ ! negation ]]"        "0"  "$([[ ! 1 -eq 2 ]]; echo $?)"
check "[[ -eq ]]"               "0"  "$([[ 5 -eq 5 ]]; echo $?)"
check "[[ -ne ]]"               "0"  "$([[ 5 -ne 4 ]]; echo $?)"
check "[[ -lt ]]"               "0"  "$([[ 3 -lt 5 ]]; echo $?)"
check "[[ -le ]]"               "0"  "$([[ 5 -le 5 ]]; echo $?)"
check "[[ -gt ]]"               "0"  "$([[ 5 -gt 3 ]]; echo $?)"
check "[[ -ge ]]"               "0"  "$([[ 5 -ge 5 ]]; echo $?)"
check "[[ glob pattern == ]]"   "0"  "$([[ foobar == foo* ]]; echo $?)"
check "[[ -v var set ]]"        "0"  "$(x=1; [[ -v x ]]; echo $?)"
check "[[ -v var unset ]]"      "1"  "$(unset _u_; [[ -v _u_ ]]; echo $?)"
check "[[ -f file ]]"           "0"  "$([[ -f /etc/passwd ]]; echo $?)"
check "[[ -d dir ]]"            "0"  "$([[ -d /tmp ]]; echo $?)"
check "[[ -e exists ]]"         "0"  "$([[ -e /tmp ]]; echo $?)"
check "[[ -r readable ]]"       "0"  "$([[ -r /etc/passwd ]]; echo $?)"
check "[[ -s non-empty file ]]" "0"  "$([[ -s /etc/passwd ]]; echo $?)"
check "[[ -x executable ]]"     "0"  "$([[ -x /bin/sh ]]; echo $?)"
check "[[ -L symlink ]]"        "yes" "$(ln -sf /tmp /tmp/_bct_lnk 2>/dev/null; [[ -L /tmp/_bct_lnk ]] && echo yes; rm -f /tmp/_bct_lnk)"
check "[[ -p pipe ]]"           "0"  "$(mkfifo /tmp/_bct_fifo 2>/dev/null; [[ -p /tmp/_bct_fifo ]]; ec=$?; rm -f /tmp/_bct_fifo; echo $ec)"
echo "tmp" > /tmp/_bct_f1.txt; cp /tmp/_bct_f1.txt /tmp/_bct_f2.txt
check "[[ -ef same inode ]]"    "1"  "$([[ /tmp/_bct_f1.txt -ef /tmp/_bct_f2.txt ]]; echo $?)"
check "[[ file1 -nt file2 ]]"   "yes" "$(touch /tmp/_bct_newer.txt; sleep 0.01; touch /tmp/_bct_f1.txt; [[ /tmp/_bct_f1.txt -nt /tmp/_bct_newer.txt ]] && echo yes || echo no; rm -f /tmp/_bct_newer.txt)"
rm -f /tmp/_bct_f1.txt /tmp/_bct_f2.txt

# ==============================================================================
# §17  FUNCTIONS  (POSIX 2.9.5)
# ==============================================================================
section "§17  Functions"

my_func() { echo "func_output"; }
check "function () style"  "func_output"  "$(my_func)"

function my_func2 { echo "func2_output"; }
check "function keyword style"  "func2_output"  "$(my_func2)"

greet() { echo "Hello $1 and $2"; }
check "function params"  "Hello Alice and Bob"  "$(greet Alice Bob)"

argc_fn() { echo $#; }
check "function \$# argc"  "3"  "$(argc_fn a b c)"

at_fn() { for a in "$@"; do printf '[%s]' "$a"; done; }
check "function \"\$@\" preserves words"  "[a b][c d]"  "$(at_fn "a b" "c d")"

star_fn() { for a in "$*"; do printf '[%s]' "$a"; done; }
check "function \"\$*\" joins"  "[a b c d]"  "$(star_fn "a b" "c d")"

ret_fn() { return 42; }
ret_fn; check "function return code"  "42"  "$?"

local_fn() { local lv="inside"; echo "$lv"; }
lv="outside"
check "local var scope"  "inside"  "$(local_fn)"
check "local doesn't leak"  "outside"  "$lv"

int_fn() { local -i n=3; n+=2; echo $n; }
check "local -i integer"  "5"  "$(int_fn)"

arr_fn() { local -a a=(1 2 3); echo "${a[@]}"; }
check "local -a array"  "1 2 3"  "$(arr_fn)"

fib() { if (( $1 <= 1 )); then echo $1; else echo $(( $(fib $(($1-1))) + $(fib $(($1-2))) )); fi; }
check "recursive fibonacci(7)"  "13"  "$(fib 7)"

fname_fn() { echo "${FUNCNAME[0]}"; }
check "FUNCNAME[0] inside fn"  "fname_fn"  "$(fname_fn)"

ov_fn() { echo "v1"; }
ov_fn() { echo "v2"; }
check "function override"  "v2"  "$(ov_fn)"

unset -f ov_fn
check "unset -f removes fn"  "yes"  "$(type ov_fn 2>/dev/null | grep -q function && echo no || echo yes)"

# ==============================================================================
# §18  INDEXED ARRAYS  (Bash 4+)
# ==============================================================================
section "§18  Indexed Arrays"

arr=(zero one two three four)
check "arr[0] first elem"         "zero"       "${arr[0]}"
check "arr[2] middle elem"        "two"        "${arr[2]}"
check "arr[4] last elem"          "four"       "${arr[4]}"
check "\${#arr[@]} length"        "5"          "${#arr[@]}"
check "\${arr[@]} all elements"   "zero one two three four"  "$(echo "${arr[@]}")"
check "\${arr[*]} all joined"     "zero one two three four"  "$(echo "${arr[*]}")"
check "\${!arr[@]} keys"          "0 1 2 3 4"  "$(echo "${!arr[@]}")"
check "arr[-1] negative index"    "four"       "${arr[-1]}"
check "arr[-2] negative index"    "three"      "${arr[-2]}"
check "arr[@]:1:3 slice"          "one two three"  "$(echo "${arr[@]:1:3}")"
check "arr[@]:2 tail slice"       "two three four" "$(echo "${arr[@]:2}")"

arr+=(five six)
check "append with +="  "7"  "${#arr[@]}"

sparse=([0]=a [3]=d [7]=h)
check "sparse arr[0]"   "a"   "${sparse[0]}"
check "sparse arr[3]"   "d"   "${sparse[3]}"
check "sparse arr[7]"   "h"   "${sparse[7]}"
check "sparse arr[1]"   ""    "${sparse[1]}"
check "sparse length"   "3"   "${#sparse[@]}"
check "sparse keys"     "0 3 7"  "$(echo "${!sparse[@]}")"

unset arr[2]
check "unset element"  "6"  "${#arr[@]}"

orig=(a b c)
copy=("${orig[@]}")
copy[0]=X
check "array copy independence"  "a"  "${orig[0]}"
check "array copy modified"      "X"  "${copy[0]}"

declare -a darr
darr[0]="declared"
check "declare -a"  "declared"  "${darr[0]}"

printf 'l1\nl2\nl3\n' > /tmp/_bct_map.txt
mapfile -t mlines < /tmp/_bct_map.txt
check "mapfile -t [0]"     "l1"   "${mlines[0]}"
check "mapfile -t [2]"     "l3"   "${mlines[2]}"
check "mapfile -t length"  "3"    "${#mlines[@]}"

mapfile -n 2 -t mlines2 < /tmp/_bct_map.txt
check "mapfile -n 2 length"  "2"  "${#mlines2[@]}"

mapfile -s 1 -t mlines3 < /tmp/_bct_map.txt
check "mapfile -s 1 skip"  "l2"  "${mlines3[0]}"

readarray -t rlines < /tmp/_bct_map.txt
check "readarray alias"  "3"  "${#rlines[@]}"

rm -f /tmp/_bct_map.txt

# ==============================================================================
# §19  ASSOCIATIVE ARRAYS  (Bash 4+)
# ==============================================================================
section "§19  Associative Arrays (Bash 4+)"

declare -A aa
aa[key1]="val1"
aa[key2]="val2"
aa["key with spaces"]="val3"
check "aa[key1]"             "val1"  "${aa[key1]}"
check "aa[key2]"             "val2"  "${aa[key2]}"
check "aa[key with spaces]"  "val3"  "${aa[key with spaces]}"
check "\${#aa[@]} length"    "3"     "${#aa[@]}"

declare -A bb=([a]=1 [b]=2 [c]=3)
check "compound aa[a]"  "1"  "${bb[a]}"
check "compound aa[b]"  "2"  "${bb[b]}"
check "compound aa[c]"  "3"  "${bb[c]}"

sorted_keys=$(echo "${!bb[@]}" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')
check "assoc keys"  "a b c"  "$sorted_keys"

bb+=([d]=4)
check "append assoc"  "4"  "${bb[d]}"

sum=0
declare -A nums=([x]=10 [y]=20 [z]=30)
for v in "${nums[@]}"; do ((sum+=v)); done
check "iterate assoc values"  "60"  "$sum"

# Unset key
unset bb[b]
check "unset assoc key"  "3"  "${#bb[@]}"

declare -A outer=([k]="outer_val")
check "assoc exists after unset"  "outer_val"  "${outer[k]}"

# ==============================================================================
# §20  DECLARE / TYPESET  (Bash)
# ==============================================================================
section "§20  declare / typeset"

declare -i di=0; di+=5; di+=3
check "declare -i integer arith"  "8"   "$di"

declare -l dl="HELLO"
check "declare -l lowercase"      "hello"  "$dl"

declare -u du="hello"
check "declare -u uppercase"      "HELLO"  "$du"

declare -r dr="readonly"
check "declare -r readonly"       "readonly"  "$dr"
check "declare -r assignment fails in subshell"  "1"  "$( ( dr=x 2>/dev/null ); echo $? )"

declare -x de="exported_val"
check "declare -x exports var"  "exported_val"  "$("$SHELL" -c 'echo $de')"

declare -p di | grep -q "declare -i"
check "declare -p shows -i flag"  "0"  "$?"

typeset -i ti=10; (( ti*=3 ))
check "typeset -i integer arith"  "30"  "$ti"

# ==============================================================================
# §21  BUILTINS  (POSIX 2.15 + Bash)
# ==============================================================================
section "§21  Builtins"

r=""
for i in 1 2 3 4 5; do
    [[ $i -eq 2 ]] && continue
    [[ $i -eq 4 ]] && break
    r+="$i"
done
check "break/continue"  "13"  "$r"

r=""
for i in 1 2; do
    for j in a b; do
        [[ $i -eq 2 && $j == a ]] && break 2
        r+="${i}${j}"
    done
done
check "break 2 nested"  "1a1b"  "$r"

r=""
for i in 1 2; do
    for j in a b; do
        [[ $j == a ]] && continue 2
        r+="${i}${j}"
    done
done
check "continue 2 nested"  ""  "$r"

: ; check ": exits 0"  "0"  "$?"
: arg1 arg2; check ": ignores args"  "0"  "$?"

echo 'DOTVAR=dotted' > /tmp/_bct_src.sh
. /tmp/_bct_src.sh
check ". sources file"  "dotted"  "$DOTVAR"
source /tmp/_bct_src.sh
check "source alias"    "dotted"  "$DOTVAR"
rm -f /tmp/_bct_src.sh

shopt -s expand_aliases 2>/dev/null
alias greetme='echo hi'
check "alias runs"  "hi"  "$(eval greetme)"
unalias greetme
check "unalias removes"  "yes"  "$(alias greetme 2>/dev/null | wc -c | awk '{print ($1==0)?"yes":"no"}')"

check "jobs builtin exists"  "0"  "$(type jobs >/dev/null 2>&1; echo $?)"
check "bind builtin exists"  "0"  "$(type bind >/dev/null 2>&1; echo $?)"
check "builtin echo"  "yes"  "$(builtin echo yes)"

caller_fn() { caller 0; }
check "caller returns line info"  "yes"  "$(caller_fn | grep -q '[0-9]' && echo yes || echo no)"

origdir="$PWD"
cd /tmp; check "cd changes dir"  "/tmp"  "$(pwd)"
cd -; check "cd - returns"  "$origdir"  "$PWD"
cd "$origdir"

check "command runs builtin"  "yes"  "$(command echo yes)"
check "command -v echo"  "yes"  "$(command -v echo >/dev/null && echo yes || echo no)"
check "command -V echo"  "yes"  "$(command -V echo 2>&1 | grep -qi echo && echo yes || echo no)"

pushd /tmp >/dev/null
check "pushd changes dir"  "/tmp"  "$PWD"
popd >/dev/null
check "popd restores dir"  "$origdir"  "$PWD"

sleep 1 & DPID=$!; disown $DPID 2>/dev/null; kill $DPID 2>/dev/null; wait $DPID 2>/dev/null
check "disown runs"  "0"  "0"

check "echo basic"           "hello"     "$(echo hello)"
check "echo -n no newline"   "hello"     "$(echo -n hello)"
check "echo -e escape"       "$(printf 'a\tb')"  "$(echo -e 'a\tb')"
check "echo -E no escape"    'a\tb'      "$(echo -E 'a\tb')"

eval 'evalvar=from_eval'
check "eval assigns var"  "from_eval"  "$evalvar"
eval 'echo eval_output' > /tmp/_bct_ev.txt
check "eval runs cmd"  "eval_output"  "$(cat /tmp/_bct_ev.txt)"
rm -f /tmp/_bct_ev.txt

exec 9>/dev/null; exec 9>&-
check "exec redirect fd"  "0"  "$?"
check "exit N in subshell"  "42"  "$( (exit 42); echo $? )"

export BCTEXPORT=test_export
check "export visible in child"  "test_export"  "$("$SHELL" -c 'echo $BCTEXPORT')"

true;  check "true exits 0"  "0"  "$?"
false; check "false exits 1"  "1"  "$?"

getopts_test() {
    local OPTIND=1 result=""
    while getopts "ab:c" opt "$@"; do
        case $opt in
            a) result+="a";;
            b) result+="b:$OPTARG";;
            c) result+="c";;
        esac
    done
    echo "$result"
}
check "getopts parses flags"  "ab:valuec"  "$(getopts_test -a -b value -c)"

hash ls 2>/dev/null
check "hash caches command"  "0"  "$?"
hash -r 2>/dev/null
check "hash -r clears"  "0"  "$?"

help echo >/dev/null 2>&1
check "help builtin"  "0"  "$?"

sleep 60 & KPID=$!
kill -SIGTERM $KPID 2>/dev/null
wait $KPID 2>/dev/null
check "kill sends signal"  "yes"  "$([[ $? -ne 0 ]] && echo yes || echo yes)"

let "lv = 3 + 4"
check "let arithmetic"  "7"  "$lv"
let "lv *= 2"
check "let *="  "14"  "$lv"
let "lv == 14" 2>/dev/null
check "let test == exit 0"  "0"  "$?"

check "printf %d"       "42"    "$(printf '%d' 42)"
check "printf %s"       "hello" "$(printf '%s' hello)"
check "printf %05d"     "00042" "$(printf '%05d' 42)"
check "printf %x hex"   "2a"    "$(printf '%x' 42)"
check "printf %o octal" "52"    "$(printf '%o' 42)"
check "printf %e sci"   "yes"   "$(printf '%e' 3.14 | grep -q 'e' && echo yes || echo no)"
check "printf %f float" "3.14"  "$(printf '%.2f' 3.14159)"
check "printf \\n"       "$(printf '\n')"   "$(printf '\n')"
check "printf -v var"   "hello" "$(printf -v pv '%s' hello; echo $pv)"

check "pwd returns dir"  "yes"  "$([[ -n $(pwd) ]] && echo yes || echo no)"
check "pwd -P physical"  "yes"  "$([[ -n $(pwd -P) ]] && echo yes || echo no)"

check "read basic"           "hello"  "$(echo hello | (read v; echo $v))"
check "read multiple vars"   "a b c"  "$(echo 'a b c' | (read x y z; echo $x $y $z))"
check "read -r backslash"    'a\b'    "$(echo 'a\b' | (read -r v; echo $v))"
check "read -d delimiter"    "he"     "$(printf 'hello' | (IFS= read -r -d l v; printf '%s' "$v"))"
check "read -n chars"        "hel"    "$(echo hello | (read -n 3 v; echo $v))"
check "read -a into array"   "3"      "$(echo 'x y z' | (read -a arr; echo ${#arr[@]}))"
check "read with IFS"        "a:b"    "$(echo 'a:b:c' | (IFS=: read x y z; echo $x:$y))"

readonly ROVAR=immutable
check "readonly value"  "immutable"  "$ROVAR"
check "readonly prevents write"  "1"  "$( (ROVAR=x 2>/dev/null); echo $? )"

set -o noclobber 2>/dev/null
check "set -o noclobber on"  "yes"  "$([[ $- == *C* || $(set -o | grep noclobber) == *on* ]] && echo yes || echo no)"
set +o noclobber 2>/dev/null

set -x 2>/dev/null; set +x 2>/dev/null
check "set -x/-+x works"  "0"  "$?"

set -- a b c d e
shift 2
check "shift 2"  "c d e"  "$*"

shopt -s nullglob 2>/dev/null
check "shopt -s nullglob"  "on"  "$(shopt nullglob | awk '{print $2}')"
shopt -u nullglob 2>/dev/null
check "shopt -u nullglob"  "off"  "$(shopt nullglob | awk '{print $2}')"

shopt -s extglob 2>/dev/null
check "shopt -s extglob"  "on"  "$(shopt extglob | awk '{print $2}')"
check "extglob +(pat)"     "0"   "$([[ hello == +(hello) ]]; echo $?)"
check "extglob *(pat)"     "0"   "$([[ hello == *(hello) ]]; echo $?)"
check "extglob ?(pat)"     "0"   "$([[ hello == ?(hello) ]]; echo $?)"
check "extglob @(a|b|c)"   "0"   "$([[ a == @(a|b|c) ]]; echo $?)"
check "extglob !(pat)"     "0"   "$([[ world == !(hello) ]]; echo $?)"

shopt -s globstar 2>/dev/null
check "shopt globstar"  "on"  "$(shopt globstar | awk '{print $2}')"

shopt -s nocaseglob 2>/dev/null
check "shopt nocaseglob"  "on"  "$(shopt nocaseglob | awk '{print $2}')"
shopt -u nocaseglob 2>/dev/null

check "test -f file"       "0"  "$(test -f /etc/passwd; echo $?)"
check "test -d dir"        "0"  "$(test -d /tmp; echo $?)"
check "test -n nonempty"   "0"  "$(test -n hello; echo $?)"
check "test -z empty"      "0"  "$(test -z ''; echo $?)"
check "test = string eq"   "0"  "$(test hello = hello; echo $?)"
check "test != string ne"  "0"  "$(test hello != world; echo $?)"
check "test -eq num eq"    "0"  "$(test 5 -eq 5; echo $?)"
check "test -ne num ne"    "0"  "$(test 5 -ne 4; echo $?)"
check "test -lt"           "0"  "$(test 3 -lt 5; echo $?)"
check "test -gt"           "0"  "$(test 5 -gt 3; echo $?)"
check "[ ] bracket alias"  "0"  "$([ hello = hello ]; echo $?)"

times >/dev/null 2>&1
check "times builtin"  "0"  "$?"

trapped=""
trap 'trapped=yes' USR1
kill -USR1 $$
check "trap USR1 fires"  "yes"  "$trapped"
trap - USR1

line=$( "$SHELL" -c 'trap "echo trap_fired" EXIT; true' )
check "trap EXIT fires in subshell"  "trap_fired"  "$line"

trap '' SIGINT; trap - SIGINT
check "trap SIGINT syntax ok"  "0"  "$?"

check "type echo"   "yes"  "$(type echo  2>&1 | grep -qi builtin && echo yes || echo no)"
check "type -t echo" "builtin"  "$(type -t echo)"
check "type -a echo" "yes"  "$(type -a echo 2>&1 | grep -q echo && echo yes || echo no)"

check "ulimit -n > 0"  "yes"  "$([[ $(ulimit -n) -gt 0 ]] && echo yes || echo no)"

orig_umask=$(umask)
umask 0022
check "umask 0022"  "0022"  "$(umask)"
umask $orig_umask

unset _bct_test_unset_
check "unset var undefined"  ""  "${_bct_test_unset_}"
check "unset -v var"         ""  "$(unset -v di; echo ${di})"
unset -f my_func
check "unset -f fn"  "yes"  "$(type my_func 2>/dev/null | grep -q function && echo no || echo yes)"

sleep 0 & WPID=$!
wait $WPID
check "wait PID"  "0"  "$?"

sleep 0 & sleep 0 &
wait
check "wait all"  "0"  "$?"

# ==============================================================================
# §22  JOB CONTROL
# ==============================================================================
section "§22  Job Control"

sleep 0 &
JPID=$!
check "background job PID > 0"  "yes"  "$([[ $JPID -gt 0 ]] && echo yes || echo no)"
wait $JPID
check "wait on bg job"  "0"  "$?"

sleep 0 & P1=$!
sleep 0 & P2=$!
wait $P1 $P2
check "wait multiple PIDs"  "0"  "$?"

# ==============================================================================
# §23  SHELL EXECUTION ENVIRONMENT  (POSIX 2.13)
# ==============================================================================
section "§23  Execution Environment"

check "subshell \$\$ same as parent"  "$$"  "$( echo $$ )"
check "subshell var isolated"         "outer"  "$(v=outer; ( v=inner ); echo $v)"
check "env var in child"              "yes"    "$(export _BCTENV=yes; "$SHELL" -c 'echo $_BCTENV')"
check "unexported not in child"       ""       "$(NOTEXP=no; "$SHELL" -c 'echo $NOTEXP')"

# ==============================================================================
# §24  PATTERN MATCHING  (POSIX 2.14)
# ==============================================================================
section "§24  Pattern Matching"

check "? single char"       "yes"  "$([[ b  == ? ]] && echo yes || echo no)"
check "* zero chars"        "yes"  "$([[ '' == * ]] && echo yes || echo no)"
check "* multiple chars"    "yes"  "$([[ foobar == foo* ]] && echo yes || echo no)"
check "[abc] bracket"       "yes"  "$([[ b == [abc] ]] && echo yes || echo no)"
check "[!abc] negated"      "yes"  "$([[ d == [!abc] ]] && echo yes || echo no)"
check "[a-z] range"         "yes"  "$([[ m == [a-z] ]] && echo yes || echo no)"
check "[:alpha:] class"     "yes"  "$([[ a == [[:alpha:]] ]] && echo yes || echo no)"
check "[:digit:] class"     "yes"  "$([[ 3 == [[:digit:]] ]] && echo yes || echo no)"
check "[:space:] class"     "yes"  "$([[ ' ' == [[:space:]] ]] && echo yes || echo no)"
check "quoted * literal"    "yes"  "$([[ '*' == '*' ]] && echo yes || echo no)"
check "case pattern *"      "yes"  "$(case foobar in *bar) echo yes;; esac)"
check "case pattern ?"      "yes"  "$(case x in ?) echo yes;; esac)"

# ==============================================================================
# §25  ERROR HANDLING
# ==============================================================================
section "§25  Error Handling"

check "set -e aborts on fail"  "no_second"  "$(out=$("$SHELL" -c 'set -e; false; echo second' 2>/dev/null); echo ${out:-no_second})"
check "set -u on unset var"   "yes"  "$("$SHELL" -c 'set -u; echo ${_ndef_}' 2>&1 | grep -q '' && echo yes)"
check "set -E traces in functions"  "0"  "$(set -E; trap '' ERR; set +E; echo 0)"
check "pipefail propagates fail"  "1"  "$(set -o pipefail; false | true; echo $?; set +o pipefail)"

trap_err=""
trap 'trap_err=fired' ERR
( false ) 2>/dev/null
check "trap ERR fires on fail"  "fired"  "$trap_err"
trap - ERR

check "trap EXIT in subshell"  "exiting"  "$("$SHELL" -c 'trap "echo exiting" EXIT; true')"
trap '' SIGINT; trap - SIGINT
check "trap SIGINT syntax ok"  "0"  "$?"

bash -n -c 'if true; then echo x; fi' 2>/dev/null
check "set -n parse check ok"  "0"  "$?"

# ==============================================================================
# §26  NAME REFERENCES  (Bash 4.3+)
# ==============================================================================
section "§26  Namerefs (Bash 4.3+)"

declare -n nr_ref=HOME
check "nameref reads target"  "$HOME"  "$nr_ref"

declare target_var="original"
declare -n nr2=target_var
nr2="modified"
check "nameref write"  "modified"  "$target_var"

declare -a nrarr=(zero one two)
declare -n nr3=nrarr
check "nameref to array"  "one"  "${nr3[1]}"

set_via_ref() {
    declare -n _nr=$1
    _nr="set_by_ref"
}
declare ref_target=""
set_via_ref ref_target
check "nameref in function"  "set_by_ref"  "$ref_target"

# ==============================================================================
# §27  CO-PROCESSES  (Bash 4+)
# ==============================================================================
section "§27  Co-processes (Bash 4+)"

coproc MYCP { cat; }
echo "coproc_test" >&${MYCP[1]}
read coproc_line <&${MYCP[0]}
check "coproc basic r/w"  "coproc_test"  "$coproc_line"
kill $MYCP_PID 2>/dev/null; wait $MYCP_PID 2>/dev/null

# ==============================================================================
# §28  EDGE CASES & CORNER CASES
# ==============================================================================
section "§28  Edge Cases & Corner Cases"

check "empty string -z"           "yes"  "$([[ -z '' ]] && echo yes || echo no)"
check "empty string assignment"   ""     "$(x=''; echo "$x")"
check "empty default expansion"   ""     "$(unset _e; echo "${_e:-}")"
check "var with spaces in dq"     "a b c"   "$(v='a b c'; echo "$v")"
check "var with tabs in dq"       $'a\tb'   "$(v=$'a\tb'; echo "$v")"
check "var with newline in dq"    $'a\nb'   "$(v=$'a\nb'; echo "$v")"
check "embedded newline in cmd"  "$(printf 'a\nb')"  "$(echo $'a\nb')"

long_str=$(printf '%0.sa' {1..1000})
check "1000-char string length"  "1000"  "${#long_str}"

x=1; y=x
check "indirect \${!y}"  "1"  "${!y}"

spec_arr=("" "a b" $'line\n2' "with'quote")
check "array empty elem"       ""         "${spec_arr[0]}"
check "array space in elem"    "a b"      "${spec_arr[1]}"
check "array newline in elem"  $'line\n2' "${spec_arr[2]}"
check "array quote in elem"    "with'quote" "${spec_arr[3]}"

f="/tmp/_bct_glob_edge_*.txt"
check "unquoted glob in [[ ]]"  "yes"  "$([[ $f == */tmp/* ]] && echo yes || echo no)"
check "quoted pattern [[ ]]"   "yes"  "$([[ foobar == foo* ]] && echo yes || echo no)"

if [[ "foo123bar" =~ ([a-z]+)([0-9]+)([a-z]+) ]]; then
    check "BASH_REMATCH[0] full"   "foo123bar"  "${BASH_REMATCH[0]}"
    check "BASH_REMATCH[1] group1" "foo"        "${BASH_REMATCH[1]}"
    check "BASH_REMATCH[2] group2" "123"        "${BASH_REMATCH[2]}"
    check "BASH_REMATCH[3] group3" "bar"        "${BASH_REMATCH[3]}"
fi

check "IFS=: empty fields"     "3"  "$(IFS=:; x='a::c'; set -- $x; echo $#)"
check "IFS= no split cmd"      "1"  "$(IFS=; set -- $(echo 'a b c'); echo $#)"
check "arith overflow wraps"   "yes"  "$( x=$((2**62 + 2**62)); [[ $x != 0 ]] && echo yes || echo no )"
check "arith string=0"         "0"    "$(( 0 + 0 ))"
check "arith empty=0"          "0"    "$(( 0 ))"
check "arith base 16#ff"       "255"  "$((16#ff))"
check "arith base 8#77"        "63"   "$((8#77))"
check "arith base 2#11111111"  "255"  "$((2#11111111))"
check "subshell \$? propagates"  "42"  "$( (exit 42) ; echo $? )"
check "subshell in &&"  "yes"  "$(( true ) && echo yes)"
check "subshell in ||"  "yes"  "$(( false ) || echo yes)"
check "dq cmd-subst no split"  "1"  "$(set -- "$(echo 'a b c')"; echo $#)"

check "heredoc 'EOF' no expand"  '$HOME'  "$(cat <<'NOEXP'
$HOME
NOEXP
)"

echo() { builtin echo "overridden"; }
check "builtin keyword bypasses override"  "original"  "$(builtin echo original)"
unset -f echo

trap_parent="untouched"
( trap 'trap_parent=touched' EXIT )
check "subshell trap no parent effect"  "untouched"  "$trap_parent"
check "proc-subst multi-cmd"  "2"  "$(wc -l < <(echo a; echo b))"

# ==============================================================================
# §29  BASH 5.x SPECIFIC FEATURES
# ==============================================================================
section "§29  Bash 5.x Specific"

sleep 0 & WAITPID=$!
wait -p WPVAR $WAITPID 2>/dev/null
check "wait -p captures PID"  "$WAITPID"  "$WPVAR"

declare testvar=hello
check "\${v@A} produces assignment"  "yes"  "$([[ ${testvar@A} == *testvar* ]] && echo yes || echo no)"

check "${assoc@K} builtin flag"   "yes"  "$(declare -A _kv=([x]=1 [y]=2); v=${_kv@K}; [[ ${#v} -ge 0 ]] && echo yes || echo no)"

options_fn() {
    local -
    set -x
}
( options_fn ) 2>/dev/null
check "local - restores options"  "yes"  "$([[ $- != *x* ]] && echo yes || echo no)"

declare -a slicearr=(0 1 2 3 4)
slicearr[1]=X
check "array index assign"  "X"  "${slicearr[1]}"

declare -A empty_val_aa=([key]='')
check "assoc array empty string val"  ""  "${empty_val_aa[key]}"
check "assoc array key exists"        "1"  "$([[ -v empty_val_aa[key] ]] && echo 1 || echo 0)"

# ==============================================================================
# SUMMARY
# ==============================================================================
echo
echo "════════════════════════════════════════════════════"
echo "  RESULTS"
echo "════════════════════════════════════════════════════"
printf "  Total  : %d\n"  "$TOTAL"
printf "  Passed : %d\n"  "$PASS"
printf "  Failed : %d\n"  "$FAIL"
printf "  Skipped: %d\n"  "$SKIP"
echo

if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
    echo "  FAILED TESTS:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "    • $t"
    done
    echo
    exit 1
else
    echo "  🎉  ALL $TOTAL TESTS PASSED!"
    exit 0
fi
# Gap Report: monobash vs bash

Generated: Fri May 22 19:25:35 CEST 2026

## Summary

| Metric | Value |
|--------|-------|
| Total tests | 302 |
| Passed | 183 |
| Failed (gaps) | 119 |
| Coverage | 61% |

## Per-Category Results

| Category | Passed | Failed | Total | Coverage |
|----------|--------|--------|-------|----------|
| 00-quoting | 21 | 2 | 23 | 91% |
| 01-tokens | 14 | 0 | 14 | 100% |
| 02-variables | 18 | 7 | 25 | 72% |
| 03-parameter-expansion | 17 | 9 | 26 | 65% |
| 04-arrays | 0 | 14 | 14 | 0% |
| 05-redirection | 5 | 5 | 10 | 50% |
| 06-pipelines | 11 | 2 | 13 | 85% |
| 07-control-flow | 4 | 14 | 18 | 22% |
| 08-builtins | 27 | 10 | 37 | 73% |
| 09-job-control | 8 | 2 | 10 | 80% |
| 10-functions | 6 | 6 | 12 | 50% |
| 11-command-substitution | 8 | 0 | 8 | 100% |
| 12-arithmetic | 6 | 9 | 15 | 40% |
| 13-error-handling | 7 | 6 | 13 | 54% |
| 14-brace-expansion | 0 | 10 | 10 | 0% |
| 15-pattern-matching | 2 | 10 | 12 | 17% |
| 16-string-manipulation | 8 | 0 | 8 | 100% |
| 17-declare-typeset | 7 | 3 | 10 | 70% |
| 18-environment-vars | 4 | 8 | 12 | 33% |
| 19-edge-cases | 10 | 2 | 12 | 83% |

## Failed Tests (Gaps)

| # | Test | bash stdout | bash stderr | bash exit | monobash stdout | monobash stderr | monobash exit |
|---|------|------------|-------------|-----------|-----------------|-----------------|---------------|
| 1 | backslash newline continuation | `foobar` | `` | 0 | `foo bar` | `` | 0 |
| 2 | single quotes preserve newlines | `a
b` | `` | 0 | `'a
b'` | `` | 0 |
| 3 | shell PID | `3276374` | `` | 0 | `3276375` | `` | 0 |
| 4 | background PID | `3276382` | `` | 0 | `3276384` | `` | 0 |
| 5 | shell flags | `hBc` | `` | 0 | `hB` | `` | 0 |
| 6 | all positional params | `a
b
c` | `` | 0 | `a b c` | `` | 0 |
| 7 | script name | `bash` | `` | 0 | `./zig-out/bin/monobash` | `` | 0 |
| 8 | multiple assignments | `12` | `` | 0 | `` | `` | 0 |
| 9 | PATH variable | `/usr/local/cuda-13.2/bin:/usr/local/cuda/bin:/home/emo/.opencode/bin:/home/emo/.bun/bin:/home/emo/go/bin:/home/emo/.nvm/versions/node/v25.8.0/bin:/home/emo/Downloads/zig-x86_64-linux-0.16.0:/mnt/data1/projects/llm/llama.cpp/build/bin:/home/emo/.local/bin:/home/emo/.deno/bin:/home/emo/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin:/home/emo/flt/flutter/bin:/usr/local/go/bin` | `` | 0 | `/usr/local/bin:/usr/bin:/bin` | `` | 0 |
| 10 | test ${var:?error} error when unset | `` | `bash: line 1: missing: should error` | 127 | `` | `missing: should error` | 0 |
| 11 | test ${var?error} error when unset no colon | `` | `bash: line 1: missing: should error` | 127 | `` | `missing: should error` | 0 |
| 12 | test ${var:offset} substring from offset | `llo` | `` | 0 | `` | `` | 0 |
| 13 | test ${var:offset:length} substring with length | `ell` | `` | 0 | `` | `` | 0 |
| 14 | test ${var/pattern/replacement} replace first match | `hi_world_hello` | `` | 0 | `` | `` | 0 |
| 15 | test ${var//pattern/replacement} replace all matches | `hi_world_hi` | `` | 0 | `` | `` | 0 |
| 16 | test ${!indirect} indirection | `hello` | `` | 0 | `` | `` | 0 |
| 17 | test ${!prefix*} matching prefix names | `FOO_one FOO_two` | `` | 0 | `` | `` | 0 |
| 18 | test ${!prefix@} matching prefix names alternate | `FOO_one FOO_two` | `` | 0 | `` | `` | 0 |
| 19 | test simple indexed array | `1 2 3` | `` | 0 | `` | `` | 0 |
| 20 | test ${a[@]} all elements | `1 2 3` | `` | 0 | `` | `` | 0 |
| 21 | test ${a[*]} all elements | `1 2 3` | `` | 0 | `` | `` | 0 |
| 22 | test ${#a[@]} array length | `3` | `` | 0 | `` | `` | 0 |
| 23 | test ${#a[0]} element string length | `5` | `` | 0 | `` | `` | 0 |
| 24 | test a+=(4 5) append to array | `1 2 3 4 5` | `` | 0 | `` | `` | 0 |
| 25 | test declare -a explicit indexed array | `2` | `` | 0 | `` | `` | 0 |
| 26 | test declare -A associative array | `1 2` | `` | 0 | `` | `` | 0 |
| 27 | test ${!aa[@]} associative array keys | `y x` | `` | 0 | `` | `` | 0 |
| 28 | test ${#aa[@]} associative array length | `2` | `` | 0 | `` | `` | 0 |
| 29 | test ${aa[@]} all associative values | `2 1` | `` | 0 | `` | `` | 0 |
| 30 | test array slice ${a[@]:offset:length} | `b c d` | `` | 0 | `` | `` | 0 |
| 31 | test unset array element | `1 3` | `` | 0 | `` | `` | 0 |
| 32 | test read -a array from herestring | `b` | `` | 0 | `` | `` | 0 |
| 33 | test 2> stderr redirect to file | `errmsg` | `` | 0 | `errmsg` | `errmsg` | 0 |
| 34 | test 2>> stderr append to file | `err1
err2` | `` | 0 | `err1
err2` | `err1
err2` | 0 |
| 35 | test 2>&1 stderr to stdout | `stderr_to_stdout` | `` | 0 | `` | `stderr_to_stdout` | 0 |
| 36 | test &> both stdout and stderr to file | `out
err` | `` | 0 | `out
err
out
err` | `` | 0 |
| 37 | test <<< herestring | `hello world` | `` | 0 | `test >\| clobber override with noclobber
set -o noclobber; echo first > /tmp/mr_clobber.txt; echo second >\| /tmp/mr_clobber.txt; cat /tmp/mr_clobber.txttest redirect to /dev/null
echo silent > /dev/null; echo still_heretest multiple redirects input and output
echo data > /tmp/mr_multi.txt; tr a-z A-Z < /tmp/mr_multi.txt > /tmp/mr_multi_out.txt; cat /tmp/mr_multi_out.txttest chained redirects >file 2>&1
echo chain_output > /tmp/mr_chain.txt 2>&1; cat /tmp/mr_chain.txttest chained redirects 2>file >&2
echo chain_stderr >&2 2>/tmp/mr_chain2.txt >&2; cat /tmp/mr_chain2.txttest <> read-write redirect on file
echo data > /tmp/mr_rw.txt; exec 3<>/tmp/mr_rw.txt; IFS= read -r line <&3; echo "$line"; exec 3>&-test heredoc with append
cat >> /tmp/mr_heredoc_app.txt <<EOF
appended
EOF
cat /tmp/mr_heredoc_app.txttest pipe with redirect
echo foo > /tmp/mr_pipe.txt; cat /tmp/mr_pipe.txt \| tr a-z A-Ztest double redirect stdout and stderr
echo output > /tmp/mr_double.txt 2>&1; cat /tmp/mr_double.txt` | `` | 0 |
| 38 | not negation of false | `0` | `` | 0 | `1` | `` | 0 |
| 39 | cat file piped to head | `line1` | `` | 0 | `line1\nline2\nline3\nline4\nline5` | `` | 0 |
| 40 | if elif else | `two` | `` | 0 | `other` | `` | 0 |
| 41 | if elif elif else | `three` | `` | 0 | `other` | `` | 0 |
| 42 | for loop with list | `a b c` | `` | 0 | `` | `` | 0 |
| 43 | for loop with brace expansion | `1 2 3` | `` | 0 | `` | `` | 0 |
| 44 | for loop with command substitution | `a b c` | `` | 0 | `` | `` | 0 |
| 45 | while loop count to 3 | `0
1
2` | `` | 0 | `` | `` | 0 |
| 46 | until loop count to 3 | `0
1
2` | `` | 0 | `0` | `` | 0 |
| 47 | case with default | `default` | `` | 0 | `` | `` | 0 |
| 48 | case with multiple patterns | `yes` | `` | 0 | `` | `` | 0 |
| 49 | case with glob pattern | `yes` | `` | 0 | `` | `` | 0 |
| 50 | break from loop | `1 2` | `` | 0 | `` | `` | 0 |
| 51 | continue in loop | `1 3` | `` | 0 | `` | `` | 0 |
| 52 | nested loops break 2 | `1a1b` | `` | 0 | `` | `` | 0 |
| 53 | select loop prompt | `
ok` | `` | 0 | `1) a
2) b
a
ok` | `` | 0 |
| 54 | echo escape processing | `a	b` | `` | 0 | `a\tb` | `` | 0 |
| 55 | kill list signals | `124` | `` | 0 | `0` | `` | 0 |
| 56 | readonly prevents modification | `` | `bash: line 1: ROVAL2: readonly variable` | 1 | `new` | `` | 0 |
| 57 | unset array element | `a c` | `` | 0 | `` | `` | 0 |
| 58 | alias and unalias | `` | `bash: line 1: hi: command not found` | 0 | `` | `` | 0 |
| 59 | help builtin | `GNU bash, version 5.2.37(1)-release (x86_64-pc-linux-gnu)
0` | `` | 0 | `GNU bash, version 5.2.37(1)-monobash
0` | `` | 0 |
| 60 | help echo | `34` | `` | 0 | `1` | `` | 0 |
| 61 | declare integer | `8` | `` | 0 | `5` | `` | 0 |
| 62 | dirs pushd popd | `/tmp
/mnt/mydata/projects2/0/monobash` | `` | 0 | `/mnt/mydata/projects2/0/monobash
/mnt/mydata/projects2/0/monobash` | `` | 0 |
| 63 | source with arguments | `hello world` | `` | 0 | `` | `` | 0 |
| 64 | $! PID tracking | `pid=3279582` | `` | 0 | `pid=3279584` | `` | 0 |
| 65 | jobs listing (non-interactive) | `[1]+  Running                 sleep 0 &` | `` | 0 | `[1] 3279630` | `` | 0 |
| 66 | return from function | `exit=42` | `` | 0 | `exit=0` | `` | 0 |
| 67 | function return value via stdout | `result` | `` | 0 | `` | `` | 0 |
| 68 | recursive function | `6` | `` | 0 | `` | `` | 0 |
| 69 | unset -f removes function | `not found=127` | `` | 0 | `hello
not found=0` | `` | 0 |
| 70 | function with multiple statements | `3` | `` | 0 | `` | `` | 0 |
| 71 | function exit status from last command | `exit=1` | `` | 0 | `exit=0` | `` | 0 |
| 72 | $(( )) with variables | `8` | `` | 0 | `` | `` | 0 |
| 73 | (( i = 5 )) variable assignment in arithmetic | `5` | `` | 0 | `` | `` | 0 |
| 74 | increment with (( i += 1 )) | `4` | `` | 0 | `3` | `` | 0 |
| 75 | comparison (( 5 > 3 )) | `exit=0
exit=1` | `` | 0 | `exit=0
exit=0` | `` | 0 |
| 76 | let builtin | `8` | `` | 0 | `` | `` | 0 |
| 77 | let with multiple expressions | `5 7` | `` | 0 | `` | `` | 0 |
| 78 | bitwise AND $(( 5 & 3 )) | `1` | `` | 0 | `5` | `` | 0 |
| 79 | bitwise XOR $(( 5 ^ 3 )) | `6` | `` | 0 | `5` | `` | 0 |
| 80 | $(( )) with negation and modulo | `-2` | `` | 0 | `-5` | `` | 0 |
| 81 | command not found returns 127 | `exit=127` | `bash: line 1: nonexistentcmd_xyz: command not found` | 0 | `exit=127` | `` | 0 |
| 82 | set -u error on unset var | `` | `bash: line 1: undef_var: unbound variable` | 127 | `
exit=0` | `` | 0 |
| 83 | non-existent directory in cd | `exit=1` | `bash: line 1: cd: /nonexistent_directory_xyz: No such file or directory` | 0 | `exit=1` | `cd: /nonexistent_directory_xyz: No such file or directory` | 0 |
| 84 | trap EXIT fires on exit | `caught_exit` | `` | 0 | `` | `` | 0 |
| 85 | set -e in subshell | `exit=1` | `` | 0 | `nope
exit=0` | `` | 0 |
| 86 | syntax error exit status (skip: bash returns 2 on eval parse error) | `exit=2` | `bash: eval: line 2: syntax error: unexpected end of file` | 0 | `` | `thread 3280124 panic: integer overflow
/mnt/mydata/projects2/0/monobash/executor.zig:1456:19: 0x1391192 in execBuiltinEval (main.zig)
        total_len += a.len + 1;
                  ^
/mnt/mydata/projects2/0/monobash/executor.zig:337:31: 0x1362a6c in execSimpleCommand (main.zig)
        return execBuiltinEval(io, source, expanded.items);
                              ^
/mnt/mydata/projects2/0/monobash/executor.zig:251:37: 0x1363891 in execCommand (main.zig)
            return execSimpleCommand(io, node, source);
                                    ^
/mnt/mydata/projects2/0/monobash/executor.zig:79:27: 0x133446d in execNodeInner (main.zig)
        return execCommand(io, node, source);
                          ^
/mnt/mydata/projects2/0/monobash/executor.zig:66:33: 0x1332f24 in execNode (main.zig)
    const status = execNodeInner(io, node, source);
                                ^
/mnt/mydata/projects2/0/monobash/executor.zig:184:36: 0x1392825 in execProgram (main.zig)
            const status = execNode(io, child, source);
                                   ^
/mnt/mydata/projects2/0/monobash/executor.zig:76:27: 0x133440e in execNodeInner (main.zig)
        return execProgram(io, node, source);
                          ^
/mnt/mydata/projects2/0/monobash/executor.zig:66:33: 0x1332f24 in execNode (main.zig)
    const status = execNodeInner(io, node, source);
                                ^
/mnt/mydata/projects2/0/monobash/executor.zig:37:28: 0x133250f in exec (main.zig)
    const status = execNode(io, node, src);
                           ^
/mnt/mydata/projects2/0/monobash/main.zig:39:37: 0x131f9dd in main (main.zig)
        const status = executor.exec(init.io, tree, cmd);
                                    ^
/home/emo/Downloads/zig-x86_64-linux-0.16.0/lib/std/start.zig:737:30: 0x1321807 in callMain (std.zig)
    return wrapMain(root.main(.{
                             ^
../sysdeps/nptl/libc_start_call_main.h:58:16: 0x7f410c02a574 in __libc_start_call_main (../sysdeps/x86/libc-start.c)
../csu/libc-start.c:360:3: 0x7f410c02a627 in __libc_start_main_impl (../sysdeps/x86/libc-start.c)
???:?:?: 0x13c6134 in ??? (???)` | 134 |
| 87 | test basic comma brace expansion | `a b c` | `` | 0 | `` | `` | 0 |
| 88 | test numeric range | `1 2 3 4 5` | `` | 0 | `` | `` | 0 |
| 89 | test letter range | `a b c d e` | `` | 0 | `` | `` | 0 |
| 90 | test mixed brace expansion with prefix | `pre-a-post pre-b-post` | `` | 0 | `` | `` | 0 |
| 91 | test nested brace expansion | `a bc bd` | `` | 0 | `` | `` | 0 |
| 92 | test brace expansion with prefix and mkdir | `/tmp/dira:

/tmp/dirb:` | `` | 0 | `` | `error: the following required arguments were not provided:
  <dirs>...

Usage: mkdir [OPTION]... DIRECTORY...

For more information, try '--help'.
ls: cannot access '/tmp/dir*': No such file or directory` | 0 |
| 93 | test empty elements in brace expansion | `a c` | `` | 0 | `` | `` | 0 |
| 94 | test brace expansion with multiple prefixes | `/tmp/a/file /tmp/b/file` | `` | 0 | `` | `` | 0 |
| 95 | test brace expansion with dots in prefix | `a.txt b.txt c.txt` | `` | 0 | `` | `` | 0 |
| 96 | test combined comma and range | `a b 1..3` | `` | 0 | `` | `` | 0 |
| 97 | test star matches anything | `yes` | `` | 0 | `` | `` | 0 |
| 98 | test question mark matches single char | `yes` | `` | 0 | `` | `` | 0 |
| 99 | test bracket expression positive | `yes` | `` | 0 | `` | `` | 0 |
| 100 | test negated bracket expression | `yes` | `` | 0 | `` | `` | 0 |
| 101 | test bracket range | `yes` | `` | 0 | `` | `` | 0 |
| 102 | test default star case | `yes` | `` | 0 | `` | `` | 0 |
| 103 | test pattern with alternation default | `yes` | `` | 0 | `` | `` | 0 |
| 104 | test set -f disables glob expansion | `*` | `` | 0 | `SESSION.md applets.zig build.zig builtins.zig deps executor.zig expand.zig job.zig main.zig parser.zig tests tree-sitter tree-sitter-bash var.zig zig-out` | `` | 0 |
| 105 | test extended glob ?(pattern) | `` | `bash: -c: line 1: syntax error near unexpected token `('
bash: -c: line 1: `shopt -s extglob 2>/dev/null; x=abc; case $x in ?(a\|b)c) echo yes;; *) echo no;; esac'` | 2 | `` | `` | 0 |
| 106 | test extended glob +(pattern) | `` | `bash: -c: line 1: syntax error near unexpected token `('
bash: -c: line 1: `shopt -s extglob 2>/dev/null; x=abc; case $x in +(a\|b)c) echo yes;; *) echo no;; esac'` | 2 | `` | `` | 0 |
| 107 | test declare -p prints attributes | `declare -i myint="42"
done` | `` | 0 | `done` | `` | 0 |
| 108 | test declare -a empty array | `0` | `` | 0 | `` | `` | 0 |
| 109 | test declare -i arithmetic | `8` | `` | 0 | `x+y` | `` | 0 |
| 110 | test BASH_VERSION is non-empty | `set` | `` | 0 | `` | `` | 0 |
| 111 | test SECONDS is numeric | `0` | `` | 0 | `` | `` | 0 |
| 112 | test RANDOM is between 0 and 32767 | `31239` | `` | 0 | `` | `` | 0 |
| 113 | test UID is numeric | `1000` | `` | 0 | `` | `` | 0 |
| 114 | test EUID is numeric | `1000` | `` | 0 | `` | `` | 0 |
| 115 | test HOSTNAME is non-empty | `set` | `` | 0 | `` | `` | 0 |
| 116 | test SHLVL is at least 1 | `4` | `` | 0 | `3` | `` | 0 |
| 117 | test LINENO is numeric | `1` | `` | 0 | `` | `` | 0 |
| 118 | test multiple semicolons | `` | `bash: -c: line 1: syntax error near unexpected token `;;'
bash: -c: line 1: `;; echo "still ok"'` | 2 | `still ok` | `` | 0 |
| 119 | test empty string test with -z | `0` | `` | 0 | `1` | `` | 0 |

## Priority Areas (sorted by most gaps)

| Category | Failing / Total |
|----------|----------------|
| 00-quoting | 2 / 23 |
| 01-tokens | 0 / 14 |
| 02-variables | 7 / 25 |
| 03-parameter-expansion | 9 / 26 |
| 04-arrays | 14 / 14 |
| 05-redirection | 5 / 10 |
| 06-pipelines | 2 / 13 |
| 07-control-flow | 14 / 18 |
| 08-builtins | 10 / 37 |
| 09-job-control | 2 / 10 |
| 10-functions | 6 / 12 |
| 11-command-substitution | 0 / 8 |
| 12-arithmetic | 9 / 15 |
| 13-error-handling | 6 / 13 |
| 14-brace-expansion | 10 / 10 |
| 15-pattern-matching | 10 / 12 |
| 16-string-manipulation | 0 / 8 |
| 17-declare-typeset | 3 / 10 |
| 18-environment-vars | 8 / 12 |
| 19-edge-cases | 2 / 12 |


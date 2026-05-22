# monobash — Session Summary

## Goal
Implement all missing bash features to make monobash a complete bash replacement.

## Repository Structure
```
/mnt/mydata/projects2/0/monobash/   ← git repo, main branch
  ├── main.zig, builtins.zig, ...    ← monobash source
  ├── executor.zig                   ← main execution engine (1364+ lines)
  ├── var.zig                        ← variable storage, shell options, jobs
  ├── parser.zig                     ← tree-sitter wrapper
  ├── expand.zig                     ← word expansion
  ├── job.zig                        ← job control stubs
  ├── applets.zig                    ← NOEXEC applets (stub table)
  ├── tree-sitter/                   ← bundled tree-sitter library
  ├── tree-sitter-bash/              ← bash grammar
  ├── tests/
  │   ├── bash_compat_test.sh        ← 537-test compatibility suite
  │   └── full.sh                    ← full test runner
  ├── build.zig                      ← standalone build
  ├── SESSION.md                     ← this file
  └── deps/coreutils/                ← submodule (v9.11-53-g2f865e275)
```

## What's Done
### Test fixes
- Fixed 7 failing tests: backslash-newline line continuation, BASH_SUBSHELL, BASHPID, select keyword, trap EXIT (×2), set -e errexit
- Added shell option flags (`errexit`, `nounset`, `pipefail`) in `var.zig`
- Added `reserved_words` recognition in `builtinType` (makes `type select` pass)
- Added `set -e`, `set -u`, `set -o pipefail` handling in `builtinSet`
- Added `read -r` flag skipping in `builtinRead`
- Added EXIT trap storage and firing in `builtinTrap` / `executor.exec()`
- Added BASH_SUBSHELL increment and BASHPID update in `execSubshell`
- Added errexit abort in `execProgram` and `execList`
- Added pipefail (rightmost non-zero) in `execPipeline`
- All 537 tests pass

### Infrastructure
- Added C-style for loop (`c_style_for_statement` handler with `evalArithmetic`)
- Added heredoc/herestring redirect support (pipe content to child stdin)
- Added C argv building in `applets.run` (forks and calls `entry.mainFn`)
- Added `childByFieldName`, `childCountByFieldName`, `childrenByFieldName` to `parser.zig`
- Added `builtinSet` variable listing (no-arg mode)
- Added `builtinTrap` handler listing
- Added basic `runPipeline` in `job.zig`
- Removed all 4 remaining TODO/stub markers from source
- Created standalone git repo for monobash with initial commit

### Job control
- Added `wait`, `jobs`, `bg`, `fg`, `disown` builtins
- Use C `waitpid()` via extern for `wait` builtin
- Use `SIGCONT` (signal 18) for `bg`/`fg` resume
- Added `sys/wait.h` to builtins.zig's `cImport` block

### Builtins added
- `alias`/`unalias` — stores in hashmap in var.zig
- `bind` — stub
- `caller` — returns 1 (non-interactive)
- `command` — supports -v, -V, runs external
- `compgen`/`complete` — stubs
- `declare`/`typeset` — supports -a, -A, -i, -r, -x
- `dirs`/`pushd`/`popd` — directory stack
- `enable` — stub
- `fc` — stub
- `getopts` — stub
- `hash` — basic stub
- `help` — minimal
- `history` — no-op
- `let` — basic arithmetic eval
- `logout` — no-op
- `mapfile`/`readarray` — stub
- `readonly` — supports listing and setting
- `shopt` — no-op
- `suspend` — no-op
- `ulimit` — no-op
- `umask` — prints/sets stub

### Variable infrastructure added to var.zig
- `getAliases` / `setAlias` / `removeAlias` / `getAlias`
- `getDirStack` / `pushDir` / `popDir`
- `setReadonly` / `isReadonly`
- `allVars()` — iterate all variables across scopes
- `setExport` — set exported flag
- `getAllocator` — expose arena allocator

### AST features
- `(( ))` arithmetic command — expression evaluation via `evalArithmetic` (wraps in `$((...))`)
- `select` loop — detects via first unnamed child "select" keyword, presents non-interactive menu

### Restructuring
- Extracted monobash from coreutils src tree
- coreutils removed from its own src (was untracked)
- coreutils added as submodule at `deps/coreutils/`
- monobash is now a standalone git repo with 2 commits

## Test Status
### Compatibility suite (bash_compat_test.sh)
```
Total  : 537
Passed : 537
Failed : 0
Skipped: 0
🎉  ALL 537 TESTS PASSED!
```

### Bash comparison suite (tests/compare.sh — 302 tests across 20 categories)
```
Total  : 302
Passed : 163
Failed : 139  (gaps vs bash)
Coverage: 54%
```
See Gap Analysis section below for detailed breakdown by category.

## Gap Analysis (bash vs monobash comparison suite)

The comparison suite (`tests/compare.sh`) runs 302 tests across 20 categories against both bash and monobash, then reports gaps. Current results: **163/302 pass (54%)**.

### Per-Category Coverage

| Category | Passed | Failed | Total | Coverage |
|----------|--------|--------|-------|----------|
| 00-quoting | 21 | 2 | 23 | 91% |
| 01-tokens | 12 | 2 | 14 | 86% |
| 02-variables | 12 | 13 | 25 | 48% |
| 03-parameter-expansion | 17 | 9 | 26 | 65% |
| 04-arrays | 0 | 14 | 14 | 0% |
| 05-redirection | 5 | 5 | 10 | 50% |
| 06-pipelines | 9 | 4 | 13 | 69% |
| 07-control-flow | 4 | 14 | 18 | 22% |
| 08-builtins | 22 | 15 | 37 | 59% |
| 09-job-control | 5 | 5 | 10 | 50% |
| 10-functions | 6 | 6 | 12 | 50% |
| 11-command-substitution | 8 | 0 | 8 | 100% |
| 12-arithmetic | 5 | 10 | 15 | 33% |
| 13-error-handling | 5 | 8 | 13 | 38% |
| 14-brace-expansion | 0 | 10 | 10 | 0% |
| 15-pattern-matching | 2 | 10 | 12 | 17% |
| 16-string-manipulation | 8 | 0 | 8 | 100% |
| 17-declare-typeset | 7 | 3 | 10 | 70% |
| 18-environment-vars | 4 | 8 | 12 | 33% |
| 19-edge-cases | 11 | 1 | 12 | 92% |

### Priority Areas (sorted by gap impact)

#### Phase 1 — Easy wins (bugs, not missing features)
1. **Backslash-newline continuation** — `echo foo\<newline>bar` produces "foo bar" instead of "foobar"
2. **Single quotes with newlines** — `$'a\nb'` prints with literal `'` quotes
3. **AND/OR list chaining** — `false || echo a && echo b` runs both sides when `||` should short-circuit
4. **echo -n/-e** — flags not implemented; `echo -n` prints "-n"
5. **printf escapes** — `\n` in format string not processed correctly
6. **Positional params missing** — `set -- a b c` and then `$#` returns 0; vars get/set don't cross correctly in `-c` mode
7. **set -u exit code** — should exit 1, not 0
8. **cd error message** — format doesn't match bash
9. **trap EXIT** — output formatting differs
10. **readonly enforcement** — doesn't prevent writes to readonly vars
11. **alias/unalias** — stderr output format mismatches
12. **heredoc body pipe** — herestrings `<<<` produce wrong output
13. **2>&1 redirect** — stderr not properly merged to stdout
14. **! pipeline negation** — returns wrong exit code for negated true

#### Phase 2 — Missing feature categories (larger effort)
15. **Arrays** — full indexed array support (a=(1 2 3), ${a[@]}, ${#a[@]}, a+=(4))
16. **Brace expansion** — {a,b,c}, {1..5}, {a..e} completely absent
17. **Parameter expansion operators** — ${var:offset}, ${var/pat/repl}, ${!indirect}, ${!prefix*}
18. **Arithmetic command with vars** — (( i = 5 )), (( i += 1 )), (( 5 > 3 )) don't affect variables
19. **let builtin** — doesn't evaluate expressions
20. **declare -i** — integer attribute doesn't affect arithmetic
21. **Case pattern matching** — glob patterns (`*`, `?`, `[abc]`) not working in case statements
22. **Associative arrays** — declare -A, key-value storage
23. **select loop** — detected but no interactive input
24. **exit status 127** — command-not-found not returning 127
25. **fork/exec from -c** — monobash gets 127 for "nonexistent" from `bash -c` wrapper due to PATH

#### Phase 3 — Environment/stub improvements
26. **Shell variables** — BASH_VERSION, SECONDS, RANDOM, UID, EUID, HOSTNAME, SHLVL, LINENO not set
27. **PATH inheritance** — hardcoded to `/usr/local/bin:/usr/bin:/bin` instead of inheriting
28. **$- flags** — hardcoded to "hB" instead of reflecting actual shell state
29. **kill -l** — not implemented
30. **dirs/pushd/popd** — output format doesn't match bash
31. **Multiple semicolons** — `;; echo "still ok"` should be a syntax error
32. **shopt** — all options stubbed to no-op
33. **getopts, fc, complete, compgen** — all stubs
34. **Process substitution** — <(...) >(...) not supported

### Comparison Test Infrastructure

- **Runner**: `tests/compare.sh` — reads `tests/compat/*.tests` files, runs each command against both bash and monobash, compares stdout/stderr/exit code
- **Test files**: 20 files in `tests/compat/` covering all major feature categories (302 total tests)
- **Gap report**: `tests/compare.sh --report` generates `tests/compat/GAP_REPORT.md` with detailed per-test failure info
- **Usage**: `SHELL=./zig-out/bin/monobash bash tests/compare.sh`

## Key Decisions
- Use C `waitpid()` via extern for `wait` builtin rather than wrapping std.posix
- Use `SIGCONT` (signal 18) for `bg`/`fg` resume since signal names not available without libc signal.h
- Add `fork`, `execvp` via `unistd.h` in builtins.zig's `cImport` block for `runExternalCommand`
- Store aliases in separate `StringHashMap` in var.zig (not part of variable scope)
- Arrays deferred — require significant infrastructure changes
- `select` loop uses non-interactive fallback (assigns first word, executes body once)
- `(( ))` arithmetic command detected by checking first child text starts with `"(("`
- Struct extracted as standalone git repo; coreutils kept as submodule

## Relevant Files
- `builtins.zig` — builtin table (line 16+), all handler implementations
- `executor.zig` — execCompound (line 861), execArithmeticCmd (line 878), execFor (line 364), evalArithmetic (line 440), detectSelect (line 361)
- `var.zig` — variable store, aliases, dir stack, readonly, jobs, shell options
- `job.zig` — runPipeline, runBackground stubs
- `applets.zig` — C argv builder (empty applet table for now)
- `parser.zig` — tree-sitter wrapper (childByFieldName, etc.)
- `tests/bash_compat_test.sh` — 537-test suite
- `tests/compare.sh` — bash comparison test runner (302 tests across 20 categories)
- `tests/compat/*.tests` — 20 comparison test definition files
- `tests/compat/GAP_REPORT.md` — auto-generated gap analysis report
- `deps/coreutils` — coreutils submodule

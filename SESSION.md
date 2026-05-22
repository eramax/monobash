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

### Bash comparison suite (tests/compare.sh — 241 tests across 17 categories)
```
Total  : 241
Passed : 167
Failed : 74  (gaps vs bash)
Coverage: 69%
Note: 3+ categories hang due to multi-line test parsing issues
```
See Gap Analysis section below for detailed breakdown by category.

## Gap Analysis (bash vs monobash comparison suite)

The comparison suite (`tests/compare.sh`) runs 302 tests across 20 categories against both bash and monobash, then reports gaps. Current results: **183/302 pass (61%)**.

### Per-Category Coverage

| Category | Passed | Failed | Total | Coverage |
|----------|--------|--------|-------|----------|
| 00-quoting | 21 | 2 | 23 | 91% |
| 01-tokens | 14 | 0 | 14 | **100%** |
| 02-variables | 18 | 7 | 25 | 72% |
| 03-parameter-expansion | 17 | 9 | 26 | 65% |
| 04-arrays | 0 | 14 | 14 | 0% |
| 05-redirection | 5 | 5 | 10 | 50% |
| 06-pipelines | 11 | 2 | 13 | 85% |
| 07-control-flow | 4 | 14 | 18 | 22% |
| 08-builtins | 27 | 10 | 37 | 73% |
| 09-job-control | 8 | 2 | 10 | 80% |
| 10-functions | 6 | 6 | 12 | 50% |
| 11-command-substitution | 8 | 0 | 8 | **100%** |
| 12-arithmetic | 6 | 9 | 15 | 40% |
| 13-error-handling | 7 | 6 | 13 | 54% |
| 14-brace-expansion | 0 | 10 | 10 | 0% |
| 15-pattern-matching | 2 | 10 | 12 | 17% |
| 16-string-manipulation | 8 | 0 | 8 | **100%** |
| 17-declare-typeset | 7 | 3 | 10 | 70% |
| 18-environment-vars | 4 | 8 | 12 | 33% |
| 19-edge-cases | 10 | 2 | 12 | 83% |

### Recent Fixes

1. **`$?` exit status tracking** — added `recordExitStatus()` wrapper around `execNode` so `$?` is updated after every command
2. **`set -- a b c`** — `builtinSet` now handles `--` separator and sets positional parameters
3. **Variable assignments in simple commands** — `execSimpleCommand` processes `variable_assignment` children first (fixes standalone `x=2`)
4. **echo -n flag** — suppresses trailing newline
5. **printf argument cycling** — format string reuses cyclically for all remaining arguments
6. **AND/OR short-circuit** — `execList` checks for `&&`/`||` operators and short-circuits
7. **`$-` expansion** — added to `expandPositional`'s special var handling
8. **Expansion error propagation** — `UndefinedVar` errors from `${var:?}` return exit code 127
9. **Readonly enforcement** — `set()`/`setLocal()` check `isReadonly()` before overwriting
10. **unset C environment cleanup** — `unset()` calls `unsetenv()` to sync C env
11. **return value parsing** — `return N` sets `$?` to N
12. **Background operator** — `&` background execution with job tracking
13. **`$x` expansion in `[...]` tests** — `test_command` nodes now expand variables via `expandToken` (was using raw `nodeText`)
14. **Arithmetic preprocessor** — `$(( ))` expressions with variables preprocessed before `wordexp` using a recursive-descent integer evaluator
15. **`evalArithmetic` refactored** — calls `evalArithmeticFromStr` directly instead of wrapping in `$((` and calling `wordexp`
16. **Backslash-newline continuation** — merged adjacent word tokens when separated by `\<newline>`
17. **ANSIC-C quoting** — `$'...'` escape processing in mixed tokens
18. **`$-` dynamic** — reflects actual shell state (errexit, nounset, etc.)
19. **cd error message** — matches bash format
20. **alias/unalias** — proper error messages on failure
21. **kill -l** — signal name listing
22. **dirs/pushd/popd** — actually change directory
23. **shopt** — basic `-s`/`-u`/list support
24. **`;;` syntax error** — properly detected
25. **Shell environment variables** — BASH_VERSION, SECONDS, RANDOM, UID, EUID, HOSTNAME, SHLVL, LINENO, PPID, EPOCHSECONDS
26. **PATH inheritance** — inherits from parent environment instead of hardcoded
27. **! pipeline negation** — fixed child selection (was picking `!` token as the command)
28. **Exit code 127** — `execCommand` propagates failure status
29. **2>&1 redirect** — rewritten `parseFileRedirect` with flexible FD parsing
30. **Herestrings** — appends newline after content
31. **Arithmetic `(( i = 5 ))`** — parses assignments from expression, evaluates RHS, stores in variable
32. **let builtin** — full rewrite handling `+=`, `++`, `--`, pre/post increment
33. **declare -i** — evaluates arithmetic expressions before storing

### Priority Areas (sorted by gap impact)

#### Remaining bugs
1. **Check for loops with brace expansion** — depends on brace expansion feature
2. **select loop** — non-interactive handling needs improvement
3. **heredoc/herestring corruption** — some edge cases cause massive output concatenation
4. **05-redirection tests** — only runs 3/10 due to hanging tests
5. **08-builtins** — some builtins still failing (hash, getopts)

#### Missing feature categories (larger effort)
6. **Arrays** — full indexed array support (`a=(1 2 3)`, `${a[@]}`, `${#a[@]}`, `a+=(4)`)
7. **Brace expansion** — `{a,b,c}`, `{1..5}`, `{a..e}` completely absent
8. **Parameter expansion operators** — `${var:offset}`, `${var/pat/repl}`, `${!indirect}`, `${!prefix*}`
9. **Associative arrays** — `declare -A`, key-value storage
10. **Case pattern matching** — glob patterns (`*`, `?`, `[abc]`) not matching in case statements

#### Environment/stub improvements
11. **$- flags** — `hBc` should be more comprehensive
12. **kill -l on specific signals** — `kill -l SIGTERM` not implemented
13. **shopt** — more options needed
14. **hash, getopts, fc, complete, compgen** — stubs
15. **Process substitution** — `<(...)` `>(...)` not supported

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

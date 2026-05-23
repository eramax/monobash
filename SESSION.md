# monobash — Session Summary

## Goal
Make monobash a complete bash replacement by:
1. Implement all missing shell features (arrays, brace expansion, etc.)
2. Pass busybox test suite at >80% for all registered NOEXEC applets
3. Port all 296 applets to NOEXEC Zig (230 registered, 66 remaining)

## Current Status
**Busybox test suite: 533/901 passing (59.2%)** — up from 182/887 (20.5%)

## Infrastructure Changes

### Busybox-style symlink dispatch (`main.zig`)
- When argv[0] isn't "monobash"/"bash"/"sh", look up the applet by name and dispatch
- Also handles `busybox <applet> [args...]` pattern (argv[0]="busybox", argv[1]=applet)
- Rebuilds argv properly for the applet (strips "busybox" prefix, uses basename for symlinks)
- Init io_uring and counters before dispatch

### Build system
- `Makefile` — targets: `release` / `debug` / `pod` (glibc 2.39 for Ubuntu 24.04) / `clean`
- `tests/Makefile` — targets: `shell` / `applet` / `compat` / `bash-compat` / `busybox-pod` / `pod-setup`

### Test infrastructure
- `ci/run-busybox-tests.sh` — runs busybox testsuite for 80+ supported applets in K8s pod
- Runner creates symlinks to monobash in `/tmp/monobash-links/` for each applet + busybox
- Builds OPTIONFLAGS with all feature flags to prevent test skipping
- Runs new-style `.tests` files and old-style per-applet test scripts
- Uses K8s pod (`monobash-tester`, ubuntu:24.04) for test isolation — never runs on host

### Pod deployment
- Binary built for `x86_64-linux-gnu.2.39` (Ubuntu 24.04 glibc)
- `kubectl cp` to copy binary, testsuite, and runner to pod
- Tests run via `kubectl exec`

## Applet Fixes (by batch)

Each batch was dispatched as a subagent, one at a time. All applets are NOEXEC (fork+exec), use `core.writeAll` for I/O.

### Batch 1: echo (11/11)
- Multi-flag args (`-e -n`, `-ne`)
- Validate all flag chars before applying side effects (`-neEZ` → literal)
- Octal/hex escapes, `\0`, `\c` suppress, `\n`/`\t`/`\r`

### Batch 2: basename (2/2), dirname (7/7), head (3/3)
- basename: skip suffix removal when result would be empty
- dirname: match musl behavior (empty→`.`, trailing slashes, `///`→`/`)
- head: support negative -n values (print all but last N lines)

### Batch 3: rev (4/4), sum (3/3), md5sum (1/1)
- rev: NUL truncation, missing-newline handling
- sum: BSD (-r) and SysV (-s) checksum flags
- md5sum: -c check mode
- **core.zig fix**: readAll loops on partial io_uring reads (pipe fix)

### Batch 4: unexpand (23/23), seq (25/25), uniq (14/14)
- unexpand: -f/--first-only, -tN tabstop parsing
- seq: -s separator, -w width, negative numbers, float precision
- uniq: -f skip-fields, -s skip-chars, -w compare-max, -u unique, two-file support

### Batch 5: cut (14/14 + old), comm (8/8), factor (13/13), cpio (9/9)
- cut: -b bytes, -s suppress, -D/-F regex, `-` as stdin
- comm: `-` as option terminator
- factor: Miller-Rabin + Pollard Rho prime factorization
- cpio: -H format, -p pass-through, -R owner, -v verbose

### Batch 6: grep (51/51), sort (21/26), printf (24/24), test (17/17)
- **grep**: -q, -F, -x, -w, -o, -E, -c, -r/-R, -m, -l/-L, -s, multiple -e, -f FILE, recursive traversal
- **sort**: -k key parsing, -t separator, -h/-M/-V comparators, -o, -z, -s, -u with keys
- **printf**: full implementation from scratch — all format specifiers, escapes, width/precision, flags
- **test**: rewrite expression parser with -a/-o precedence, grouping, string comparison

### Batch 7: diff (18/18), patch (11/11), cp (27/30), tar (~5/9)
- diff: full unified diff with LCS, -u/-b/-B/-q/-r/-N
- patch: complete application with -R/-N/-pN/-i
- cp: -a/-d/-P/-H/-L/-i/-v/-l/-s/--parents, symlink policy
- tar: basic create/extract/list, empty/zeroed block handling

### Batch 8: sed (37/59)
- Address expressions (numeric, regex, step, negation, $)
- Commands: d, p, P, q, a, i, c, =, N, n, {}, y///, w, r
- s/// with g/p/w/I/NUM flags
- Branching: :label, b, t, T
- CLI: -e, -f, -n, -r, --version

### Batch 9: awk (50/78)
- Complete awk interpreter from scratch (2792 lines)
- Recursive-descent parser, expression evaluator, field variables
- 28 built-in functions, arrays, functions, BEGIN/END blocks
- -F/-f/-e/-v flags, print/printf with redirects

### Batch 10: bc (3/66 — partial), dc (17/36)
- dc: arbitrary-precision decimal engine, stack ops, registers, macros, conditionals
- bc: improved stub with basic arithmetic (needs full parser rewrite)

### Batch 11: uuencode (19/19), xxd (7/7) — **new applets created**
- uuencode: standard and base64 encoding, created from scratch
- xxd: hex dump with -p plain, -r reverse, created from scratch
- Both registered in applets.zig

### Batch 12: xargs (10/11), nl (3/3), fold (3/3), readlink (6/6), realpath (10/10), touch (3/3), tree (4/4), cal (1/1), pidof (3/4), hexdump (1/6), od (~partial)
- Various small applet fixes and rewrites
- pidof registered in applets.zig (was missing)

## Remaining Work (~368 failures to reach 80%)

### Hard (need full parser/engine rewrites):
- **bc**: 57 failures — needs recursive-descent parser with control flow, functions, math library
- **awk**: 27 failures — edge cases (getline, backslash-newline, gensub backslashes)
- **sed**: 22 failures — edge cases (-i in-place, -e combined, \U/\L case conv)
- **dc**: 19 failures — edge cases (precision, string escapes)

### Moderate:
- **tar**: ~12 failures plus old-style — needs -z gzip, proper archive format
- **cp**: 3 failures — missing SKIP_KNOWN_BUGS guarded features
- **sort**: 5 failures — reverse-with-keys, -b blanks, -sr stable ordering
- **od**: ~8 failures — format alignment
- **hexdump**: 5 failures — -e format support
- **xargs**: 1 failure — quote support

### Small (~33 total):
- nl, fold, readlink, realpath, touch, tree, cal, pidof — mostly fixed

## Key Decisions
- Subagents dispatched one at a time (not parallel) per user request
- Each subagent reads source + test file, fixes, rebuilds, verifies
- Tests run in K8s pod, never on host machine
- Binary built for glibc 2.39 (Ubuntu 24.04 in pod)
- Applets are NOEXEC — fork+exec, each child re-inits io_uring
- `core.zig` modifications allowed only when necessary (readAll pipe fix)
- New applets registered in `applets.zig` with `const` import + `all_metas` entry
- Do NOT modify main.zig, build.zig except when adding symlink dispatch or build infra

## Relevant Files
- `main.zig` — symlink dispatch (busybox/compat mode)
- `applets.zig` — applet registry (230 registered)
- `applets/core.zig` — shared I/O (readAll, writeAll), io_uring, counters
- `applets/*.zig` — individual NOEXEC applets
- `ci/run-busybox-tests.sh` — busybox test runner for K8s pod
- `ci/test-pod.yaml` — K8s pod spec
- `Makefile` — build targets
- `tests/Makefile` — test targets
- `deps/busybox/testsuite/` — vendored busybox test suite

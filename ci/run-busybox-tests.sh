#!/bin/bash
# Run busybox testsuite tests for monobash-supported applets

MONOBASH="/usr/local/bin/monobash"
TSDIR="/mnt/testsuite"
LINKDIR="/tmp/monobash-links"

[ -f "$MONOBASH" ] || { echo "FATAL: monobash not found"; exit 1; }
[ -d "$TSDIR" ] || { echo "FATAL: testsuite not found"; exit 1; }

# Applets with busybox tests (excluding dangerous/system/blocked)
APPLETS="awk bc basename cal cat cmp comm cp cpio cryptpw cut date dc dd diff dirname du echo expand expr factor false find fold grep head hexdump hostid hostname id ln ls md5sum mkdir mv nl od paste patch pidof printf pwd readlink realpath rev rm rmdir sed seq sha1sum sha256sum sha3sum sha512sum sort start-stop-daemon strings sum tail tar taskset tee test time touch tr tree true tsort unexpand uniq uptime uuencode wc wget which xargs xxd"

echo "============================================"
echo " BusyBox Tests for monobash"
echo " Applets: $(echo $APPLETS | wc -w)"
echo "============================================"

# Create symlinks
rm -rf "$LINKDIR" && mkdir -p "$LINKDIR"
ln -sf "$MONOBASH" "$LINKDIR/busybox"
for a in $APPLETS; do ln -sf "$MONOBASH" "$LINKDIR/$a"; done

# Build OPTIONFLAGS with all features
OPTFLAGS=:
for f in DESKTOP LONG_OPTS ASH_ECHO BUNZIP2 EGREP EXTRA_COMPAT GUNZIP LS \
    SH_IS_ASH STATIC TAR UNICODE_SUPPORT USE_BB_CRYPT_SHA UUDECODE \
    FEATURE_AR_CREATE FEATURE_AWK_GNU_EXTENSIONS FEATURE_AWK_LIBM \
    FEATURE_CATN FEATURE_CATV FEATURE_CPIO_O FEATURE_CPIO_P \
    FEATURE_CUT_REGEX FEATURE_DC_BIG FEATURE_DIFF_DIR FEATURE_FANCY_HEAD \
    FEATURE_FIND_EXEC FEATURE_FIND_EXEC_OK FEATURE_FIND_EXEC_PLUS \
    FEATURE_FIND_MAXDEPTH FEATURE_FIND_NOT FEATURE_FIND_TYPE \
    FEATURE_LS_RECURSIVE FEATURE_LS_SORTFILES FEATURE_LS_TIMESTAMPS \
    FEATURE_LS_USERNAME FEATURE_MAKEDEVS_TABLE FEATURE_MD5_SHA1_SUM_CHECK \
    FEATURE_MDEV_CONF FEATURE_MDEV_EXEC FEATURE_MDEV_RENAME \
    FEATURE_MDEV_RENAME_REGEXP FEATURE_PIDOF_OMIT FEATURE_PIDOF_SINGLE \
    FEATURE_READLINK_FOLLOW FEATURE_SEAMLESS_BZ2 FEATURE_SEAMLESS_GZ \
    FEATURE_SEAMLESS_XZ FEATURE_SORT_BIG FEATURE_STAT_FORMAT \
    FEATURE_TAR_AUTODETECT FEATURE_TAR_CREATE FEATURE_TAR_GNU_EXTENSIONS \
    FEATURE_TAR_LONG_OPTIONS FEATURE_TR_CLASSES FEATURE_UNZIP_CDF \
    FEATURE_UNZIP_LZMA FEATURE_VERBOSE_USAGE FEATURE_XARGS_SUPPORT_QUOTES \
    FEATURE_XARGS_SUPPORT_REPL_STR FEATURE_CP_LONG_OPTIONS \
    FEATURE_DD_IBS_OBS FEATURE_DU_DEFAULT_BLOCKSIZE_1K FEATURE_FANCY_ECHO \
    FEATURE_FIND_XDEV FEATURE_GZIP_LEVELS FEATURE_HUMAN_READABLE \
    FEATURE_PRESERVE_HARDLINKS FEATURE_TAR_FROM FEATURE_TAR_UNAME_GNAME \
    FEATURE_TIMEZONE FEATURE_XARGS_SUPPORT_ZERO_TERM INCLUDE_SUSv2 \
    CONFIG_UNICODE_SUPPORT FEATURE_DD_SIGNAL_HANDLE FEATURE_GREP_CONTEXT \
    FEATURE_GREP_EGREP_ALIAS FEATURE_GREP_FGREP_ALIAS \
    FEATURE_SED_EMBEDED_NEWLINE FEATURE_TAIL_SEEK; do
    OPTFLAGS="$OPTFLAGS$f:"
done
export OPTIONFLAGS="$OPTFLAGS"
export VERBOSE=1

ALL_PASS=0
ALL_FAIL=0

run_test_file() {
    local applet="$1"
    [ -f "$TSDIR/$applet.tests" ] || return 0
    echo "--- [$applet] ---"
    local outfile=$(mktemp)
    (
        export PATH="$LINKDIR:$TSDIR:/usr/bin:/bin"
        export OPTIONFLAGS="$OPTIONFLAGS"
        cd "$TSDIR"
        /bin/bash "$applet.tests"
    ) > "$outfile" 2>&1
    cat "$outfile"
    local pass=$(grep -c "^PASS:" "$outfile" 2>/dev/null || true)
    local fail=$(grep -c "^FAIL:" "$outfile" 2>/dev/null || true)
    echo "  PASS=$pass FAIL=$fail"
    ALL_PASS=$((ALL_PASS + pass))
    ALL_FAIL=$((ALL_FAIL + fail))
    rm -f "$outfile"
}

run_old_style() {
    local applet="$1"
    [ -d "$TSDIR/$applet" ] || return 0
    echo "--- [$applet] ---"
    local count=0
    for testcase in "$TSDIR/$applet"/*; do
        case "${testcase##*/}" in .*|*~|"CVS"|\#*|*.mine|*.r[0-9]*) continue ;; esac
        [ -f "$testcase" ] || continue
        local testname="${testcase##*/}"
        local tmpdir="$TSDIR/.tmpdir.$applet"
        rm -rf "$tmpdir" 2>/dev/null
        mkdir -p "$tmpdir"
        (
            cd "$tmpdir"
            export d="$TSDIR"
            export PATH="$LINKDIR:$TSDIR:/usr/bin:/bin"
            /bin/bash -e "$testcase" > "$testname.stdout.txt" 2>&1
        )
        local status=$?
        rm -rf "$tmpdir" 2>/dev/null
        if [ $status -ne 0 ]; then
            echo "FAIL: $testname"
            ALL_FAIL=$((ALL_FAIL + 1))
        else
            echo "PASS: $testname"
            ALL_PASS=$((ALL_PASS + 1))
        fi
        count=$((count + 1))
    done
    echo "  $count tests"
}

for applet in $APPLETS; do
    run_test_file "$applet"
    run_old_style "$applet"
done

echo ""
echo "============================================"
echo " RESULTS"
echo "============================================"
echo " PASS:  $ALL_PASS"
echo " FAIL:  $ALL_FAIL"
echo " TOTAL: $((ALL_PASS + ALL_FAIL))"
echo "============================================"
exit $ALL_FAIL

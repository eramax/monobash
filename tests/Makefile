SHELL := /bin/bash
MONOBASH := ../zig-out/bin/monobash
TEST_POD := monobash-tester

.PHONY: all shell applet compat bash-compat busybox-pod pod-setup

all: shell applet compat

# monobash shell tests (basic shell features)
shell:
	@bash run_monobash_tests.sh "$(MONOBASH)"

# Applet comparison tests (monobash applet vs system binary)
applet:
	@bash applet-test.sh

applet-%:
	@bash applet-test.sh "$*"

# Bash compat tests (monobash vs real bash behavior)
compat:
	@bash compare.sh

compat-report:
	@bash compare.sh --report

compat-%:
	@bash compare.sh "$*"

# bash_compat_test.sh (537-test bash 5.x suite)
bash-compat:
	SHELL="$(MONOBASH)" bash bash_compat_test.sh

# full.sh (comprehensive bash compat)
full:
	SHELL="$(MONOBASH)" bash full.sh

# Busybox testsuite (runs in K8s pod)
busybox-pod:
	@kubectl exec "$(TEST_POD)" -- bash /tmp/run-busybox-tests.sh

# Copy test files to pod
pod-setup:
	@kubectl cp "$(MONOBASH)" "$(TEST_POD):/usr/local/bin/monobash"
	@kubectl cp ../deps/busybox/testsuite "$(TEST_POD):/mnt/testsuite"
	@kubectl cp ../ci/run-busybox-tests.sh "$(TEST_POD):/tmp/run-busybox-tests.sh"

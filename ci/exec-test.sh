#!/bin/bash
# Run a test inside the monobash-tester pod
# Usage: ci/exec-test.sh [category]
#   category: test category name (e.g., "00-quoting") or "all"

CATEGORY="${1:-all}"
POD="${POD:-monobash-tester}"
SHELL="${SHELL:-/mnt/monobash/zig-out/bin/monobash}"

if [ "$CATEGORY" = "all" ]; then
  kubectl exec "$POD" -- /bin/bash -c "cd /mnt/tests && SHELL=$SHELL bash compare.sh 2>&1"
else
  kubectl exec "$POD" -- /bin/bash -c "cd /mnt/tests && SHELL=$SHELL bash compare.sh $CATEGORY 2>&1"
fi

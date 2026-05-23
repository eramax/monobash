#!/bin/bash
# Run monobash comparison tests in parallel K8s pods
# Each category gets its own pod for isolation

BIN_PATH="$(cd "$(dirname "$0")/.." && pwd)/zig-out/bin/monobash"
TESTS_PATH="$(cd "$(dirname "$0")/.." && pwd)/tests"
NAMESPACE="${NAMESPACE:-default}"
PARALLEL="${PARALLEL:-4}"

CATEGORIES=(
  00-quoting 01-tokens 02-variables 03-parameter-expansion
  05-redirection 06-pipelines 07-control-flow 08-builtins
  09-job-control 10-functions 11-command-substitution 12-arithmetic
  13-error-handling 14-brace-expansion 15-pattern-matching
  16-string-manipulation 17-declare-typeset 18-environment-vars 19-edge-cases
)

echo "=== Monobash K8s Test Runner ==="
echo "Binary: $BIN_PATH"
echo "Tests:  $TESTS_PATH"
echo "Pods:   ${#CATEGORIES[@]} total, $PARALLEL at a time"
echo ""

if [ ! -f "$BIN_PATH" ]; then
  echo "ERROR: monobash binary not found at $BIN_PATH"
  echo "Build it first: zig build -Doptimize=ReleaseSmall"
  exit 1
fi

# Resolve host paths (no symlinks for hostPath)
BIN_HOST=$(readlink -f "$BIN_PATH" 2>/dev/null || echo "$BIN_PATH")
TESTS_HOST=$(readlink -f "$TESTS_PATH" 2>/dev/null || echo "$TESTS_PATH")

# Create temp job file
TMPFILE=$(mktemp)

launch_pod() {
  local cat="$1"
  local name="monobash-test-${cat}"
  
  # Check if already exists
  kubectl -n "$NAMESPACE" get job "$name" &>/dev/null && return 0
  
  sed -e "s/{CATEGORY}/$cat/g" \
      -e "s|{BIN_PATH}|$BIN_HOST|g" \
      -e "s|{TESTS_PATH}|$TESTS_HOST|g" \
      "$(dirname "$0")/test-job.yaml" > "$TMPFILE"
  
  echo "  Launching: $name"
  kubectl -n "$NAMESPACE" apply -f "$TMPFILE" &>/dev/null
}

collect_results() {
  local cat="$1"
  local name="monobash-test-${cat}"
  local pod=$(kubectl -n "$NAMESPACE" get pods --selector=job-name="$name" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  
  if [ -n "$pod" ]; then
    local status=$(kubectl -n "$NAMESPACE" get pod "$pod" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$status" = "Succeeded" ] || [ "$status" = "Failed" ]; then
      echo "=== $cat ==="
      kubectl -n "$NAMESPACE" logs "$pod" 2>/dev/null | grep -E "✓|✗|Total|Passed|Failed"
      echo ""
      return 0
    fi
  fi
  return 1
}

echo "Launching test pods ($PARALLEL at a time)..."
launched=0
for cat in "${CATEGORIES[@]}"; do
  launch_pod "$cat" &
  launched=$((launched + 1))
  
  # Throttle
  if [ $((launched % PARALLEL)) -eq 0 ]; then
    wait
    sleep 1
  fi
done
wait

echo ""
echo "Waiting for results (polling every 10s)..."
echo ""

# Poll for results
all_done=false
while ! $all_done; do
  all_done=true
  for cat in "${CATEGORIES[@]}"; do
    if ! collect_results "$cat"; then
      all_done=false
    fi
  done
  
  if ! $all_done; then
    sleep 10
  fi
done

echo "=== ALL DONE ==="
rm -f "$TMPFILE"

# Print summary
echo ""
echo "=== SUMMARY ==="
for cat in "${CATEGORIES[@]}"; do
  collect_results "$cat"
done

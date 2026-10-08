#!/usr/bin/env bash
# EasyWork test runner — run each *.bats file in parallel, print per-file
# output in file order, and aggregate the exit status.
#
# Usage: tests/run.sh [jobs]
#   jobs defaults to $JOBS or 4.
#
# Why parallel: bats re-sources each test file per test, so a single file is
# inherently serial; running files concurrently cuts wall-clock time.
# Files are independent because each test uses a unique $TEST_HOME.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Isolate tests from any EASYWORK_* env leaking from the developer's shell
# (e.g. EASYWORK_HOME exported during manual testing).
unset EASYWORK_HOME EASYWORK_RAW_URL EASYWORK_RELEASE_URL EASYWORK_API_URL EASYWORK_WEB_URL EASYWORK_CHANNEL

jobs="${1:-${JOBS:-}}"
if [[ -z "$jobs" ]]; then
    # Default to the CPU count (throttled by the number of test files)
    jobs="$(sysctl -n hw.ncpu 2> /dev/null || nproc 2> /dev/null || echo 4)"
fi
bats_bin="${BATS:-bats}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Run one bats process per file, throttled to $jobs concurrent processes.
i=0
while IFS= read -r f; do
    i=$((i + 1))
    (
        "$bats_bin" "$f" > "$tmp/$i.out" 2>&1
        echo $? > "$tmp/$i.rc"
    ) &
    while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$jobs" ]]; do
        sleep 0.1
    done
done < <(ls tests/*.bats)

wait

# Print output in file order and aggregate status.
rc=0
i=0
while IFS= read -r _f; do
    i=$((i + 1))
    cat "$tmp/$i.out"
    [[ "$(cat "$tmp/$i.rc" 2> /dev/null)" == "0" ]] || rc=1
done < <(ls tests/*.bats)

exit "$rc"

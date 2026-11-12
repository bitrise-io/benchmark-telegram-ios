#!/usr/bin/env bash
# Clean Bazel simulator build, no cache (port of Bitrise _telegram_benchmark).
set -eo pipefail
source "$(dirname "$0")/lib.sh"
cd "$GITHUB_WORKSPACE"
LOGS="$BENCH_OUT/logs"; mkdir -p "$LOGS"
case "$TG_CONFIGURATION" in release_*) TG_METRIC=clean_build_release ;; *) TG_METRIC=clean_build_debug ;; esac

timed_build() { # $1 = log
  local start end bz
  start=$(now)
  python3 build-system/Make/Make.py --bazel="$TG_BAZEL" --overrideXcodeVersion build \
    --configurationPath=build-system/appstore-configuration.json \
    --codesigningInformationPath=build-system/fake-codesigning \
    --buildNumber=100001 --configuration="$TG_CONFIGURATION" > "$1" 2>&1 || { tail -n 80 "$1" >&2; return 1; }
  end=$(now); bz=$(sed -n 's/^INFO: Elapsed time: \([0-9.]*\)s.*$/\1/p' "$1" | tail -1)
  if [ -n "$bz" ]; then echo "$bz"; else python3 -c "print(round($end-$start,3))"; fi
}

echo "project,metric_key,machine_key,run,duration_sec" > "$BENCH_OUT/results.csv"
: > "$BENCH_OUT/clean.txt"
for i in $(seq 1 $(( WARMUP_RUNS + BENCHMARK_RUNS ))); do
  run_label "$i"
  "$TG_BAZEL" clean >/dev/null 2>&1 || true   # keep fetched externals, drop outputs
  echo "=== $LABEL: clean ${TG_CONFIGURATION} build ==="
  CLEAN=$(timed_build "$LOGS/$LABEL-clean.log"); echo "clean: ${CLEAN}s"
  echo "${BENCHMARK_PROJECT},${TG_METRIC},${MACHINE_KEY},${LABEL},${CLEAN}" >> "$BENCH_OUT/results.csv"
  if [ "$MEASURED" = 1 ]; then echo "$CLEAN" >> "$BENCH_OUT/clean.txt"; fi
done
"$TG_BAZEL" clean >/dev/null 2>&1 || true

cat > "$BENCH_OUT/summary.json" <<JSON
{
$(summary_common),
  "bazel": "$("$TG_BAZEL" --version | awk '{print $2}')",
  "benchmark_revision": "$(git rev-parse HEAD)",
  "configuration": "${TG_CONFIGURATION}",
  "${TG_METRIC}": $(stats "$BENCH_OUT/clean.txt")
}
JSON
rm -f "${BENCH_OUT:?}/clean.txt"
finish

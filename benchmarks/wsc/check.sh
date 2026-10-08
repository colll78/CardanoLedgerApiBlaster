#!/usr/bin/env bash
# Run the original WSC containment goal against a selected solver revision.
set -euo pipefail
ulimit -c 0

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd -- "$script_dir"
mode="${1:-plain}"
blaster_dir=".lake/packages/Blaster"
if (( $# > 0 )); then shift; fi
case "$mode" in
  plain) proof=WscContainment/Plain.lean ;;
  auto) proof=WscContainment/Auto.lean ;;
  *) echo "usage: $0 [plain|auto] [-KblasterRev=REF ...]" >&2; exit 2 ;;
esac
for argument in "$@"; do
  [[ "$argument" == -K* ]] || { echo "Expected a Lake -K configuration argument: $argument" >&2; exit 2; }
  if [[ "$argument" == -KblasterPath=* ]]; then
    blaster_dir="${argument#-KblasterPath=}"
  fi
done
budget="${WSC_TIMEOUT_SECONDS:-1800}"
[[ "$budget" =~ ^[1-9][0-9]*$ ]] || { echo "WSC_TIMEOUT_SECONDS must be a positive integer" >&2; exit 2; }
fin_compat="${WSC_FIN_COMPAT:-0}"
[[ "$fin_compat" == 0 || "$fin_compat" == 1 ]] || { echo "WSC_FIN_COMPAT must be 0 or 1" >&2; exit 2; }
[[ "$fin_compat" == 0 || "$mode" == plain ]] || { echo "Fin compatibility comparisons use plain mode" >&2; exit 2; }

# The scope includes Lean and its solver children. On hosts without systemd,
# use an equivalent container memory limit for comparisons (see README).
if [[ "${WSC_SCOPED:-0}" != 1 ]] && command -v systemd-run >/dev/null &&
    systemctl --user show-environment >/dev/null 2>&1; then
  exec systemd-run --user --scope --quiet --unit="wsc-tractability-$$" \
    -p MemoryMax=8G -p MemoryHigh=7G env WSC_SCOPED=1 \
    bash "$script_dir/check.sh" "$mode" "$@"
fi

mkdir -p .lake
run_dir="$(mktemp -d "$script_dir/.lake/tractability.$mode.XXXXXX")"
echo "Results: $run_dir"
trap 'rm -f -- "$run_dir/libBlaster.so"' EXIT
{
  echo "mode=$mode"
  echo "wall_budget_seconds=$budget"
  echo "fin_compat=$fin_compat"
  echo "benchmark_commit=$(git -C ../.. rev-parse HEAD)"
  lean --version
  z3 --version
} > "$run_dir/environment.txt"
lake_command=(lake "$@")
deadline=$((SECONDS + budget))

run_stage() {
  local stage=$1
  shift
  local remaining=$((deadline - SECONDS))
  local result
  if (( remaining <= 0 )); then
    echo "TIMEOUT before $stage" | tee "$run_dir/result.txt"
    exit 124
  fi
  echo "Running $stage"
  if /usr/bin/time -v -o "$run_dir/$stage.time" \
      timeout --signal=TERM --kill-after=5s "${remaining}s" "$@" \
      > "$run_dir/$stage.log" 2>&1; then
    return
  else
    result=$?
  fi
  if [[ "$result" == 124 ]]; then
    echo "TIMEOUT during $stage" | tee "$run_dir/result.txt"
  else
    echo "FAILED during $stage (exit $result)" | tee "$run_dir/result.txt"
  fi
  tail -n 20 "$run_dir/$stage.log" >&2
  exit "$result"
}

# Refresh branch refs explicitly and record the commits actually tested.
# `meta if get_config?` is evaluated when Lake compiles the configuration.
# Reconfigure explicitly so cached configuration cannot ignore new -K choices.
run_stage update "${lake_command[@]}" -R update
cp lake-manifest.json "$run_dir/lake-manifest.json"
lean_path="$("${lake_command[@]}" env printenv LEAN_PATH)"
printf '%s\n' "$lean_path" > "$run_dir/lean-path.txt"
expected_blaster="$(cd -- "$blaster_dir" && pwd)/.lake/build/lib/lean"
case ":$lean_path:" in
  *":$expected_blaster:"*) ;;
  *) echo "FAILED: selected solver is absent from LEAN_PATH" | tee "$run_dir/result.txt"; exit 1 ;;
esac
if [[ "$fin_compat" == 1 ]]; then
  cp compat/fin-sort.patch "$run_dir/fin-sort.patch"
  sha256sum compat/fin-sort.patch > "$run_dir/fin-sort.sha256"
  run_stage compatibility bash compat/apply-fin.sh "$blaster_dir"
fi
git -C "$blaster_dir" rev-parse HEAD > "$run_dir/blaster-commit.txt"
git -C "$blaster_dir" diff --stat > "$run_dir/blaster-dirty.txt"
git -C "$blaster_dir" diff --binary HEAD > "$run_dir/blaster.diff"
run_stage build "${lake_command[@]}" build Blaster:shared WscContainment
# A concurrent build must not replace a loaded shared library.
cp "$blaster_dir/.lake/build/lib/libBlaster.so" "$run_dir/libBlaster.so"
if [[ "$fin_compat" == 1 ]]; then
  run_stage fin-smoke "${lake_command[@]}" env lean --plugin="$run_dir/libBlaster.so" \
    -j2 -s65536 -M5000 compat/FinSmoke.lean
fi
run_stage proof "${lake_command[@]}" env lean --plugin="$run_dir/libBlaster.so" \
  -j2 -s65536 -M5000 "$proof"
if grep -q 'sorryAx' "$run_dir/proof.log"; then
  echo "FAILED: theorem depends on sorryAx" | tee "$run_dir/result.txt"
  exit 1
fi
echo "PASS: both containment theorems compiled without sorryAx" | tee "$run_dir/result.txt"
cat "$run_dir/proof.log"

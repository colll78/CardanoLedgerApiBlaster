#!/usr/bin/env bash
# Apply the small finite-type translation bridge to an isolated solver checkout.
set -euo pipefail
[[ $# == 1 ]] || { echo "usage: $0 /path/to/Lean-blaster" >&2; exit 2; }
patch_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
patch_file="$patch_dir/fin-sort.patch"
solver_dir="$1"
git -C "$solver_dir" rev-parse --show-toplevel >/dev/null
if git -C "$solver_dir" apply --check "$patch_file" 2>/dev/null; then
  git -C "$solver_dir" apply "$patch_file"
  echo "Applied Fin sort compatibility patch"
elif git -C "$solver_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
  echo "Fin sort compatibility patch already applied"
else
  echo "Fin sort patch does not apply cleanly; no changes made" >&2
  git -C "$solver_dir" apply --check "$patch_file"
  exit 1
fi

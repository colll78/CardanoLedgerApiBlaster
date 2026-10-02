#!/usr/bin/env bash
# Run on GitHub's ubuntu-24.04 runner. The repository owns the Lean version.
set -euo pipefail
: "${GITHUB_PATH:?This setup script runs inside GitHub Actions}"
: "${RUNNER_TEMP:?Missing runner temporary directory}"
toolchain=${LEAN_TOOLCHAIN:-$(tr -d '[:space:]' < lean-toolchain)}
if [[ ! "$toolchain" =~ ^[A-Za-z0-9:/._-]+$ ]]; then
  echo "Invalid Lean toolchain" >&2
  exit 2
fi
# Pin the installer source rather than following elan/master.
curl --fail --silent --show-error --location \
  https://raw.githubusercontent.com/leanprover/elan/0e36a07b9bbcc5381fa6250df109f9a4f94d7bac/elan-init.sh \
  -o "$RUNNER_TEMP/elan-init.sh"
sh "$RUNNER_TEMP/elan-init.sh" -y --default-toolchain "$toolchain"
export PATH="$HOME/.elan/bin:$PATH"
echo "$HOME/.elan/bin" >> "$GITHUB_PATH"
if [[ -n "${LEAN_TOOLCHAIN:-}" ]]; then
  printf '%s\n' "$toolchain" > lean-toolchain
fi
elan toolchain install "$toolchain"

z3_archive=z3-4.15.2-x64-glibc-2.39.zip
curl --fail --silent --show-error --location \
  "https://github.com/Z3Prover/z3/releases/download/z3-4.15.2/$z3_archive" \
  -o "$RUNNER_TEMP/$z3_archive"
printf '%s  %s\n' \
  85d2da1bf440fca3288874c2a06e23f96d09befcc21b5a7489fe0fa40444e685 \
  "$RUNNER_TEMP/$z3_archive" | sha256sum --check
unzip -q -o "$RUNNER_TEMP/$z3_archive" -d "$RUNNER_TEMP"
z3_bin="$RUNNER_TEMP/z3-4.15.2-x64-glibc-2.39/bin"
export PATH="$z3_bin:$PATH"
echo "$z3_bin" >> "$GITHUB_PATH"
lean --version
lake --version
z3 --version

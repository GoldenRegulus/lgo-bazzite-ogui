#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf '%s\n' "Usage: $0 LINUX_SOURCE" >&2
  exit 2
fi

linux=$(realpath "$1")
script_dir=$(dirname "$(realpath "$0")")
root=$(realpath "$script_dir/..")

"$script_dir/verify-base.sh" "$linux"

bash -n "$script_dir"/*.sh "$root/tests/standalone-kunit"/*.sh
if find "$root" -type f -name '*.patch' -print -quit | grep -q .; then
  printf '%s\n' 'Patch files are not permitted' >&2
  exit 1
fi

"$linux/scripts/checkpatch.pl" --no-tree --strict --file \
  "$root/tests/standalone-kunit/lenovo-wmi-fan-kunit.c"

printf '%s\n' 'source-check=pass'

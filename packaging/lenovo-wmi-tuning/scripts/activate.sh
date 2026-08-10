#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

# shellcheck source=lib.sh
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning activate: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"

if systemctl is-active --quiet "$TUNING_UNIT"; then
  printf '%s\n' "wmi-tuning activate: project module is already active"
  exit 0
fi

systemctl start "$TUNING_UNIT" || fail "service start failed"
printf '%s\n' "wmi-tuning activate: project module is active"

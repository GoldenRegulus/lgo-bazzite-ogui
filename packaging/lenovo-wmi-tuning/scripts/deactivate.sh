#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

# shellcheck source=lib.sh
script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning deactivate: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"

if systemctl is-active --quiet "$TUNING_UNIT"; then
  systemctl stop "$TUNING_UNIT" || fail "service stop failed; recovery state was kept"
else
  /usr/local/lib/legion-go-ogui/wmi-tuning/current/unload.sh || \
    fail "driver stop failed; recovery state was kept"
fi

printf '%s\n' "wmi-tuning deactivate: stock module is active"

#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
# shellcheck disable=SC1091
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning lifecycle validate: $*" >&2
  exit 1
}

errors=0
check() {
  local desc=$1

  shift
  if "$@"; then
    printf '%s\n' "PASS: $desc"
  else
    printf '%s\n' "FAIL: $desc" >&2
    errors=$((errors + 1))
  fi
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"

printf '%s\n' "=== wmi-tuning lifecycle validation ==="

check "DMI vendor is LENOVO" \
  test "$(cat /sys/class/dmi/id/sys_vendor)" == LENOVO
check "DMI product is 83E1" \
  test "$(cat /sys/class/dmi/id/product_name)" == 83E1
check "DMI version is Legion Go 8APU1" \
  test "$(cat /sys/class/dmi/id/product_version)" == "Legion Go 8APU1"

kver=$(uname -r)
printf '%s\n' "Kernel: $kver"

# Release checks.
release_dir=$script_dir
if [[ -r $release_dir/kernel-release ]]; then
  check "release kernel matches running kernel" \
    test "$(cat "$release_dir/kernel-release")" == "$kver"
fi
if [[ -r $release_dir/vermagic ]]; then
  check "release vermagic recorded" \
    test -n "$(cat "$release_dir/vermagic")"
fi

# Module checks.
module_path=$script_dir/modules/$kver/lenovo-wmi-tuning.ko
if [[ -r $module_path ]]; then
  check "module exists for running kernel" test -f "$module_path"
  check "module name is $TUNING_MODULE_NAME" \
    test "$(modinfo -F name "$module_path")" == "$TUNING_MODULE_NAME"
  check "module vermagic matches current kernel" \
    tuning_vermagic_matches "$module_path"

  if [[ -r $release_dir/project.sha256 ]]; then
    check "module hash matches release" \
      test "$(sha256sum "$module_path" | awk '{print $1}')" == \
           "$(cat "$release_dir/project.sha256")"
  fi
fi

# State checks.
if [[ -f $TUNING_STATE_DIR/active ]]; then
  if tuning_module_loaded "$TUNING_MODULE_NAME"; then
    printf '%s\n' "INFO: project module is active"
    check "project note matches loaded module" \
      tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
        "$TUNING_STATE_DIR/project.note"
    check "project interfaces are complete" tuning_verify_project_interfaces
  else
    fail "active marker exists but project module is not loaded"
  fi
elif tuning_module_loaded "$TUNING_MODULE_NAME"; then
  fail "project module is loaded without active state"
elif tuning_stock_module_loaded; then
  printf '%s\n' "INFO: stock module is active"
  check "stock interfaces are restored" tuning_verify_stock_interfaces
else
  fail "neither stock nor project module is loaded"
fi

# Recovery marker check.
if [[ -f $TUNING_STATE_DIR/recovery-incomplete ]]; then
  printf '%s\n' "WARNING: recovery marker exists; manual repair is required" >&2
  errors=$((errors + 1))
fi

if [[ $errors -eq 0 ]]; then
  printf '%s\n' "=== All lifecycle checks passed ==="
else
  printf '%s\n' "=== $errors lifecycle check(s) failed ===" >&2
  exit 1
fi

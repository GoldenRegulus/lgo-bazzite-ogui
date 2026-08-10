#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
# shellcheck disable=SC1091
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning load: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"

release_dir=$script_dir
validator=$script_dir/validate-host.sh
module_path=$release_dir/modules/$(uname -r)/lenovo-wmi-tuning.ko
[[ -x $validator ]] || fail "installed validator is missing"
[[ -r $module_path ]] || fail "no module exists for running kernel $(uname -r)"
module=$(readlink -f -- "$module_path")
"$validator"

# Verify vermagic.
tuning_vermagic_matches "$module" || fail "module vermagic does not match running kernel"

# Verify release hashes.
tuning_release_hashes_match "$release_dir" "$module" || \
  fail "release hashes do not match the installed module"
tuning_file_note_matches "$module" "$release_dir/project.note" || \
  fail "release build ID does not match the installed module"

install -d -m 0700 "$TUNING_STATE_DIR"
exec 9> "$TUNING_STATE_DIR/lock"
flock -x 9

[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "a prior recovery is incomplete; keep the saved state for repair"

if [[ -f $TUNING_STATE_DIR/active ]]; then
  tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
    "$TUNING_STATE_DIR/project.note" || \
    fail "active state does not match the loaded module"
  tuning_verify_project_interfaces || fail "project interfaces are incomplete"
  printf '%s\n' "wmi-tuning load: project module is already active"
  exit 0
fi

if tuning_module_loaded "$TUNING_MODULE_NAME"; then
  fail "project module is loaded but no active state exists"
fi

find "$TUNING_STATE_DIR" -mindepth 1 -maxdepth 1 ! -name lock -delete

# Require the exact stock module recorded by this release.
tuning_stock_module_loaded || fail "stock module $TUNING_STOCK_MODULE is not loaded"
tuning_release_stock_matches "$release_dir" || \
  fail "loaded stock module does not match this release"
tuning_verify_stock_interfaces || fail "stock WMI interfaces are incomplete"

# Verify no unsafe dependents.
dependents=$(tuning_dependent_count "$TUNING_STOCK_MODULE") || \
  fail "cannot read module dependents"
if [[ $dependents -ne 0 ]]; then
  fail "stock module has $dependents dependent(s); refuse to unload"
fi

# Record stock state.
stock=$(modinfo -n "$TUNING_STOCK_MODULE") || fail "cannot find the stock module"
[[ -r $stock ]] || fail "stock module is not readable"
case $stock in
  *.xz) stock_copy=$TUNING_STATE_DIR/stock-module.ko.xz ;;
  *.zst) stock_copy=$TUNING_STATE_DIR/stock-module.ko.zst ;;
  *.gz) stock_copy=$TUNING_STATE_DIR/stock-module.ko.gz ;;
  *) stock_copy=$TUNING_STATE_DIR/stock-module.ko ;;
esac
cp --reflink=auto -- "$stock" "$stock_copy"
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  chcon -t modules_object_t "$stock_copy" 2>/dev/null || true
fi
printf '%s\n' "$stock" > "$TUNING_STATE_DIR/stock.path"
printf '%s\n' "$stock_copy" > "$TUNING_STATE_DIR/stock-copy.path"
sha256sum "$stock_copy" | awk '{print $1}' > "$TUNING_STATE_DIR/stock.sha256"
sha256sum "$module" | awk '{print $1}' > "$TUNING_STATE_DIR/project.sha256"
printf '%s\n' "$module" > "$TUNING_STATE_DIR/project.path"
tuning_extract_build_id_note "$stock_copy" "$TUNING_STATE_DIR/stock.note" || \
  fail "cannot read the stock module build ID"
tuning_extract_build_id_note "$module" "$TUNING_STATE_DIR/project.note" || \
  fail "cannot read the project module build ID"

# Record pre-removal WMI ownership.
tuning_guid_owners > "$TUNING_STATE_DIR/wmi-owners.before"
[[ $(wc -l < "$TUNING_STATE_DIR/wmi-owners.before") -eq 1 ]] || \
  fail "expected exactly one WMI driver owner before replacement"
[[ $(cat "$TUNING_STATE_DIR/wmi-owners.before") == "$TUNING_DRIVER_NAME" ]] || \
  fail "stock WMI driver owner is not $TUNING_DRIVER_NAME"

rollback() {
  local rc=$?

  if [[ $# -eq 1 ]]; then
    rc=$1
  fi
  trap - ERR
  trap '' INT TERM HUP
  set +e
  printf '%s\n' "wmi-tuning load: replacement failed; restoring the saved stock module" >&2

  # Unload project if loaded.
  if tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
       "$TUNING_STATE_DIR/project.note"; then
    timeout --kill-after=5 20 rmmod "$TUNING_MODULE_NAME" 2>/dev/null || true
  fi

  # Restore stock.
  if ! tuning_stock_module_loaded; then
    insmod "$stock_copy" 2>/dev/null || true
  fi

  if tuning_loaded_note_matches "$TUNING_STOCK_MODULE" \
       "$TUNING_STATE_DIR/stock.note" &&
     [[ $(tuning_guid_owners) == "$(cat "$TUNING_STATE_DIR/wmi-owners.before")" ]] &&
     tuning_verify_stock_interfaces; then
    rm -f -- "$TUNING_STATE_DIR/active" "$TUNING_STATE_DIR/recovery-incomplete"
    printf '%s\n' "wmi-tuning load: stock module was restored" >&2
  else
    printf '%s\n' "wmi-tuning load: saved stock restoration is incomplete" >&2
    printf '%s\n' incomplete > "$TUNING_STATE_DIR/recovery-incomplete"
  fi
  exit "$rc"
}
trap rollback ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM
trap 'rollback 129' HUP

# Unload stock, load project.
timeout --kill-after=5 20 rmmod "$TUNING_STOCK_MODULE"
insmod "$module"

# Verify project module is loaded with correct build ID.
tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
  "$TUNING_STATE_DIR/project.note" || fail "loaded project module build ID is incorrect"

# Verify exact WMI ownership and read-only interfaces.
tuning_verify_project_interfaces || fail "project WMI interfaces are incomplete"

trap - ERR INT TERM HUP
printf '%s\n' active > "$TUNING_STATE_DIR/active"
printf '%s\n' "wmi-tuning load: project module is active"

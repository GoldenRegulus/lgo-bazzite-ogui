#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
# shellcheck disable=SC1091
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "wmi-tuning unload: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"

install -d -m 0700 "$TUNING_STATE_DIR"
exec 9> "$TUNING_STATE_DIR/lock"
flock -x 9

[[ ! -f $TUNING_STATE_DIR/recovery-incomplete ]] || \
  fail "a prior recovery is incomplete; keep the saved state for repair"

if [[ ! -f $TUNING_STATE_DIR/active ]]; then
  stock=$(modinfo -n "$TUNING_STOCK_MODULE" 2>/dev/null) || \
    fail "cannot find the stock module"
  tuning_extract_build_id_note "$stock" \
    "$TUNING_STATE_DIR/current-stock.note" || \
    fail "cannot read the current stock module build ID"
  if tuning_stock_module_loaded && \
     ! tuning_loaded_note_matches "$TUNING_STOCK_MODULE" \
       "$TUNING_STATE_DIR/current-stock.note"; then
    fail "state is missing and the loaded module is not stock"
  fi
  rm -f -- "$TUNING_STATE_DIR/current-stock.note"
  tuning_verify_stock_interfaces || fail "stock WMI interfaces are incomplete"
  printf '%s\n' "wmi-tuning unload: project module is not active"
  exit 0
fi

for file in project.note project.path project.sha256 stock-copy.path \
    stock.note stock.sha256 wmi-owners.before; do
  [[ -r $TUNING_STATE_DIR/$file ]] || fail "saved state is incomplete"
done

stock_copy=$(cat "$TUNING_STATE_DIR/stock-copy.path")
module=$(cat "$TUNING_STATE_DIR/project.path")
[[ -r $module ]] || fail "saved project module is missing"
[[ $(sha256sum "$module" | awk '{print $1}') == \
   "$(cat "$TUNING_STATE_DIR/project.sha256")" ]] || fail "the project module changed"
[[ $(sha256sum "$stock_copy" | awk '{print $1}') == \
   "$(cat "$TUNING_STATE_DIR/stock.sha256")" ]] || fail "the saved stock module changed"
tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
  "$TUNING_STATE_DIR/project.note" || fail "refusing to unload an unknown module"

recover_project() {
  local rc=$?

  if [[ $# -eq 1 ]]; then
    rc=$1
  fi
  trap - ERR
  trap '' INT TERM HUP
  set +e

  if ! tuning_module_loaded "$TUNING_MODULE_NAME"; then
    insmod "$module" 2>/dev/null || true
  fi

  if tuning_loaded_note_matches "$TUNING_MODULE_NAME" \
       "$TUNING_STATE_DIR/project.note" &&
     tuning_verify_project_interfaces; then
    printf '%s\n' "wmi-tuning unload: restoration failed; project module was recovered" >&2
  elif tuning_loaded_note_matches "$TUNING_STOCK_MODULE" \
         "$TUNING_STATE_DIR/stock.note" &&
       [[ $(tuning_guid_owners) == "$(cat "$TUNING_STATE_DIR/wmi-owners.before")" ]] &&
       tuning_verify_stock_interfaces; then
    rm -f -- "$TUNING_STATE_DIR/active" "$TUNING_STATE_DIR/recovery-incomplete"
    printf '%s\n' "wmi-tuning unload: stock module is active after a partial failure" >&2
  else
    printf '%s\n' "wmi-tuning unload: recovery failed; state and logs were kept" >&2
    printf '%s\n' incomplete > "$TUNING_STATE_DIR/recovery-incomplete"
  fi
  exit "$rc"
}
trap recover_project ERR
trap 'recover_project 130' INT
trap 'recover_project 143' TERM
trap 'recover_project 129' HUP

# Unload project, restore stock.
timeout --kill-after=5 20 rmmod "$TUNING_MODULE_NAME"
insmod "$stock_copy"
tuning_loaded_note_matches "$TUNING_STOCK_MODULE" "$TUNING_STATE_DIR/stock.note" || \
  fail "restored stock module build ID does not match"
[[ $(tuning_guid_owners) == "$(cat "$TUNING_STATE_DIR/wmi-owners.before")" ]] || \
  fail "WMI ownership was not restored"

# Read-only stock check after restoration.
tuning_verify_stock_interfaces || fail "stock WMI interfaces are incomplete"

trap - ERR INT TERM HUP
find "$TUNING_STATE_DIR" -mindepth 1 -maxdepth 1 ! -name lock -delete
printf '%s\n' "wmi-tuning unload: saved stock module is active"

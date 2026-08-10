#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "hid-driver unload: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ $(systemctl is-active inputplumber.service 2>/dev/null || true) != active ]] || \
  fail "stop InputPlumber before driver replacement"
install -d -m 0700 "$HID_STATE_DIR"
exec 9> "$HID_STATE_DIR/lock"
flock -x 9

[[ ! -f $HID_STATE_DIR/recovery-incomplete ]] || \
  fail "a prior recovery is incomplete; keep the saved state for repair"
if [[ ! -f $HID_STATE_DIR/active ]]; then
  stock=$(modinfo -n "$HID_MODULE_NAME") || fail "cannot find the stock module"
  hid_extract_build_id_note "$stock" "$HID_STATE_DIR/current-stock.note" || \
    fail "cannot read the current stock module build ID"
  if hid_module_loaded && ! hid_loaded_note_matches "$HID_STATE_DIR/current-stock.note"; then
    fail "state is missing and the loaded module is not stock"
  fi
  rm -f -- "$HID_STATE_DIR/current-stock.note"
  printf '%s\n' "hid-driver unload: project module is not active"
  exit 0
fi
for file in bindings.before project.note project.path project.sha256 stock-copy.path stock.note stock.sha256; do
  [[ -r $HID_STATE_DIR/$file ]] || fail "saved state is incomplete"
done
stock_copy=$(cat "$HID_STATE_DIR/stock-copy.path")
module=$(cat "$HID_STATE_DIR/project.path")
[[ -r $module ]] || fail "saved project module is missing"
[[ $(sha256sum "$module" | awk '{print $1}') == \
   "$(cat "$HID_STATE_DIR/project.sha256")" ]] || fail "the project module changed"
[[ $(sha256sum "$stock_copy" | awk '{print $1}') == \
   "$(cat "$HID_STATE_DIR/stock.sha256")" ]] || fail "the saved stock module changed"
hid_loaded_note_matches "$HID_STATE_DIR/project.note" || \
  fail "refusing to unload an unknown module"

recover_project() {
  local rc=$?

  if [[ $# -eq 1 ]]; then
    rc=$1
  fi
  trap - ERR
  trap '' INT TERM HUP
  set +e
  if ! hid_module_loaded; then
    insmod "$module"
  fi
  if hid_loaded_note_matches "$HID_STATE_DIR/project.note" &&
     hid_restore_bindings "$HID_STATE_DIR/bindings.before" &&
     [[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]]; then
    printf '%s\n' "hid-driver unload: restoration failed; project module was recovered" >&2
  elif hid_loaded_note_matches "$HID_STATE_DIR/stock.note" &&
       hid_restore_bindings "$HID_STATE_DIR/bindings.before" &&
       [[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]]; then
    rm -f -- "$HID_STATE_DIR/active" "$HID_STATE_DIR/recovery-incomplete"
    printf '%s\n' "hid-driver unload: stock module is active after a partial failure" >&2
  else
    printf '%s\n' "hid-driver unload: recovery failed; state and logs were kept" >&2
    printf '%s\n' incomplete > "$HID_STATE_DIR/recovery-incomplete"
  fi
  exit "$rc"
}
trap recover_project ERR
trap 'recover_project 130' INT
trap 'recover_project 143' TERM
trap 'recover_project 129' HUP
[[ $(systemctl is-active inputplumber.service 2>/dev/null || true) != active ]]
timeout --kill-after=5 20 rmmod "$HID_MODULE_NAME"
insmod "$stock_copy"
hid_loaded_note_matches "$HID_STATE_DIR/stock.note"
hid_restore_bindings "$HID_STATE_DIR/bindings.before"
[[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]]
trap - ERR INT TERM HUP
find "$HID_STATE_DIR" -mindepth 1 -maxdepth 1 ! -name lock -delete
printf '%s\n' "hid-driver unload: saved stock module is active"

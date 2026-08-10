#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$script_dir/lib.sh"

fail() {
  printf '%s\n' "hid-driver load: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ $(systemctl is-active inputplumber.service 2>/dev/null || true) != active ]] || \
  fail "stop InputPlumber before driver replacement"
validator=$script_dir/validate-host.sh
module_path=$script_dir/modules/$(uname -r)/hid-lenovo-go.ko
[[ -x $validator ]] || fail "installed validator is missing"
[[ -r $module_path ]] || fail "no module exists for running kernel $(uname -r)"
module=$(readlink -f -- "$module_path")
"$validator"

install -d -m 0700 "$HID_STATE_DIR"
exec 9> "$HID_STATE_DIR/lock"
flock -x 9

[[ ! -f $HID_STATE_DIR/recovery-incomplete ]] || \
  fail "a prior recovery is incomplete; keep the saved state for repair"
if [[ -f $HID_STATE_DIR/active ]]; then
  hid_loaded_note_matches "$HID_STATE_DIR/project.note" || \
    fail "active state does not match the loaded module"
  [[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]] || \
    fail "active binding map changed"
  printf '%s\n' "hid-driver load: project module is already active"
  exit 0
fi

find "$HID_STATE_DIR" -mindepth 1 -maxdepth 1 ! -name lock -delete
stock=$(modinfo -n "$HID_MODULE_NAME") || fail "cannot find the stock module"
[[ -r $stock ]] || fail "stock module is not readable"
case $stock in
  *.xz) stock_copy=$HID_STATE_DIR/stock-module.ko.xz ;;
  *.zst) stock_copy=$HID_STATE_DIR/stock-module.ko.zst ;;
  *.gz) stock_copy=$HID_STATE_DIR/stock-module.ko.gz ;;
  *) stock_copy=$HID_STATE_DIR/stock-module.ko ;;
esac
cp --reflink=auto -- "$stock" "$stock_copy"
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  chcon -t modules_object_t "$stock_copy"
fi
printf '%s\n' "$stock" > "$HID_STATE_DIR/stock.path"
printf '%s\n' "$stock_copy" > "$HID_STATE_DIR/stock-copy.path"
sha256sum "$stock_copy" | awk '{print $1}' > "$HID_STATE_DIR/stock.sha256"
sha256sum "$module" | awk '{print $1}' > "$HID_STATE_DIR/project.sha256"
printf '%s\n' "$module" > "$HID_STATE_DIR/project.path"
hid_extract_build_id_note "$stock_copy" "$HID_STATE_DIR/stock.note" || \
  fail "cannot read the stock module build ID"
hid_extract_build_id_note "$module" "$HID_STATE_DIR/project.note" || \
  fail "cannot read the project module build ID"

if ! hid_module_loaded; then
  insmod "$stock_copy" || fail "cannot load the saved stock module"
fi
hid_loaded_note_matches "$HID_STATE_DIR/stock.note" || \
  fail "the loaded module is not the saved stock module"
hid_binding_map > "$HID_STATE_DIR/bindings.before"
[[ -s $HID_STATE_DIR/bindings.before ]] || fail "no supported HID interface exists"

rollback() {
  local rc=$?

  if [[ $# -eq 1 ]]; then
    rc=$1
  fi
  trap - ERR
  trap '' INT TERM HUP
  set +e
  printf '%s\n' "hid-driver load: replacement failed; restoring the saved stock module" >&2
  if hid_loaded_note_matches "$HID_STATE_DIR/project.note"; then
    timeout --kill-after=5 20 rmmod "$HID_MODULE_NAME"
  fi
  if ! hid_module_loaded; then
    insmod "$stock_copy"
  fi
  if hid_loaded_note_matches "$HID_STATE_DIR/stock.note" &&
     hid_restore_bindings "$HID_STATE_DIR/bindings.before" &&
     [[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]]; then
    rm -f -- "$HID_STATE_DIR/active" "$HID_STATE_DIR/recovery-incomplete"
  else
    printf '%s\n' "hid-driver load: saved stock restoration is incomplete" >&2
    printf '%s\n' incomplete > "$HID_STATE_DIR/recovery-incomplete"
  fi
  exit "$rc"
}
trap rollback ERR
trap 'rollback 130' INT
trap 'rollback 143' TERM
trap 'rollback 129' HUP
[[ $(systemctl is-active inputplumber.service 2>/dev/null || true) != active ]]
timeout --kill-after=5 20 rmmod "$HID_MODULE_NAME"
insmod "$module"
hid_loaded_note_matches "$HID_STATE_DIR/project.note"
hid_restore_bindings "$HID_STATE_DIR/bindings.before"
[[ $(hid_binding_map) == "$(cat "$HID_STATE_DIR/bindings.before")" ]]

cfg=$(find /sys/bus/hid/devices -maxdepth 1 -name '0003:17EF:61E[B-E].*' \
  -exec test -d '{}/left_handle' \; -print -quit)
[[ -n $cfg ]]
[[ $(cat "$cfg/left_handle/hardware_generation") == 1 ]]
[[ $(cat "$cfg/right_handle/hardware_generation") == 1 ]]
printf '%s\n' active > "$HID_STATE_DIR/active"
trap - ERR INT TERM HUP
printf '%s\n' "hid-driver load: project module is active"

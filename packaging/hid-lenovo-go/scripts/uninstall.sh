#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

unit=legion-go-ogui-hid.service
unit_target=/etc/systemd/system/$unit
install_root=/usr/local/lib/legion-go-ogui/hid
current=$install_root/current
state_dir=/run/legion-go-ogui/hid-driver

fail() {
  printf '%s\n' "hid-driver uninstall: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ -x $current/deactivate.sh ]] || fail "installed recovery scripts are missing"

if systemctl is-active --quiet "$unit" || [[ -f $state_dir/active ]]; then
  "$current/deactivate.sh" || fail "driver deactivation failed; project files were kept"
fi
[[ ! -f $state_dir/active ]] || fail "project driver is still active"
[[ ! -f $state_dir/recovery-incomplete ]] || \
  fail "driver recovery is incomplete; project files were kept"
install -d -m 0700 "$state_dir"
exec 9> "$state_dir/lock"
flock -x 9
[[ ! -f $state_dir/active ]] || fail "project driver became active during uninstall"
[[ ! -f $state_dir/recovery-incomplete ]] || \
  fail "driver recovery became incomplete during uninstall"
[[ $(systemctl show -p ActiveState --value "$unit" 2>/dev/null || true) == inactive ]] || \
  fail "the service is not fully inactive"

# shellcheck source=lib.sh
source "$current/lib.sh"
stock=$(modinfo -n "$HID_MODULE_NAME") || fail "cannot find the stock module"
hid_extract_build_id_note "$stock" "$state_dir/uninstall-stock.note" || \
  fail "cannot read the stock module build ID"
hid_module_loaded || fail "the stock module is not loaded"
hid_loaded_note_matches "$state_dir/uninstall-stock.note" || \
  fail "the loaded module is not the stock module"
rm -f -- "$state_dir/uninstall-stock.note"

unit_backup=$(mktemp --tmpdir legion-go-ogui-hid-unit.XXXXXXXX)
cp -- "$unit_target" "$unit_backup"
quarantine=$install_root.removing.$$
unit_enabled=0
if systemctl is-enabled --quiet "$unit"; then
  unit_enabled=1
fi

rollback() {
  local rc=$?

  trap - ERR
  set +e
  if [[ -d $quarantine && ! -e $install_root ]]; then
    mv -- "$quarantine" "$install_root"
  fi
  install -m 0644 "$unit_backup" "$unit_target"
  systemctl daemon-reload
  if [[ $unit_enabled -eq 1 ]]; then
    systemctl enable "$unit"
  fi
  rm -f -- "$unit_backup"
  exit "$rc"
}
trap rollback ERR

if [[ $unit_enabled -eq 1 ]]; then
  systemctl disable "$unit"
fi
mv -- "$install_root" "$quarantine"
rm -f -- "$unit_target"
systemctl daemon-reload
rm -rf -- "$quarantine"
trap - ERR
rm -f -- "$unit_backup"

printf '%s\n' "Removed hid-driver project files"

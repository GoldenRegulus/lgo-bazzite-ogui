#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -Eeuo pipefail

root_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source_dir=$(CDPATH= cd -- "$root_dir/../../drivers/hid-lenovo-go" && pwd)
kver=$(uname -r)
module=$source_dir/hid-lenovo-go.ko
install_root=/usr/local/lib/legion-go-ogui/hid
releases=$install_root/releases
unit=legion-go-ogui-hid.service
unit_source=$root_dir/systemd/$unit
unit_target=/etc/systemd/system/$unit
state_dir=/run/legion-go-ogui/hid-driver

fail() {
  printf '%s\n' "hid-driver install: $*" >&2
  exit 1
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
[[ -r $module ]] || fail "build hid-lenovo-go.ko first"
[[ -r $unit_source ]] || fail "service file is missing"
[[ ! -f $state_dir/active ]] || fail "deactivate the project driver before installation"
[[ ! -f $state_dir/recovery-incomplete ]] || fail "repair the incomplete driver recovery first"
"$root_dir/scripts/validate-host.sh"

[[ $(modinfo -F name "$module") == hid_lenovo_go ]] || fail "module name is incorrect"
vermagic=$(modinfo -F vermagic "$module") || fail "cannot read module metadata"
[[ ${vermagic%% *} == "$kver" ]] || fail "module vermagic does not match $kver"
[[ $(modinfo -F depends "$module") == led-class-multicolor ]] || \
  fail "module dependency list is incorrect"

install -d -m 0700 "$state_dir"
exec 9> "$state_dir/lock"
flock -x 9
[[ ! -f $state_dir/active ]] || fail "project driver became active during installation"
[[ ! -f $state_dir/recovery-incomplete ]] || fail "driver recovery became incomplete"
[[ $(systemctl show -p ActiveState --value "$unit" 2>/dev/null || true) == inactive ]] || \
  fail "the service is not fully inactive"
install -d -m 0755 "$releases"
release_id=$(
  sha256sum "$module" "$unit_source" "$root_dir"/scripts/*.sh |
    awk '{print $1}' | sha256sum | awk '{print $1}'
)
release=$releases/$release_id
stage=$(mktemp -d "$releases/.stage.XXXXXXXX")
chmod 0755 "$stage"
old_link=$(readlink "$install_root/current" 2>/dev/null || true)
unit_backup=$(mktemp --tmpdir legion-go-ogui-hid-unit.XXXXXXXX)
unit_existed=0
unit_enabled=0
if [[ -f $unit_target ]]; then
  cp -- "$unit_target" "$unit_backup"
  unit_existed=1
fi
if systemctl is-enabled --quiet "$unit"; then
  unit_enabled=1
fi

rollback() {
  local rc=$?

  trap - ERR
  set +e
  rm -rf -- "$stage"
  if [[ -n $old_link ]]; then
    ln -sfn -- "$old_link" "$install_root/current.rollback"
    mv -Tf -- "$install_root/current.rollback" "$install_root/current"
  else
    rm -f -- "$install_root/current"
  fi
  if [[ $unit_existed -eq 1 ]]; then
    install -m 0644 "$unit_backup" "$unit_target"
  else
    rm -f -- "$unit_target"
  fi
  systemctl daemon-reload
  if [[ $unit_enabled -eq 0 ]]; then
    systemctl disable "$unit"
  fi
  rm -f -- "$unit_backup"
  exit "$rc"
}
trap rollback ERR

install -d -m 0755 "$stage/modules/$kver"
install -m 0644 "$module" "$stage/modules/$kver/hid-lenovo-go.ko"
for script in activate.sh deactivate.sh lib.sh load.sh unload.sh uninstall.sh validate-host.sh; do
  install -m 0755 "$root_dir/scripts/$script" "$stage/$script"
done
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  chcon -t modules_object_t "$stage/modules/$kver/hid-lenovo-go.ko"
fi
if [[ -d $release ]]; then
  rm -rf -- "$stage"
else
  mv -- "$stage" "$release"
fi
install -m 0644 "$unit_source" "$unit_target"
ln -sfn -- "releases/$release_id" "$install_root/current.new"
mv -Tf -- "$install_root/current.new" "$install_root/current"
systemctl daemon-reload
systemctl disable "$unit"
trap - ERR
rm -f -- "$unit_backup"

printf '%s\n' "Installed $release/modules/$kver/hid-lenovo-go.ko"
printf '%s\n' "The service is disabled. Use current/activate.sh for a controlled start."

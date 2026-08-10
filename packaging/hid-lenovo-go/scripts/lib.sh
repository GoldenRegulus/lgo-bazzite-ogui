#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

HID_DRIVER_NAME=hid-lenovo-go
HID_MODULE_NAME=hid_lenovo_go
HID_STATE_DIR=/run/legion-go-ogui/hid-driver
HID_INSTALL_ROOT=/usr/local/lib/legion-go-ogui/hid
HID_UNIT=legion-go-ogui-hid.service

hid_binding_map() {
  local current device driver interface
  local -a devices

  shopt -s nullglob
  devices=(/sys/bus/hid/devices/0003:17EF:61E[B-E].*)
  shopt -u nullglob
  for device in "${devices[@]}"; do
    interface=$(basename "$(dirname "$(readlink -f -- "$device")")")
    driver=-
    if [[ -L $device/driver ]]; then
      current=$(readlink -f -- "$device/driver")
      driver=${current##*/}
    fi
    printf '%s %s\n' "$interface" "$driver"
  done | LC_ALL=C sort
}

hid_find_device() {
  local device interface target
  local -a devices

  target=$1
  shopt -s nullglob
  devices=(/sys/bus/hid/devices/0003:17EF:61E[B-E].*)
  shopt -u nullglob
  for device in "${devices[@]}"; do
    interface=$(basename "$(dirname "$(readlink -f -- "$device")")")
    if [[ $interface == "$target" ]]; then
      printf '%s\n' "$device"
      return 0
    fi
  done
  return 1
}

hid_bind() {
  local current device driver id interface target

  interface=$1
  target=$2
  [[ $interface =~ ^[A-Za-z0-9_.:-]+$ ]] || return 1
  [[ $target == - || $target =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  device=$(hid_find_device "$interface") || return 1
  id=${device##*/}

  current=-
  if [[ -L $device/driver ]]; then
    driver=$(readlink -f -- "$device/driver")
    current=${driver##*/}
  fi
  [[ $current == "$target" ]] && return 0
  if [[ $current != - ]]; then
    printf '%s' "$id" > "/sys/bus/hid/drivers/$current/unbind"
  fi
  if [[ $target != - ]]; then
    [[ -w /sys/bus/hid/drivers/$target/bind ]] || return 1
    printf '%s' "$id" > "/sys/bus/hid/drivers/$target/bind"
  fi
}

hid_restore_bindings() {
  local driver interface

  while read -r interface driver; do
    [[ -n $interface && -n $driver ]] || return 1
    hid_bind "$interface" "$driver" || return 1
  done < "$1"
}

hid_extract_build_id_note() {
  local module output temporary

  module=$1
  output=$2
  temporary=$(mktemp --tmpdir hid-lenovo-go-module.XXXXXXXX)
  case $module in
    *.xz) xz -dc -- "$module" > "$temporary" ;;
    *.zst) zstd -qdc -- "$module" > "$temporary" ;;
    *.gz) gzip -dc -- "$module" > "$temporary" ;;
    *) cp -- "$module" "$temporary" ;;
  esac
  objcopy --dump-section ".note.gnu.build-id=$output" "$temporary"
  rm -f -- "$temporary"
  [[ -s $output ]]
}

hid_loaded_note_matches() {
  [[ -r /sys/module/$HID_MODULE_NAME/notes/.note.gnu.build-id ]] &&
    cmp -s -- /sys/module/$HID_MODULE_NAME/notes/.note.gnu.build-id "$1"
}

hid_module_loaded() {
  grep -q "^$HID_MODULE_NAME " /proc/modules
}

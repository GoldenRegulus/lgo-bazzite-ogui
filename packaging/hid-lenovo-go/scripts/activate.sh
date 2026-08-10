#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

unit=legion-go-ogui-hid.service
input_active=0

fail() {
  printf '%s\n' "hid-driver activate: $*" >&2
  exit 1
}

restore_input() {
  local unused

  [[ $input_active -eq 1 ]] || return 0
  systemctl reset-failed inputplumber.service
  systemctl start inputplumber.service || return 1
  for unused in {1..30}; do
    systemctl is-active --quiet inputplumber.service && return 0
    sleep 1
  done
  return 1
}

finish() {
  local rc=$?

  trap - EXIT INT TERM HUP
  if ! restore_input; then
    printf '%s\n' "hid-driver activate: InputPlumber restoration failed" >&2
    rc=1
  fi
  exit "$rc"
}

[[ $# -eq 0 ]] || fail "this command does not accept arguments"
[[ $EUID -eq 0 ]] || fail "run as root"
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if systemctl is-active --quiet inputplumber.service; then
  input_active=1
  systemctl stop inputplumber.service
fi
systemctl start "$unit" || fail "service start failed"
restore_input || fail "InputPlumber restoration failed"
input_active=0
trap - EXIT INT TERM HUP
printf '%s\n' "hid-driver activate: project module is active"

#!/usr/bin/env bash
# This is started by the fixed GNOME autostart entry.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  exit 2
fi
if [[ "$(/usr/bin/id -u)" -eq 0 || -z "${HOME:-}" || "$HOME" != /* ]]; then
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(/usr/bin/dirname -- "$0")" && /usr/bin/pwd -P)"
AUTOSTART_FILE="$HOME/.config/autostart/legion-go-ogui-backend-install.desktop"

# Remove the one-shot request before sudo can display a prompt or be cancelled.
/usr/bin/rm -f -- "$AUTOSTART_FILE"
exec /usr/bin/bash "$SCRIPT_DIR/install-backend.sh"

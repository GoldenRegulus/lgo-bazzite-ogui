#!/usr/bin/env bash
# Schedule one terminal-backed installer run at the next GNOME login.
set -euo pipefail

if [[ "$#" -ne 0 ]]; then
  printf '%s\n' 'This launcher does not accept arguments.' >&2
  exit 2
fi
if [[ "$(/usr/bin/id -u)" -eq 0 ]]; then
  printf '%s\n' 'Run this launcher as the desktop user, not as root.' >&2
  exit 2
fi
if [[ -z "${HOME:-}" || "$HOME" != /* ]]; then
  printf '%s\n' 'A valid home directory is required.' >&2
  exit 3
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(/usr/bin/dirname -- "$0")" && /usr/bin/pwd -P)"
RUNNER="$SCRIPT_DIR/run-scheduled-install.sh"
AUTOSTART_DIR="$HOME/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/legion-go-ogui-backend-install.desktop"
UNINSTALL_AUTOSTART_FILE="$AUTOSTART_DIR/legion-go-ogui-backend-uninstall.desktop"

if [[ ! -f "$RUNNER" ]]; then
  printf '%s\n' 'The bundled scheduled installer runner is missing.' >&2
  exit 4
fi

# Escape only the two Desktop Entry quoted-string characters used in this path.
ESCAPED_RUNNER="${RUNNER//\\/\\\\}"
ESCAPED_RUNNER="${ESCAPED_RUNNER//\"/\\\"}"
umask 077
/usr/bin/mkdir -p -- "$AUTOSTART_DIR"
/usr/bin/rm -f -- "$UNINSTALL_AUTOSTART_FILE"
/usr/bin/printf '%s\n' \
  '[Desktop Entry]' \
  'Type=Application' \
  'Name=Install Legion Go OGUI backend' \
  "Exec=/usr/bin/bash \"$ESCAPED_RUNNER\"" \
  'Terminal=true' \
  'X-GNOME-Autostart-enabled=true' \
  > "$AUTOSTART_FILE"
/usr/bin/chmod 0600 -- "$AUTOSTART_FILE"

printf '%s\n' 'The installer will open in a terminal at the next GNOME login.'
printf '%s\n' 'It removes this one-shot entry before it asks sudo for consent.'

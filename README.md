# Legion Go OpenGamepadUI Plugin for Bazzite

This development plugin adds Lenovo Legion Go controls to OpenGamepadUI (OGUI).
It targets `bazzite-deck-gnome:testing`.

## Supported hardware

The Original Lenovo Legion Go is the only live-verified device. It must report:

- Vendor: `LENOVO`
- Product name: `83E1`
- Product version: `Legion Go 8APU1`

Legion Go 2 work is source-backed only. Do not use this build on Legion Go 2 or Legion Go S.

## Controls

The full-screen menu has Battery, Cooling, and Controllers pages.

- Set the battery limit to 80% Long Life or 100% Standard.
- Read fan speed and control Full Speed.
- Select Automatic, Quiet, Balanced, Performance, or Custom fan settings.
- Swap the Lenovo, Menu, and View buttons.
- View the FPS switch and mouse DPI status.
- Start or cancel joystick, trigger, and gyroscope calibration.
  This requires the applicable driver support.

## Status

Version `0.12.12` works on the live-verified Original Legion Go.

The current fan range is a project safety limit. It is not a proved EC maximum.

## Experimental kernel support

The backend can replace the in-tree `lenovo_wmi_other` module to add fan
controls. This route is experimental. It is only live-verified on the Original
Legion Go. It can break after a kernel update and has no broad support promise.

## Installation

Download the tested plugin package from the latest GitHub release. Do not
extract it.

```sh
mkdir -p ~/.local/share/opengamepadui/plugins
curl -L https://github.com/GoldenRegulus/lgo-bazzite-ogui/releases/latest/download/legion-go.zip \
  -o ~/.local/share/opengamepadui/plugins/legion-go.zip
```

Restart OGUI or restart the device. Open the Legion Go plugin settings and
select **Install backend**. Backend setup requires administrator approval. It
builds both kernel modules for the running kernel. The matching kernel headers
and C build tools must be available.

## Development source build

A source build is not required for normal installation. It needs Linux x86-64,
Git, Make, Cargo, Rust 1.87 or newer, `bc`, Base64, the Godot 4.7 editor, and the
headers for the running kernel.

Run `make` as a regular user in the project directory. It builds and exports
`legion-go.zip` to the local OGUI plugin directory.

## Permissions

OGUI runs as the desktop user. Hardware setup requires administrator approval.

## Documents

- [License inventory](LICENSES/README.md)
- [Requirements](REQUIREMENTS.md)
- [Technical Reference](wiki/Technical-Reference.md)
- [Lenovo WMI fan source](drivers/lenovo-wmi-fan/README.md)
- [Windows Legion Space research](wiki/Research.md)
- [Test results](wiki/Validation.md)

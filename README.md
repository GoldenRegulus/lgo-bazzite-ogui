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

Version `0.12.7` works on the live-verified Original Legion Go.

The current fan range is a project safety limit. It is not a proved EC maximum.

## Experimental kernel support

The backend can replace the in-tree `lenovo_wmi_other` module to add fan
controls. This route is experimental. It is only live-verified on the Original
Legion Go. It can break after a kernel update and has no broad support promise.

## Installation

Download or clone the source. In the project directory, run:

```sh
make
```

Run this command as a regular user. It builds and installs the plugin locally.
Then open its settings and select **Install backend**. Backend setup requires administrator approval.

## Permissions

OGUI runs as the desktop user. Hardware setup requires administrator approval.

## Documents

- [License inventory](LICENSES/README.md)
- [Requirements](REQUIREMENTS.md)
- [Technical Reference](wiki/Technical-Reference.md)
- [Lenovo WMI fan source](drivers/lenovo-wmi-fan/README.md)
- [Windows Legion Space research](wiki/Research.md)
- [Test results](wiki/Validation.md)

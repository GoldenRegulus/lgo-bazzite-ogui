# Technical Reference

## Architecture

| Component | Responsibility | Must not do |
|---|---|---|
| OGUI plugin | Present capability and confirmed state. Send typed requests. | Run as root or send raw EC, ACPI, HID, or uinput operations. |
| InputPlumber | Own controller HID and IIO sources, composite routing, and virtual targets. | Be changed by this project or replaced by a plugin reader or physical-device owner. |
| Deferred DSU backend | No implementation. A future backend can use only a released source-identified motion interface. | Open physical or virtual input devices, emit buttons, or run as root. |
| Restricted battery helper | Validate one target and battery. Read state. Write only 80 or 100 with readback. | Accept paths, values, arbitrary commands, HID reports, ACPI methods, or EC addresses. |
| Linux kernel interfaces | Provide typed, bounded power-supply, HID, LED, WMI, and hwmon transport interfaces. | Save, infer, confirm, restore, or persist user policy. |
| Project HID kernel driver | Own calibration transport and controller LED path. | Route input or contain plugin policy. |
| OpenGamingCollective Lenovo WMI interfaces | Own the fan curve, Full Speed, and tachometer interfaces. | Change thermal profile, TDP, or power limits for fan-only controls. |

PowerStation owns general performance controls, not fan-only modes or gyro routing. HHD is research evidence, not a dependency.

- Support host and detachable-controller generations separately.
- Prefer a released owner interface. Add a project interface only after the dependency gate proves it necessary.
- Keep Legion Go 2 source-backed claims separate from live verification. Do not infer a host gate from a UI label.
- Keep `SetFanMode` separate from `SetSmartFanMode` and Linux `platform_profile`.
- DSU/Cemuhook, main-gyro selection, and standard controller LED integration are deferred. Do not change InputPlumber source, profiles, or configuration. Use Steam and InputPlumber for mapping. Do not add a plugin template, remapping, direct LED write, or lighting editor.
- Use the restricted battery helper because the tested native continuous UI misreported binary 80% and 100% firmware states.

### OGUI navigation

The plugin settings card contains one Open button. It pushes a plugin-owned state onto OGUI's existing menu state machine and shows one full-screen control.

The full-screen control uses OGUI's native tab header and four tabs: Battery, Cooling, Controllers, and Calibration. LB and RB change tabs. Back pops only the plugin state. The plugin does not change InputPlumber interception.

Each tab has one focus group. Hidden, disabled, and read-only controls do not enter the focus chain. Routine refreshes do not remove active controls from focus.

### Dependency gate

Before a dependency source change or project hardware interface:

1. Identify the unmet requirement and reproduce it.
2. Show why a released interface is insufficient. Search current owner work.
3. Identify affected devices, capabilities, and callers.
4. Recover protocol, bounds, results, errors, lifecycle, and recovery.
5. Make the smallest owner-native change. Keep packaging and plugin policy outside it.
6. Pass synthetic tests, a build with the target kernel, no-write lifecycle tests, and controlled live tests.

### Current gyro boundary

InputPlumber owns center, left, and right gyro and accelerometer routing. Target selection does not remove source filters. InputPlumber 0.78 has no source-identified vector signal for an external DSU backend: its DBus target drops `Vector3`, and the composite converts source-specific motion to generic motion before normal targets. Do not modify InputPlumber or let another backend read HID, IIO, evdev, or virtual gamepad devices.

A project hardware interface needs exact capability gates, bounded parsing and serialization, removal safety, readback when available, suspend and resume, uninstall and rollback, synthetic tests, and controlled target evidence. Keep source, tests, protocol evidence, and packaging separate.

See [Hardware and Software Interfaces](#hardware-and-software-interfaces) and [validation records](Validation.md).

## Hardware and Software Interfaces

**Source-backed** facts come from Linux, InputPlumber, HHD, or copied Lenovo Legion Space 1.4.4.21 analysis. **Live-verified** facts come from the original Legion Go 8APU1. Source-backed facts do not authorize writes.

Sources: [Linux charge support](https://github.com/torvalds/linux/commit/9ca8fc065b88b327acbfdc33454efea391639716), [Linux HID driver](https://github.com/torvalds/linux/blob/11028ab62899e4191e074ee364c712b77823a9c4/drivers/hid/hid-lenovo-go.c), [InputPlumber Legion Go profile](https://github.com/ShadowBlip/InputPlumber/blob/082f67fba6aaff88441abdc482ae76b711ad2885/rootfs/usr/share/inputplumber/devices/50-legion_go.yaml), and copied Lenovo Legion Space 1.4.4.21. The local source copy is Git-ignored. Copy needed Windows files before inspection. Do not inspect the source volume directly.

### Target gates

| Scope | Gate | Evidence and limit |
|---|---|---|
| Original Legion Go writes | DMI `LENOVO`, `83E1`, and `Legion Go 8APU1` | Live-verified target. Reject a mismatch. |
| Updated controller protocol | Controller vendor `0x17ef`; PIDs `0x61eb` through `0x61ee` | Source-backed driver match. The project tested `0x61eb`. |
| Legion Go 2 | A recognized product name or version, after partial Original-Go identity rejection, plus a per-function route, values, bounds, result, errors, and recovery | Best-effort support uses a `0..115` project fan limit from the driver reference. It is not a proved firmware ceiling and is not live-verified. |
| Legion Go S | Excluded | SteamOS owns native support. |

### Battery

**Owner:** Linux power-supply class through `legion-go-ogui-helper`.

- Validate DMI and find exactly one power supply with type `Battery` and a regular `charge_types` attribute.
- `status` is unprivileged. `enable` writes only `Long_Life`; `disable` writes only `Standard`. Both require root and exact readback.
- Parse only `Standard` and `Long_Life` with exactly one bracketed active value. Return 80 or 100 for the existing user interface.
- Unknown: reboot, suspend, external change, unsupported firmware, and multiple batteries.

### Fan

**Owner:** OpenGamingCollective Lenovo WMI interfaces. The helper is the only project fan writer.

| Operation | Contract |
|---|---|
| Full Speed | Lenovo Other Mode WMI GUID `DC2A8805-3A8C-41BA-A6F7-092E0089CD3B`, regular `fan_fullspeed`; write and readback Boolean `0` or `1`. |
| Tachometer | Exactly one `lenovo_wmi_other` hwmon device with regular `name` and `fan1_input`; return raw RPM. |
| Curve read/write | Lenovo Fan Method WMI GUID `92549549-4BDE-4F06-AC04-CE8BF898DBAA`, regular `fan_curve`; read and write one ten-point table. |

The in-tree interfaces expose RPM, independent Full Speed, and one complete curve. The plugin owns labels and tables:

| Plugin label | Complete curve |
|---|---|
| Automatic | `44 44 55 60 71 87 100 100 100 100` |
| Quiet | `44 48 48 48 48 48 48 48 48 48` |
| Balanced | `44 48 55 60 60 60 60 60 60 60` |
| Performance | `44 48 55 60 71 79 87 87 100 100` |
| Custom | The user's validated curve |

Automatic is the live original-Go probe curve. Quiet, Balanced, and Performance are Lenovo original-Go tables. Curve submission does not change Full Speed. The plugin shows Full Speed independently and infers labels only by exact curve equality.

Temperature points are 10 through 100 °C in 10 °C steps. A write contains exactly ten nondecreasing levels. The current project policy permits `0..125` at 10–70 °C, `79..125` at 80–90 °C, and `100..125` at 100 °C. The backend also accepts the exact Quiet and Balanced tables. The helper confirms each requested value by readback. The EC behavior above `125` is an open question.

The firmware curve is the source of truth. A controlled warm reboot retained an exact custom curve. The plugin reads this curve and does not persist a second preference copy. A confirmed write remains in firmware across driver removal. The kernel driver serializes transport calls but does not save, infer, confirm, restore, or persist a curve or Full Speed preference.

`SetFanMode` reaches `Fan_Set_Table`. Do not substitute `SetSmartFanMode`, Linux `platform_profile`, a thermal profile, TDP, WMAA, or a power limit. Immutable packaging builds the integrated owner for the running kernel. Installation does not activate it.

### Controller calibration

**Owner:** Linux `hid-lenovo-go`. Reviewed source: [`drivers/hid-lenovo-go`](../drivers/hid-lenovo-go/README.md).

Linux creates MCU, transmitter, left, right, and touchpad attribute groups for each matched `0x61eb..0x61ee` device. It reads `hardware_generation` for MCU, transmitter, and handles, but does not gate attributes or operations with it. The project source preserves this behavior and adds no generation or host-DMI gate in `hid-lenovo-go.c`.

Lenovo source proves fixed, zero-filled 64-byte requests. `<device>` is `03` for left or `04` for right. `<action>` is `01` Start or `02` Stop.

```text
Trigger:  05 00 0a 04 <device> <action> 00 ... 00
Joystick: 05 00 0c 04 <device> <action> 00 ... 00
Gyro:     05 00 0e 06 <device> <action> 00 ... 00
```

Windows keys `0x43`, `0x4d`, and `0x58` select these requests. They are not raw HID bytes.

Live read-only evidence:

```text
Request: 05 00 02 06 03 00 ... 00
Reply:   04 00 02 06 03 01 ... 00
```

Synchronous commands retain the kernel 50 ms bound. Input framing requires a 64-byte `04` report on the active configuration interface. The waiter matches command and sub-command at bytes `2..3`; device is not part of its key. A late identical reply is ambiguous because there is no sequence token. Short write or nonzero synchronous SET returns `-EIO`; timeout returns `-ETIMEDOUT`; negative HID errors and interrupted waits propagate; removed interfaces return `-ENODEV`.

Calibration is asynchronous. A sysfs write sends one report and returns the HID submission result. It does not wait for firmware, set a deadline, or retry. Userspace owns workflow policy.

Live evidence proves completion `04 00 a0 02 <device> <module> <result> <error-le16> ...`. Device is `03` or `04`; module is gyro `01`, joystick `02`, or trigger `03`; result is failure `00` or success `01`. The kernel exposes `success` or `failure` through `calibrate_<module>_status` and raw error through `calibrate_<module>_error`. Do not overlap indistinguishable operations.

| Module | Errors |
|---|---|
| Gyro | `0x0001` not stationary or timeout; `0x0002` connection changed |
| Joystick | `0x0100` full range missing; `0x0200` not centered; `0x0400` rotations missing; `0x0800` connection changed |
| Trigger | `0x0001` not fully pressed; `0x0002` did not return; `0x0004` not pressed twice; `0x0008` connection changed |
| All | `0xffff` exception |

Evidence: [calibration test record](Validation.md#test-record-hid-calibration-transport).

### Input and gyro routing

**Owner:** InputPlumber. Center motion uses IIO. Left and right motion use Lenovo HID. InputPlumber filters all six gyro and accelerometer signals before target routing. `deck-uhid` and DualSense support does not remove these filters.

The filter setter has no proved atomic whole-operation contract after source re-enumeration. Do not use it as an interactive control. A future interface needs named source selection, target lifecycle, confirmed whole-operation state, rollback, and no duplicate motion. Do not add a second HID reader or virtualizer.

### Other controller operations

Button swap accepts fixed requests and tracks requested state, but has no firmware readback. FPS assignment, DPI, vibration, touchpad, auto-sleep, factory reset, power-button lighting, and controller LED completion lack a safe owner contract. Do not send historical or community reports.

### Legion Go 2 best-effort boundary

The project supports Go 2 routes on a best-effort basis when the driver reference supplies the route, serializer or method, values, bounds, reply or readback, errors, and recovery behavior. The current gate accepts a recognized product name or version after it rejects a partial Original-Go identity. Keep each function marked source-backed until target validation proves it.

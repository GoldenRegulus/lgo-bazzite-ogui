# Windows Legion Space Research

This research comes only from static analysis of Lenovo Legion Space `1.4.4.21` for Windows.

No Windows program was run. No controller or firmware command was sent. This collection does not include findings from other source trees or hardware tests.

## Research documents

- [Application values and maps](research/Legion-Space-App.md) covers model selection, values, ranges, and error maps.
- [Application bridge](research/Legion-Space-Bridge.md) maps app methods and fields to proved native methods.
- [Low-level raw maps](research/Legion-Space-Driver.md) covers native DLLs, WMI calls, HID requests, replies, selectors, records, and missing serializers.
- [Source set](research/Legion-Space-Source-Set.md) records the copied files, hashes, and analysis method.

## What the analysis found

| Area | Result |
| --- | --- |
| Product selection | Legion Space has separate `GO`, `GOS`, and `GO2` paths. Controller generation and host model are separate inputs. |
| Fan control | The app defines mode values, original-Go fan tables, Full Speed, fan RPM, and the native fan-table call path. |
| Controller settings | The app defines button, lighting, joystick, trigger, gyro, vibration, touchpad, DPI, sleep, and calibration values. |
| Calibration protocol | The native controller DLL proves the complete 64-byte Start and Stop HID requests for both controllers. |
| Other controller protocols | The analysis found KZ selectors, native records, four vibration-family report headers, and many native methods. Most complete HID packets remain unknown. |
| Battery and power-button light | The app proves Boolean controls and native function names. It does not prove their complete low-level requests. |
| Legion Go 2 | The app contains Go 2 screens and native branches. It does not provide a plain-text Go 2 DMI identity. |

## Low-level command results

The decompilation produced one complete current HID command family: controller calibration. It also produced four partial write headers for vibration-related controls.

| Function | Result |
| --- | --- |
| Trigger calibration | `05 00 0a 04 <device> <action> 00 ... 00` |
| Joystick calibration | `05 00 0c 04 <device> <action> 00 ... 00` |
| Gyro calibration | `05 00 0e 06 <device> <action> 00 ... 00` |

Each request is 64 bytes. `<device>` is `03` for left or `04` for right. `<action>` is `01` for Start or `02` for Stop. See [Native driver and protocol](research/Legion-Space-Driver.md#controller-calibration) for reply handling and error values.

The KZ command map also proves these partial report headers:

| Function | Header | Limit |
| --- | --- | --- |
| Handle vibration | `05 00 06 02` | Complete payload and reply are unknown. |
| Vibration notification | `05 00 06 03` | Complete payload and reply are unknown. |
| Touchpad vibration | `05 00 06 06` | Complete payload and reply are unknown. |
| Vibration test | `05 00 06 07` | Complete payload and reply are unknown. |

The fan analysis also found these WMI feature IDs:

| Function | Feature ID | Value |
| --- | ---: | --- |
| Full Speed | `0x04020000` | Boolean `0` or `1` |
| Fan RPM | `0x04030001` | Raw 32-bit RPM value |

The runtime WMI class and complete request buffer were not recovered. These are method and feature values, not a complete WMI command.

## Important gaps

The Windows app does not yet provide complete raw requests for:

- Lenovo/Menu/View swap;
- mouse DPI;
- vibration;
- touchpad settings;
- controller sleep;
- controller lighting;
- button maps and templates;
- factory reset;
- battery mode;
- power-button lighting;
- fan-curve WMI serialization.

The [application document](research/Legion-Space-App.md) records the app values for these functions. The [driver document](research/Legion-Space-Driver.md) records the known native calls and the missing low-level fields.

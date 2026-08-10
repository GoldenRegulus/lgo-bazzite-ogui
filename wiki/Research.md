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

## Linux kernel upstream and contribution route — 2026-08-11

The final upstream for both kernel components is the Linux kernel project. The
OpenGamingCollective Linux repository is a downstream integration tree. It is
useful for testing and coordination, but it is not the final acceptance route.

### Lenovo Legion Go HID

`drivers/hid/hid-lenovo-go.c` is in Linus's mainline tree, linux-next, and the
HID maintainer tree. Derek J. Clark authored the original mainline driver. The
current Lenovo HID maintainers are Derek J. Clark and Mark Pearson. The HID
subsystem maintainers are Jiri Kosina and Benjamin Tissoires.

Submit changes against the HID maintainer tree:

- Tree: <https://git.kernel.org/pub/scm/linux/kernel/git/hid/hid.git>
- List: `linux-input@vger.kernel.org`
- Archive: <https://lore.kernel.org/linux-input/>
- Patchwork: <https://patchwork.kernel.org/project/linux-input/list/>
- Subject form: `HID: hid-lenovo-go: <change>`

The accepted original driver is commit
[`d69ccfcbc955`](https://github.com/torvalds/linux/commit/d69ccfcbc9551988190895bc125a8bf709aa5931).
The current sysfs ABI document is
[`Documentation/ABI/testing/sysfs-driver-hid-lenovo-go`](https://github.com/torvalds/linux/blob/master/Documentation/ABI/testing/sysfs-driver-hid-lenovo-go).

### Lenovo WMI

`drivers/platform/x86/lenovo/wmi-other.c` is in mainline Linux. The base driver
entered mainline in commit
[`edc4b183b794`](https://github.com/torvalds/linux/commit/edc4b183b794baefb54aa0baeb810fe3ac65d826).
Standard capability-gated hwmon fan support entered in commit
[`51ed34282f63`](https://github.com/torvalds/linux/commit/51ed34282f63fab5b3996477cc56135eb4de5284).

Mainline does not contain this project's Fan Method GUID curve interface or
Full Speed interface. The complete external replacement file is not a suitable
submission unit. Reconstruct the work as small, incremental changes against the
current in-tree driver.

The Lenovo WMI maintainers are Mark Pearson and Derek J. Clark. The x86
platform driver maintainers are Hans de Goede and Ilpo Järvinen.

- Tree: <https://git.kernel.org/pub/scm/linux/kernel/git/pdx86/platform-drivers-x86.git>
- List: `platform-driver-x86@vger.kernel.org`
- Archive: <https://lore.kernel.org/platform-driver-x86/>
- Patchwork: <https://patchwork.kernel.org/project/platform-driver-x86/list/>
- Subject form: `platform/x86: lenovo-wmi-other: <change>`

Run `scripts/get_maintainer.pl` on the final patches. New hwmon or sysfs
interfaces can also require `linux-hwmon@vger.kernel.org`, its maintainers, and
`linux-api@vger.kernel.org`. Do not select recipients from this document alone.

### Required preparation

The current project diffs are review artifacts, not submission patches. Before
submission:

1. Rebase each component on its current subsystem tree. Drop changes that are
   already upstream.
2. Reconstruct each logical change as one commit. Each commit must build and
   work by itself.
3. Preserve upstream authorship. Establish the human author and source
   provenance for every added line.
4. Add or update `Documentation/ABI/` for each userspace interface. Update the
   applicable driver document.
5. Use a standard hwmon interface when it can represent a fan function. Get
   hwmon review before adding a custom fan sysfs ABI.
6. Resolve the unexpected controller LED activation. Do not submit a series
   with a known lifecycle regression.
7. Add in-tree tests where practical. Keep live hardware evidence with the
   cover letter or commit that it supports.

The human submitter must review the complete series and add the human
`Signed-off-by` trailer under the Developer Certificate of Origin. AI tools
must not add this trailer. Current kernel guidance requires an `Assisted-by`
trailer when an AI tool materially assisted the contribution. The submitter
needs a known identity and a working email address because review is public and
occurs by email.

### Submission checklist

For each series:

- Run `scripts/checkpatch.pl --strict` and justify each remaining report.
- Run sparse and `make checkstack`.
- Build relevant configurations with the changed option set to `y`, `m`, and
  `n`; also test `allnoconfig`, `allmodconfig`, and an `O=` output directory.
- Build changed code with extra warnings, including `W=1`.
- Build changed documentation with `make htmldocs`.
- Build and test against current linux-next.
- Run HID selftests and `hid-tools` checks for HID report changes.
- Test probe, removal, unload and reload, suspend and resume, missing
  capabilities, malformed firmware replies, concurrent access, and failure
  cleanup.
- Test on the Original Legion Go. State clearly that Legion Go 2 is not live
  tested.
- Run `scripts/get_maintainer.pl` on the generated patches.
- Generate a cover letter for a series and include the exact base commit.
- Send plain-text patches by email with `git send-email` or `b4`. Send a test
  to yourself and confirm that `git am` applies it unchanged.
- Reply to review inline. Send the complete series for each revision and put
  the revision changes below the `---` separator.

Official process sources:

- [Submitting patches](https://docs.kernel.org/process/submitting-patches.html)
- [Submission checklist](https://docs.kernel.org/process/submit-checklist.html)
- [Email client requirements](https://docs.kernel.org/process/email-clients.html)
- [AI coding assistants](https://docs.kernel.org/process/coding-assistants.html)
- [B4 contributor workflow](https://b4.docs.kernel.org/en/latest/contributor/overview.html)

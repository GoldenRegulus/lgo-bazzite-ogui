# Lenovo WMI kernel change record

This record lists project edits to `wmi-other.c` relative to OpenGamingCollective
Linux commit `9c37615c0efca8ec4c7d461ef7ae2f4806951ace`. It does not describe
unchanged upstream code.

## 1. Select supported handhelds

**Edit:** Add Lenovo DMI matching for the Original Legion Go. Add a separate,
best-effort rule for source-known Legion Go 2 identifiers.

**Reason:** The Fan Method WMI GUID is also present on Lenovo laptops. A
handheld-specific interface must not appear on unrelated hardware.

**Limit:** Only the Original Legion Go match is live-verified. The Legion Go 2
rule is not a support claim.

## 2. Add the Fan Method curve interface

**Edit:** Add `fan_curve`, which reads and writes one complete ten-point curve
through Fan Method WMI methods 5 and 6. Parse reply shape and bounds before
exposing values. Serialize all ten values for a write.

**Reason:** A complete curve is the firmware transport unit. Per-point kernel
controls would create partial firmware state and duplicate plugin policy.

## 3. Add independent Full Speed control

**Edit:** Add Boolean `fan_fullspeed` through Lenovo Other Mode WMI methods 17
and 18. Synchronize reads, writes, and sysfs removal.

**Reason:** Full Speed uses a different firmware route from the curve. It must
not silently change the selected curve.

## 4. Provide RPM readback

**Edit:** Provide standard hwmon `fan1_input` when the native RPM path is not
available on a supported handheld.

**Reason:** Userspace needs actual tachometer RPM. It must not estimate speed
from a curve level.

## Boundaries

These edits expose bounded WMI transport only. They do not create named fan
modes, save a curve, restore a preference, change `platform_profile`, or change
TDP or power limits. The external module replacement remains experimental.

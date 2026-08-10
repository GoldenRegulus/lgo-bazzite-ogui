# HID kernel change record

This record lists project edits to `hid-lenovo-go.c` relative to the selected
OGC5 source. It does not describe unchanged upstream code.

## 1. Correlate synchronous replies

**Edit:** Arm a request before output, then complete it only when the input
reply has the same command and sub-command.

**Reason:** Unrelated input reports must not complete a waiting request.

**Limit:** Firmware has no sequence token. A late reply with the same command
and sub-command remains ambiguous.

## 2. Keep calibration asynchronous

**Edit:** A calibration sysfs write sends one HID report and returns the
transport result. Completion reports update per-control result and error state.

**Reason:** Firmware calibration can complete after the transport request. A
kernel timeout, retry, or cancellation policy would be user workflow policy.

**Limit:** The kernel does not wait for calibration completion or retry a
request. Userspace reads completion state and owns workflow decisions.

## 3. Expose per-control completion state

**Edit:** Decode Lenovo calibration completion reports and expose result and
firmware-error readback for each supported controller control.

**Reason:** The backend must show firmware state instead of guessing from a
submitted request.

## 4. Correct calibration selectors and input bounds

**Edit:** Correct the right-controller IMU-enable and reset selectors. Reject
unknown writable text while preserving the valid zero auto-sleep value.

**Reason:** A selector must address the intended firmware control. Sysfs input
must have a defined accepted set.

## 5. Clean up LED ownership on removal

**Edit:** Drain and release LED-related state during driver removal.

**Reason:** Linux must not leave a controller LED class device owned by a
removed HID driver.

## Boundaries

These edits do not route controller input, change InputPlumber, add an OGUI
policy interface, or implement calibration retries and deadlines.

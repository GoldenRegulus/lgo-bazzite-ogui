extends RefCounted

const HID_DEVICES_PATH := "/sys/bus/hid/devices"
const LEGION_CONTROLLER_IDS := [
  "HID_ID=0003:000017EF:000061EB",
  "HID_ID=0003:000017EF:000061EC",
  "HID_ID=0003:000017EF:000061ED",
  "HID_ID=0003:000017EF:000061EE",
]
const SIDES := ["left", "right"]
const CALIBRATION_KINDS := ["joystick", "trigger", "gyro"]


func read_state() -> Dictionary:
  var controller_path := _find_controller_path()
  if controller_path.is_empty():
    return {
      "ok": false,
      "message": "A single supported Legion controller interface was not found.",
    }

  var calibrations := {}
  for side in SIDES:
    var side_state := {}
    for kind in CALIBRATION_KINDS:
      var base := "%s/%s_handle/calibrate_%s" % [controller_path, side, kind]
      side_state[kind] = {
        "status": _read_value(base + "_status", "unavailable"),
        "error": _read_value(base + "_error", "unavailable"),
        "actions": _read_value(base + "_index", "unavailable"),
      }
    calibrations[side] = side_state

  return {
    "ok": true,
    "controller": _read_hid_name(controller_path),
    "left_generation": _read_value(
      controller_path + "/left_handle/hardware_generation",
      "unavailable"
    ),
    "right_generation": _read_value(
      controller_path + "/right_handle/hardware_generation",
      "unavailable"
    ),
    "calibrations": calibrations,
    "fps_mode": _read_value(controller_path + "/fps_switch_status", "unavailable"),
    "fps_dpi": _read_value(controller_path + "/fps_mode_dpi", "unavailable"),
    "fps_dpi_options": _read_value(
      controller_path + "/fps_mode_dpi_index",
      "unavailable"
    ),
  }


func _find_controller_path() -> String:
  var directory := DirAccess.open(HID_DEVICES_PATH)
  if directory == null:
    return ""

  var matches: Array[String] = []
  directory.list_dir_begin()
  var entry := directory.get_next()
  while not entry.is_empty():
    var path := HID_DEVICES_PATH + "/" + entry
    if _is_supported_controller(path):
      matches.append(path)
    entry = directory.get_next()
  directory.list_dir_end()

  if matches.size() != 1:
    return ""
  return matches[0]


func _is_supported_controller(path: String) -> bool:
  if not DirAccess.dir_exists_absolute(path + "/left_handle"):
    return false
  if not DirAccess.dir_exists_absolute(path + "/right_handle"):
    return false
  var uevent := _read_value(path + "/uevent", "")
  for line in uevent.split("\n"):
    if line.strip_edges() in LEGION_CONTROLLER_IDS:
      return true
  return false


func _read_hid_name(controller_path: String) -> String:
  var uevent := _read_value(controller_path + "/uevent", "")
  for line in uevent.split("\n"):
    if line.begins_with("HID_NAME="):
      return line.trim_prefix("HID_NAME=").strip_edges()
  return "Legion Controller"


func _read_value(path: String, fallback: String) -> String:
  var file := FileAccess.open(path, FileAccess.READ)
  if file == null:
    return fallback
  var value := file.get_as_text().strip_edges()
  if value.is_empty():
    return fallback
  return value

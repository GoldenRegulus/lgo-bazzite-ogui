extends VBoxContainer

signal open_requested(tree: SceneTree)

const CARD_BUTTON_PATH := "res://core/ui/components/card_button.tscn"
const BASH_PATH := "/usr/bin/bash"
const HELPER_PATH := "/var/usrlocal/libexec/legion-go-ogui-helper"
const PLUGIN_USER_PATH := "user://plugins/legion-go/plugins/legion-go"

var card_button_scene := load(CARD_BUTTON_PATH) as PackedScene
var open_button: CardButton
var install_button: CardButton
var remove_button: CardButton
var action_status: Label
var backend_busy := false


func _init() -> void:
  size_flags_horizontal = Control.SIZE_EXPAND_FILL
  open_button = card_button_scene.instantiate() as CardButton
  open_button.text = "Open"
  open_button.focus_mode = Control.FOCUS_ALL
  open_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  open_button.pressed.connect(_on_open_pressed)
  add_child(open_button)

  install_button = _new_button(
    "Update backend" if FileAccess.file_exists(HELPER_PATH) else "Install backend"
  )
  install_button.pressed.connect(_schedule_backend_action.bind("install"))
  add_child(install_button)

  remove_button = _new_button("Remove backend")
  remove_button.visible = FileAccess.file_exists(HELPER_PATH)
  remove_button.focus_mode = (
    Control.FOCUS_ALL if remove_button.visible else Control.FOCUS_NONE
  )
  remove_button.pressed.connect(_schedule_backend_action.bind("uninstall"))
  add_child(remove_button)

  action_status = Label.new()
  action_status.focus_mode = Control.FOCUS_NONE
  action_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  add_child(action_status)


func _new_button(text: String) -> CardButton:
  var button := card_button_scene.instantiate() as CardButton
  button.text = text
  button.focus_mode = Control.FOCUS_ALL
  button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  return button


func _on_open_pressed() -> void:
  open_requested.emit(get_tree())


func _schedule_backend_action(action: String) -> void:
  if backend_busy:
    return
  var script_name := (
    "schedule-desktop-install.sh"
    if action == "install"
    else "schedule-desktop-uninstall.sh"
  )
  var script_path := ProjectSettings.globalize_path(
    "%s/backend/%s" % [PLUGIN_USER_PATH, script_name]
  )
  if not FileAccess.file_exists(script_path):
    action_status.text = "Backend action is unavailable."
    return

  backend_busy = true
  action_status.text = "Opening Desktop Mode…"
  var command := Command.create(BASH_PATH, [script_path])
  command.timeout = 10.0
  if command.execute() != OK:
    backend_busy = false
    action_status.text = "Could not start the backend action."
    return

  var exit_code := await command.finished as int
  if not is_inside_tree():
    return
  backend_busy = false
  if exit_code != 0:
    action_status.text = "Could not schedule the backend action."

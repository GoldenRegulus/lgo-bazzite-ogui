extends Plugin

const MENU_STATE_MACHINE_PATH := "res://assets/state/state_machines/menu_state_machine.tres"

var settings_launcher: Control
var fullscreen_menu: Control
var fullscreen_state: State
var state_machine := load(MENU_STATE_MACHINE_PATH) as StateMachine


func _ensure_fullscreen_state() -> void:
  if fullscreen_state != null:
    return
  fullscreen_state = State.new()
  fullscreen_state.name = "legion_go"
  fullscreen_state.state_entered.connect(_on_fullscreen_state_entered)
  fullscreen_state.state_exited.connect(_on_fullscreen_state_exited)


func get_settings_menu() -> Control:
  _ensure_fullscreen_state()
  if is_instance_valid(settings_launcher):
    return settings_launcher

  var launcher_script := load(plugin_base + "/core/settings_launcher.gd") as Script
  if launcher_script == null:
    logger.error("Unable to load the Legion Go settings launcher")
    return null
  settings_launcher = launcher_script.new() as Control
  settings_launcher.connect("open_requested", _on_open_requested)
  return settings_launcher


func _attach_fullscreen_menu(tree: SceneTree) -> void:
  if is_instance_valid(fullscreen_menu):
    return
  var main := tree.get_first_node_in_group("main") as Control
  if main == null:
    logger.error("Unable to find the OGUI main node")
    return
  var menu_script := load(plugin_base + "/core/settings_menu.gd") as Script
  if menu_script == null:
    logger.error("Unable to load the Legion Go full-screen menu")
    return
  fullscreen_menu = menu_script.new() as Control
  fullscreen_menu.hide()
  fullscreen_menu.connect("close_requested", _close_fullscreen_menu)
  main.add_child(fullscreen_menu)
  fullscreen_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _on_open_requested(tree: SceneTree) -> void:
  _ensure_fullscreen_state()
  _attach_fullscreen_menu(tree)
  if not is_instance_valid(fullscreen_menu):
    return
  state_machine.push_state(fullscreen_state)


func _on_fullscreen_state_entered(_from: State) -> void:
  if not is_instance_valid(fullscreen_menu):
    return
  fullscreen_menu.show()
  fullscreen_menu.call("activate")


func _on_fullscreen_state_exited(_to: State) -> void:
  if is_instance_valid(fullscreen_menu):
    fullscreen_menu.hide()


func _close_fullscreen_menu() -> void:
  if state_machine.current_state() == fullscreen_state:
    state_machine.pop_state()
    return
  state_machine.remove_state(fullscreen_state)


func unload() -> void:
  if state_machine != null and fullscreen_state != null:
    state_machine.remove_state(fullscreen_state)
  if is_instance_valid(fullscreen_menu):
    fullscreen_menu.queue_free()
    fullscreen_menu = null
  if is_instance_valid(settings_launcher):
    settings_launcher.queue_free()
    settings_launcher = null
  logger.info("Legion Go plugin unloaded")

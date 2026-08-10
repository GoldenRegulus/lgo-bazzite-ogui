extends Control

signal close_requested

const TABS_HEADER_PATH := "res://core/ui/components/tabs_header.tscn"
const SELECTABLE_TEXT_PATH := "res://core/ui/components/text.tscn"
const CARD_BUTTON_PATH := "res://core/ui/components/card_button.tscn"
const TOGGLE_PATH := "res://core/ui/components/toggle.tscn"
const SLIDER_PATH := "res://core/ui/components/slider.tscn"
const CONTROLLER_INVENTORY_PATH := "res://plugins/legion-go/core/controller_inventory.gd"
const HELPER_PATH := "/var/usrlocal/libexec/legion-go-ogui-helper"
const CONTROLLER_HELPER_PATH := "/var/usrlocal/libexec/legion-go-ogui-controller"
const FAN_HELPER_PATH := "/var/usrlocal/libexec/legion-go-ogui-fan"
const PKEXEC_PATH := "/usr/bin/pkexec"
const FAN_MIN_LEVEL := 0
const FAN_MAX_LEVEL := 125
const FAN_HARD_MIN: Array[int] = [0, 0, 0, 0, 0, 0, 0, 79, 79, 100]
const FAN_RECOMMENDED_MIN: Array[int] = [44, 44, 44, 55, 60, 71, 79, 79, 79, 100]
const FAN_RECOMMENDED_MAX: Array[int] = [55, 55, 55, 60, 71, 87, 100, 100, 100, 100]
const FAN_AUTOMATIC_CURVE: Array[int] = [44, 44, 55, 60, 71, 87, 100, 100, 100, 100]
const FAN_QUIET_CURVE: Array[int] = [44, 48, 48, 48, 48, 48, 48, 48, 48, 48]
const FAN_BALANCED_CURVE: Array[int] = [44, 48, 55, 60, 60, 60, 60, 60, 60, 60]
const FAN_PERFORMANCE_CURVE: Array[int] = [44, 48, 55, 60, 71, 79, 87, 87, 100, 100]
const FAN_UI_MODE_NAMES: Array[String] = ["Quiet", "Balanced", "Performance", "Custom"]
const DIRECTION_ACTIONS: Array[String] = ["ui_up", "ui_down", "ui_left", "ui_right"]
const DIRECTION_REPEAT_DELAY := 0.4
const DIRECTION_REPEAT_INTERVAL := 0.09

var tabs_header_scene := load(TABS_HEADER_PATH) as PackedScene
var selectable_text_scene := load(SELECTABLE_TEXT_PATH) as PackedScene
var card_button_scene := load(CARD_BUTTON_PATH) as PackedScene
var toggle_scene := load(TOGGLE_PATH) as PackedScene
var slider_scene := load(SLIDER_PATH) as PackedScene
var controller_inventory = load(CONTROLLER_INVENTORY_PATH).new()

var charge_status_row: SelectableText
var battery_message_row: SelectableText
var charge_toggle: Toggle

var fan_status_row: SelectableText
var fan_message_row: SelectableText
var fan_mode_buttons: Array[CardButton] = []
var fan_full_speed_toggle: Toggle
var fan_curve_sliders: Array[ValueSlider] = []
var fan_apply_custom_button: CardButton
var fan_mode_container: HBoxContainer
var calibration_container: HFlowContainer

var controller_status_row: SelectableText
var controller_control_message_row: SelectableText
var fps_status_row: SelectableText
var left_calibration_row: SelectableText
var right_calibration_row: SelectableText
var controller_message_row: SelectableText
var button_swap_toggle: Toggle
var calibration_buttons: Array[CardButton] = []
var calibration_button_actions: Array[Dictionary] = []
var calibration_action_supported := {}
var calibration_cancel_button: CardButton

var refresh_timer: Timer
var fan_refresh_timer: Timer
var calibration_timer: Timer
var direction_repeat_timer: Timer
var direction_repeat_action := ""
var input_manager: Node
var battery_busy := false
var battery_ready := false
var battery_syncing := false
var controller_busy := false
var controller_ready := false
var controller_syncing := false
var controller_inventory_available := false
var calibration_supported := false
var active_calibration_side := ""
var active_calibration_kind := ""
var fan_busy := false
var fan_ready := false
var fan_syncing := false
var fan_firmware_curve: Array[int] = []
var fan_custom_curve: Array[int] = []
var fan_custom_selected := false
var fan_full_speed_enabled := false
var tabs_state := TabContainerState.new()
var focus_stack := FocusStack.new()
var tab_container: TabContainer
var tab_focus_groups: Array[FocusGroup] = []
var current_content: VBoxContainer


func _ready() -> void:
  set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
  input_manager = get_tree().get_first_node_in_group("input_manager")
  tabs_state.tabs_text = PackedStringArray(["Battery", "Cooling", "Controllers"])
  _build_menu()
  tabs_state.tab_changed.connect(_on_tab_changed)
  visibility_changed.connect(_on_visibility_changed)
  _refresh_all()


func activate() -> void:
  _on_tab_changed(tabs_state.current_tab)


func _unhandled_input(event: InputEvent) -> void:
  if not is_visible_in_tree() or not event.is_action_released("ogui_east"):
    return
  get_viewport().set_input_as_handled()
  close_requested.emit()


func _build_menu() -> void:
  var background := ColorRect.new()
  background.color = Color("10151d")
  background.mouse_filter = Control.MOUSE_FILTER_IGNORE
  add_child(background)
  background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

  var layout := VBoxContainer.new()
  layout.add_theme_constant_override("separation", 8)
  add_child(layout)
  layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

  var tabs_header := tabs_header_scene.instantiate() as TabsHeader
  tabs_header.tabs_state = tabs_state
  layout.add_child(tabs_header)

  tab_container = TabContainer.new()
  tab_container.tabs_visible = false
  tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
  layout.add_child(tab_container)
  for tab_name in tabs_state.tabs_text:
    _add_tab(tab_name)

  current_content = _tab_content(0)
  charge_status_row = _add_status_row("Charge", "Checking…")
  charge_toggle = toggle_scene.instantiate() as Toggle
  _prepare_control(charge_toggle)
  charge_toggle.text = "80% limit"
  charge_toggle.description = "Off: 100%"
  charge_toggle.disabled = true
  _set_focusable(charge_toggle, false)
  charge_toggle.toggled.connect(_on_charge_toggled)
  current_content.add_child(charge_toggle)
  battery_message_row = _add_message_row()

  current_content = _tab_content(1)
  fan_status_row = _add_status_row("RPM", "Checking…")
  fan_full_speed_toggle = toggle_scene.instantiate() as Toggle
  _prepare_control(fan_full_speed_toggle)
  fan_full_speed_toggle.text = "Full Speed"
  fan_full_speed_toggle.description = "Maximum RPM"
  fan_full_speed_toggle.disabled = true
  _set_focusable(fan_full_speed_toggle, false)
  fan_full_speed_toggle.toggled.connect(_on_fan_full_speed_toggled)
  current_content.add_child(fan_full_speed_toggle)
  fan_mode_container = HBoxContainer.new()
  fan_mode_container.focus_mode = Control.FOCUS_NONE
  fan_mode_container.add_theme_constant_override("separation", 8)
  current_content.add_child(fan_mode_container)
  for mode_name in FAN_UI_MODE_NAMES:
    var mode_button := _new_compact_button(mode_name)
    mode_button.disabled = true
    _set_focusable(mode_button, false)
    mode_button.pressed.connect(_on_fan_mode_pressed.bind(mode_name))
    fan_mode_container.add_child(mode_button)
    fan_mode_buttons.append(mode_button)
  fan_mode_container.focus_entered.connect(
    _focus_first_enabled.bind(fan_mode_buttons)
  )
  for index in range(10):
    var curve_slider := slider_scene.instantiate() as ValueSlider
    _prepare_control(curve_slider)
    curve_slider.text = "%d °C" % ((index + 1) * 10)
    curve_slider.min_value = FAN_HARD_MIN[index]
    curve_slider.max_value = FAN_MAX_LEVEL
    curve_slider.step = 1
    curve_slider.value = FAN_RECOMMENDED_MIN[index]
    curve_slider.editable = false
    _set_focusable(curve_slider, false)
    curve_slider.value_changed.connect(_on_fan_curve_value_changed.bind(index))
    current_content.add_child(curve_slider)
    fan_curve_sliders.append(curve_slider)
  fan_apply_custom_button = _new_button("Apply")
  fan_apply_custom_button.disabled = true
  _set_focusable(fan_apply_custom_button, false)
  fan_apply_custom_button.pressed.connect(_on_apply_custom_curve)
  current_content.add_child(fan_apply_custom_button)
  fan_message_row = _add_message_row()

  current_content = _tab_content(2)
  controller_status_row = _add_status_row("Connected", "Checking…")
  fps_status_row = _add_status_row("FPS mode", "")
  fps_status_row.visible = false
  button_swap_toggle = toggle_scene.instantiate() as Toggle
  _prepare_control(button_swap_toggle)
  button_swap_toggle.text = "Menu / View swap"
  button_swap_toggle.description = "Saved request; firmware readback is unavailable"
  button_swap_toggle.disabled = true
  _set_focusable(button_swap_toggle, false)
  button_swap_toggle.toggled.connect(_on_button_swap_toggled)
  current_content.add_child(button_swap_toggle)
  controller_control_message_row = _add_message_row()

  var calibrate_heading := Label.new()
  calibrate_heading.text = "Calibrate"
  calibrate_heading.focus_mode = Control.FOCUS_NONE
  current_content.add_child(calibrate_heading)
  calibration_container = HFlowContainer.new()
  calibration_container.focus_mode = Control.FOCUS_NONE
  calibration_container.add_theme_constant_override("h_separation", 8)
  calibration_container.add_theme_constant_override("v_separation", 8)
  current_content.add_child(calibration_container)
  for action in _controller_calibration_actions():
    var calibration_button := _new_compact_button(str(action["label"]))
    calibration_button.disabled = true
    _set_focusable(calibration_button, false)
    calibration_button.pressed.connect(
      _on_calibration_start_requested.bind(
        str(action["side"]),
        str(action["kind"]),
        calibration_button
      )
    )
    calibration_container.add_child(calibration_button)
    calibration_buttons.append(calibration_button)
    calibration_button_actions.append(action)
  calibration_container.focus_entered.connect(
    _focus_first_enabled.bind(calibration_buttons)
  )
  calibration_cancel_button = _new_button("Cancel calibration")
  calibration_cancel_button.visible = false
  calibration_cancel_button.disabled = true
  _set_focusable(calibration_cancel_button, false)
  calibration_cancel_button.pressed.connect(_on_calibration_cancel_requested)
  current_content.add_child(calibration_cancel_button)
  left_calibration_row = _add_status_row("Left calibration", "")
  left_calibration_row.visible = false
  right_calibration_row = _add_status_row("Right calibration", "")
  right_calibration_row.visible = false
  controller_message_row = _add_message_row()

  refresh_timer = Timer.new()
  refresh_timer.wait_time = 60.0
  refresh_timer.autostart = true
  refresh_timer.timeout.connect(_refresh_all)
  add_child(refresh_timer)
  fan_refresh_timer = Timer.new()
  fan_refresh_timer.wait_time = 5.0
  fan_refresh_timer.autostart = true
  fan_refresh_timer.timeout.connect(_refresh_fan)
  add_child(fan_refresh_timer)
  calibration_timer = Timer.new()
  calibration_timer.wait_time = 1.0
  calibration_timer.timeout.connect(_refresh_controller_inventory)
  add_child(calibration_timer)
  direction_repeat_timer = Timer.new()
  direction_repeat_timer.one_shot = true
  direction_repeat_timer.timeout.connect(_repeat_direction)
  add_child(direction_repeat_timer)


func _process(_delta: float) -> void:
  if not is_visible_in_tree() or input_manager == null:
    return
  var held_action := ""
  for action in DIRECTION_ACTIONS:
    if bool(input_manager.call("is_action_pressed", action)):
      held_action = action
      break
  if held_action == direction_repeat_action:
    return
  direction_repeat_action = held_action
  direction_repeat_timer.stop()
  if not direction_repeat_action.is_empty():
    direction_repeat_timer.start(DIRECTION_REPEAT_DELAY)


func _repeat_direction() -> void:
  if direction_repeat_action.is_empty() or not is_visible_in_tree():
    return
  var release_event := InputEventAction.new()
  release_event.action = direction_repeat_action
  release_event.pressed = false
  release_event.strength = 0.0
  release_event.set_meta("legion_go_repeat", true)
  Input.parse_input_event(release_event)

  var press_event := InputEventAction.new()
  press_event.action = direction_repeat_action
  press_event.pressed = true
  press_event.strength = 1.0
  press_event.set_meta("legion_go_repeat", true)
  Input.parse_input_event(press_event)
  direction_repeat_timer.start(DIRECTION_REPEAT_INTERVAL)


func _add_tab(tab_name: String) -> void:
  var scroll := ScrollContainer.new()
  scroll.name = tab_name
  scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
  scroll.follow_focus = true
  tab_container.add_child(scroll)
  var margin := MarginContainer.new()
  margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  margin.add_theme_constant_override("margin_left", 32)
  margin.add_theme_constant_override("margin_top", 24)
  margin.add_theme_constant_override("margin_right", 32)
  margin.add_theme_constant_override("margin_bottom", 32)
  scroll.add_child(margin)
  var content := VBoxContainer.new()
  content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  content.add_theme_constant_override("separation", 8)
  margin.add_child(content)
  var focus_group := FocusGroup.new()
  focus_group.name = "FocusGroup"
  focus_group.focus_stack = focus_stack
  focus_group.wrap_focus = false
  content.add_child(focus_group)
  tab_focus_groups.append(focus_group)


func _tab_content(index: int) -> VBoxContainer:
  var scroll := tab_container.get_child(index) as ScrollContainer
  var margin := scroll.get_child(0) as MarginContainer
  return margin.get_child(0) as VBoxContainer


func _on_tab_changed(index: int) -> void:
  if not is_instance_valid(tab_container) or index < 0 or index >= tab_focus_groups.size():
    return
  tab_container.current_tab = index
  focus_stack.clear()
  tab_focus_groups[index].current_focus = null
  _repair_focus_group.call_deferred(tab_focus_groups[index])
  if index == 0 and battery_ready:
    charge_toggle.grab_focus.call_deferred()


func _add_status_row(title: String, value: String) -> SelectableText:
  var row := _add_selectable_row(title, value, "")
  _set_focusable(row, false)
  return row


func _add_message_row() -> SelectableText:
  var row := _add_status_row("", "")
  row.visible = false
  return row


func _show_message(row: SelectableText, text: String) -> void:
  row.text = text
  row.visible = not text.is_empty()


func _new_button(text: String) -> CardButton:
  var button := card_button_scene.instantiate() as CardButton
  button.text = text
  button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
  button.custom_minimum_size = Vector2(0, 48)
  button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  _prepare_control(button)
  return button


func _new_compact_button(text: String) -> CardButton:
  var button := _new_button(text)
  button.custom_minimum_size = Vector2(144, 44)
  button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
  return button


func _set_focusable(control: Control, enabled: bool) -> void:
  var desired_mode := Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
  var changed := control.focus_mode != desired_mode
  if changed:
    control.focus_mode = desired_mode
    _disable_descendant_focus(control)

  if control is ValueSlider:
    var native_slider := control.get_node_or_null("%HSlider") as HSlider
    if native_slider != null and native_slider.focus_mode != desired_mode:
      native_slider.focus_mode = desired_mode
      changed = true

  if not changed:
    return
  for focus_group in tab_focus_groups:
    _repair_focus_group.call_deferred(focus_group)


func _repair_focus_group(focus_group: FocusGroup) -> void:
  focus_group.recalculate_focus()
  _assign_compact_focus_neighbors()
  _sync_slider_focus_neighbors()
  var current := focus_group.current_focus
  if (
    is_instance_valid(current)
    and current.focus_mode == Control.FOCUS_ALL
    and current.is_visible_in_tree()
  ):
    return
  focus_group.current_focus = FocusGroup.find_focusable(
    focus_group.get_parent().get_children(),
    focus_group.get_parent()
  ) as Control
  var index := tab_focus_groups.find(focus_group)
  if index == tabs_state.current_tab and is_visible_in_tree():
    focus_group.grab_focus()


func _assign_compact_focus_neighbors() -> void:
  _assign_horizontal_focus_neighbors(fan_mode_buttons, fan_mode_container)
  _assign_horizontal_focus_neighbors(calibration_buttons, calibration_container)


func _assign_horizontal_focus_neighbors(
  buttons: Array[CardButton],
  container: Container
) -> void:
  var enabled_buttons: Array[CardButton] = []
  for button in buttons:
    button.focus_neighbor_left = NodePath()
    button.focus_neighbor_right = NodePath()
    if button.disabled or button.focus_mode != Control.FOCUS_ALL:
      continue
    if button.is_visible_in_tree():
      enabled_buttons.append(button)

  for index in range(enabled_buttons.size()):
    var button := enabled_buttons[index]
    var left_index := (index - 1 + enabled_buttons.size()) % enabled_buttons.size()
    var right_index := (index + 1) % enabled_buttons.size()
    button.focus_neighbor_top = container.focus_neighbor_top
    button.focus_neighbor_bottom = container.focus_neighbor_bottom
    button.focus_neighbor_left = button.get_path_to(enabled_buttons[left_index])
    button.focus_neighbor_right = button.get_path_to(enabled_buttons[right_index])


func _sync_slider_focus_neighbors() -> void:
  for curve_slider in fan_curve_sliders:
    var native_slider := curve_slider.get_node_or_null("%HSlider") as HSlider
    if native_slider == null:
      continue
    native_slider.focus_neighbor_top = curve_slider.focus_neighbor_top
    native_slider.focus_neighbor_bottom = curve_slider.focus_neighbor_bottom
    native_slider.focus_neighbor_left = curve_slider.focus_neighbor_left
    native_slider.focus_neighbor_right = curve_slider.focus_neighbor_right
    native_slider.focus_previous = curve_slider.focus_previous
    native_slider.focus_next = curve_slider.focus_next


func _focus_first_enabled(buttons: Array[CardButton]) -> void:
  for button in buttons:
    if not button.disabled and button.focus_mode == Control.FOCUS_ALL:
      button.grab_focus.call_deferred()
      return


func _set_focus_container_enabled(container: Container, enabled: bool) -> void:
  var desired_mode := Control.FOCUS_ALL if enabled else Control.FOCUS_NONE
  if container.focus_mode == desired_mode:
    return
  container.focus_mode = desired_mode
  for focus_group in tab_focus_groups:
    _repair_focus_group.call_deferred(focus_group)


func _disable_descendant_focus(node: Node) -> void:
  for child in node.get_children():
    if child is Control:
      (child as Control).focus_mode = Control.FOCUS_NONE
    _disable_descendant_focus(child)


func _prepare_control(control: Control) -> void:
  control.custom_minimum_size.x = 0
  var title_label := control.get_node_or_null("%Label") as Label
  if title_label != null:
    title_label.custom_minimum_size.x = 0
    title_label.autowrap_mode = TextServer.AUTOWRAP_OFF

  for node_name in ["%LabelValue", "%DescriptionLabel"]:
    var label := control.get_node_or_null(node_name) as Label
    if label == null:
      continue
    label.custom_minimum_size.x = 100
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


func _add_selectable_row(title: String, value: String, description: String) -> SelectableText:
  var row := selectable_text_scene.instantiate() as SelectableText
  _prepare_control(row)
  row.title = title
  row.text = value
  row.description = description
  row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
  current_content.add_child(row)
  return row


func _refresh_all() -> void:
  _refresh_battery()
  _refresh_controller_inventory()
  _refresh_fan()


func _on_visibility_changed() -> void:
  if is_visible_in_tree():
    _refresh_all()
    return
  direction_repeat_action = ""
  if is_instance_valid(direction_repeat_timer):
    direction_repeat_timer.stop()


func _refresh_battery() -> void:
  if battery_busy or not is_visible_in_tree():
    return
  if not FileAccess.file_exists(HELPER_PATH):
    _show_backend_missing()
    return

  battery_busy = true
  if not battery_ready:
    _set_charge_busy(true)
  var result := await _run_battery_helper("status", false)
  if not is_inside_tree():
    return
  battery_busy = false
  _apply_battery_result(result)


func _on_charge_toggled(enabled: bool) -> void:
  if battery_busy or battery_syncing:
    return

  battery_busy = true
  charge_status_row.visible = true
  charge_status_row.text = "Applying…"
  _show_message(
    battery_message_row,
    "Setting 80%…" if enabled else "Setting 100%…"
  )
  var command_name := "enable" if enabled else "disable"
  var result := await _run_battery_helper(command_name, true)
  if not is_inside_tree():
    return

  if bool(result.get("ok", false)):
    battery_busy = false
    _apply_battery_result(result)
    return

  _show_message(
    battery_message_row,
    "Could not change charging mode: %s" % str(result.get("message", "Request failed."))
  )
  var confirmed_result := await _run_battery_helper("status", false)
  if not is_inside_tree():
    return
  battery_busy = false
  _apply_battery_result(confirmed_result, false)


func _run_battery_helper(command_name: String, privileged: bool) -> Dictionary:
  var executable := HELPER_PATH
  var arguments: Array[String] = [command_name]
  if privileged:
    executable = PKEXEC_PATH
    arguments = [HELPER_PATH, command_name]
  return await _run_json_command(executable, arguments, 15.0, "battery")


func _apply_battery_result(result: Dictionary, clear_message := true) -> void:
  var ok := bool(result.get("ok", false))
  var threshold := int(result.get("threshold", -1))
  var mode := str(result.get("mode", ""))
  battery_syncing = true

  if ok and threshold == 80 and mode == "long-life":
    battery_ready = true
    charge_status_row.visible = false
    charge_status_row.text = "80%"
    charge_toggle.button_pressed = true
    _set_charge_busy(false)
    if tabs_state.current_tab == 0 and is_visible_in_tree():
      charge_toggle.grab_focus.call_deferred()
    if clear_message:
      _show_message(battery_message_row, "")
    battery_syncing = false
    return

  if ok and threshold == 100 and mode == "standard":
    battery_ready = true
    charge_status_row.visible = false
    charge_status_row.text = "100%"
    charge_toggle.button_pressed = false
    _set_charge_busy(false)
    if tabs_state.current_tab == 0 and is_visible_in_tree():
      charge_toggle.grab_focus.call_deferred()
    if clear_message:
      _show_message(battery_message_row, "")
    battery_syncing = false
    return

  battery_ready = false
  charge_status_row.visible = true
  charge_status_row.text = "Unavailable"
  charge_toggle.disabled = true
  _set_focusable(charge_toggle, false)
  _show_message(
    battery_message_row,
    "%s Use Update backend in the plugin menu." % str(
      result.get("message", "Battery charging control is unavailable.")
    )
  )
  battery_syncing = false


func _show_backend_missing() -> void:
  battery_ready = false
  charge_status_row.visible = true
  charge_status_row.text = "Setup required"
  battery_syncing = true
  charge_toggle.button_pressed = false
  battery_syncing = false
  charge_toggle.disabled = true
  _set_focusable(charge_toggle, false)
  _show_message(
    battery_message_row,
    "Use Install backend in the plugin menu."
  )


func _set_charge_busy(busy: bool) -> void:
  charge_toggle.disabled = busy
  _set_focusable(charge_toggle, not busy)


func _controller_calibration_actions() -> Array[Dictionary]:
  return [
    {
      "label": "Left stick",
      "side": "left",
      "kind": "joystick",
    },
    {
      "label": "Left trigger",
      "side": "left",
      "kind": "trigger",
    },
    {
      "label": "Left gyro",
      "side": "left",
      "kind": "gyro",
    },
    {
      "label": "Right stick",
      "side": "right",
      "kind": "joystick",
    },
    {
      "label": "Right trigger",
      "side": "right",
      "kind": "trigger",
    },
    {
      "label": "Right gyro",
      "side": "right",
      "kind": "gyro",
    },
  ]


func _refresh_controller_inventory() -> void:
  var inventory_state: Dictionary = controller_inventory.read_state()
  controller_inventory_available = bool(inventory_state.get("ok", false))
  _apply_controller_inventory(inventory_state)

  if controller_busy:
    return
  if not FileAccess.file_exists(CONTROLLER_HELPER_PATH):
    controller_ready = false
    _show_message(controller_control_message_row, "Controller controls unavailable.")
    _show_message(
      controller_message_row,
      "Calibration needs the current controller helper and project HID driver. "
      + "Use Update backend in the plugin menu."
    )
    _set_controller_controls_enabled(false)
    return

  controller_busy = true
  if not controller_ready:
    _set_controller_controls_enabled(false)
  var backend_state := await _run_controller_helper("status", false)
  if not is_inside_tree():
    return
  controller_busy = false
  _apply_controller_status(backend_state)


func _apply_controller_inventory(state: Dictionary) -> void:
  if not bool(state.get("ok", false)):
    controller_status_row.text = "Waiting for Legion controllers"
    fps_status_row.visible = false
    return

  var left := _generation_name(str(state.get("left_generation", "")))
  var right := _generation_name(str(state.get("right_generation", "")))
  if left.is_empty() and right.is_empty():
    controller_status_row.text = "Legion Go Controller"
  else:
    controller_status_row.text = "Left: %s  •  Right: %s" % [
      left if not left.is_empty() else "Not detected",
      right if not right.is_empty() else "Not detected",
    ]

  var fps_mode := str(state.get("fps_mode", "")).strip_edges()
  var fps_dpi := str(state.get("fps_dpi", "")).strip_edges()
  if _is_available_value(fps_mode):
    var mode_text := _fps_mode_name(fps_mode)
    fps_status_row.text = mode_text
    if _is_available_value(fps_dpi):
      fps_status_row.text += " • %s DPI" % fps_dpi
    fps_status_row.visible = true
  else:
    fps_status_row.visible = false

  _apply_calibration_rows(state.get("calibrations", {}) as Dictionary)


func _generation_name(value: String) -> String:
  match value.strip_edges():
    "1":
      return "Original"
    "2":
      return "Legion Go 2"
    "", "unknown", "unavailable":
      return ""
    _:
      return "Generation %s" % value


func _fps_mode_name(value: String) -> String:
  match value.to_lower():
    "0", "off", "disabled":
      return "Off"
    "1", "on", "enabled":
      return "On"
    _:
      return value.capitalize()


func _is_available_value(value: String) -> bool:
  return not value.is_empty() and value.to_lower() not in ["unknown", "unavailable"]


func _apply_controller_status(state: Dictionary) -> void:
  if not bool(state.get("ok", false)):
    controller_ready = false
    _show_message(controller_control_message_row, "Controller controls unavailable.")
    _show_message(
      controller_message_row,
      "Calibration needs the current controller helper and project HID driver. "
      + "Use Update backend in the plugin menu."
    )
    _set_controller_controls_enabled(false)
    return

  controller_ready = true
  if not controller_inventory_available:
    controller_status_row.text = "Legion Go Controller"
  _show_message(controller_control_message_row, "")
  var swap_requested := str(state.get("swap_requested", ""))
  controller_syncing = true
  button_swap_toggle.button_pressed = swap_requested == "enabled"
  controller_syncing = false
  calibration_supported = _update_calibration_support(state)
  _apply_calibration_rows(_calibrations_from_flat_state(state))
  var had_active_calibration := not active_calibration_side.is_empty()
  _update_active_calibration(state)
  if calibration_supported:
    if not had_active_calibration and active_calibration_side.is_empty():
      _show_message(controller_message_row, "")
  else:
    _show_message(
      controller_message_row,
      "Calibration needs the project HID driver for this kernel. "
      + "Use Update backend in the plugin menu."
    )
  _set_controller_controls_enabled(true)


func _update_calibration_support(state: Dictionary) -> bool:
  calibration_action_supported.clear()
  var all_supported := true
  for action in _controller_calibration_actions():
    var side := str(action["side"])
    var kind := str(action["kind"])
    var error := str(state.get("%s_%s_error" % [side, kind], "unknown"))
    var actions := str(state.get("%s_%s_index" % [side, kind], ""))
    var supported := (
      error not in ["unknown", "unavailable"]
      and actions.split(" ").has("start")
      and actions.split(" ").has("stop")
    )
    calibration_action_supported["%s_%s" % [side, kind]] = supported
    if not supported:
      all_supported = false
  return all_supported


func _is_calibration_action_supported(side: String, kind: String) -> bool:
  return bool(calibration_action_supported.get("%s_%s" % [side, kind], false))


func _calibrations_from_flat_state(state: Dictionary) -> Dictionary:
  var calibrations := {}
  for side in ["left", "right"]:
    var side_state := {}
    for kind in ["joystick", "trigger", "gyro"]:
      side_state[kind] = {
        "status": state.get("%s_%s_status" % [side, kind], "unknown"),
        "error": state.get("%s_%s_error" % [side, kind], "0x0000"),
      }
    calibrations[side] = side_state
  return calibrations


func _apply_calibration_rows(calibrations: Dictionary) -> void:
  _apply_calibration_row(
    left_calibration_row,
    calibrations.get("left", {}) as Dictionary
  )
  _apply_calibration_row(
    right_calibration_row,
    calibrations.get("right", {}) as Dictionary
  )


func _apply_calibration_row(row: SelectableText, side_state: Dictionary) -> void:
  var labels := {"joystick": "Joystick", "trigger": "Trigger", "gyro": "Gyro"}
  var results: Array[String] = []
  for kind in ["joystick", "trigger", "gyro"]:
    var result := side_state.get(kind, {}) as Dictionary
    var status := str(result.get("status", "unknown")).to_lower()
    var error := str(result.get("error", "0x0000"))
    match status:
      "success", "complete", "completed":
        results.append("%s complete" % labels[kind])
      "failure", "failed", "error":
        var text := "%s failed" % labels[kind]
        if error not in ["", "0", "0x0000", "unknown", "unavailable"]:
          text += " (%s)" % error
        results.append(text)
      "in-progress", "in_progress", "running", "started":
        results.append("%s in progress" % labels[kind])
  row.text = "  •  ".join(results)
  row.visible = not results.is_empty()


func _run_controller_helper(command_name: String, privileged: bool) -> Dictionary:
  var executable := CONTROLLER_HELPER_PATH
  var arguments: Array[String] = [command_name]
  if privileged:
    executable = PKEXEC_PATH
    arguments = [CONTROLLER_HELPER_PATH, command_name]
  return await _run_json_command(executable, arguments, 15.0, "controller")


func _on_button_swap_toggled(enabled: bool) -> void:
  if controller_syncing or controller_busy:
    return
  var command_name := "swap-enable" if enabled else "swap-disable"
  _run_controller_action(command_name)


func _on_calibration_start_requested(
  side: String,
  kind: String,
  source_button: CardButton
) -> void:
  if not _is_calibration_action_supported(side, kind) or controller_busy:
    return
  var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
  if dialog == null:
    _show_message(controller_message_row, "Could not open calibration.")
    return

  dialog.cancel_visible = true
  dialog.open(
    source_button,
    _controller_calibration_guide(side, kind),
    "Start",
    "Cancel"
  )
  var accepted := await dialog.choice_selected as bool
  if accepted:
    _run_calibration_action(side, kind, "start")


func _controller_calibration_guide(side: String, kind: String) -> String:
  var side_name := side.capitalize()
  match kind:
    "joystick":
      return "%s stick\n\nRotate to the edge twice. Release to center." % side_name
    "trigger":
      var trigger := "LT" if side == "left" else "RT"
      return "%s trigger\n\nPress and release %s twice." % [side_name, trigger]
    "gyro":
      return "%s gyro\n\nPlace the controller level. Keep it still." % side_name
  return "Calibration type is not supported."


func _run_calibration_action(side: String, kind: String, action: String) -> void:
  if controller_busy:
    return
  controller_busy = true
  _show_message(
    controller_message_row,
    "%s %s calibration…" % [
      "Starting" if action == "start" else "Stopping",
      kind,
    ]
  )
  _set_controller_controls_enabled(false)
  var command_name := "calibrate-%s-%s-%s" % [side, kind, action]
  var result := await _run_controller_helper(command_name, true)
  if not is_inside_tree():
    return
  controller_busy = false
  if not bool(result.get("ok", false)):
    _show_message(
      controller_message_row,
      "Calibration request failed: %s" % str(result.get("message", "Request failed."))
    )
    await _refresh_controller_inventory()
    return

  if action == "start":
    active_calibration_side = side
    active_calibration_kind = kind
    _set_calibration_cancel_visible(true)
    calibration_timer.start()
    _show_message(
      controller_message_row,
      "%s %s running." % [side.capitalize(), kind]
    )
  else:
    _clear_active_calibration()
    _show_message(controller_message_row, "Calibration canceled.")
  await _refresh_controller_inventory()


func _on_calibration_cancel_requested() -> void:
  if active_calibration_side.is_empty() or active_calibration_kind.is_empty():
    return
  _run_calibration_action(active_calibration_side, active_calibration_kind, "stop")


func _update_active_calibration(state: Dictionary) -> void:
  if active_calibration_side.is_empty() or active_calibration_kind.is_empty():
    return
  var key := "%s_%s" % [active_calibration_side, active_calibration_kind]
  var status := str(state.get(key + "_status", "unknown")).to_lower()
  if status == "success":
    var completed := "%s %s complete." % [
      active_calibration_side.capitalize(),
      active_calibration_kind,
    ]
    _clear_active_calibration()
    _show_message(controller_message_row, completed)
  elif status in ["failure", "failed", "error"]:
    var error := str(state.get(key + "_error", "unknown"))
    var failed := "%s %s calibration failed: %s" % [
      active_calibration_side.capitalize(),
      active_calibration_kind,
      _calibration_error_text(active_calibration_kind, error),
    ]
    _clear_active_calibration()
    _show_message(controller_message_row, failed)


func _calibration_error_text(kind: String, error: String) -> String:
  var key := error.to_lower()
  var messages := {
    "gyro:0x0001": "Keep the controller still and try again.",
    "gyro:0x0002": "The controller connection changed.",
    "joystick:0x0100": "The stick did not reach its full range.",
    "joystick:0x0200": "The stick did not return to center.",
    "joystick:0x0400": "Rotate the stick at least twice.",
    "joystick:0x0800": "The controller connection changed.",
    "trigger:0x0001": "The trigger was not fully pressed.",
    "trigger:0x0002": "The trigger was not fully released.",
    "trigger:0x0004": "Press and release the trigger twice.",
    "trigger:0x0008": "The controller connection changed.",
  }
  if key == "0xffff":
    return "The controller reported an internal error."
  return str(messages.get("%s:%s" % [kind, key], error))


func _set_calibration_cancel_visible(show: bool) -> void:
  calibration_cancel_button.visible = show
  _set_focusable(calibration_cancel_button, show and not calibration_cancel_button.disabled)


func _clear_active_calibration() -> void:
  active_calibration_side = ""
  active_calibration_kind = ""
  calibration_timer.stop()
  _set_calibration_cancel_visible(false)


func _run_controller_action(command_name: String) -> void:
  if controller_busy:
    return
  controller_busy = true
  _show_message(controller_control_message_row, "Updating…")
  var result := await _run_controller_helper(command_name, true)
  if not is_inside_tree():
    return
  controller_busy = false
  if not bool(result.get("ok", false)):
    _show_message(
      controller_control_message_row,
      "Update failed: %s" % str(result.get("message", "Request failed."))
    )
    await _refresh_controller_inventory()
    return
  _show_message(controller_control_message_row, "")
  await _refresh_controller_inventory()


func _set_controller_controls_enabled(enabled: bool) -> void:
  button_swap_toggle.disabled = not enabled
  _set_focusable(button_swap_toggle, enabled)
  var calibration_enabled := enabled and active_calibration_side.is_empty()
  var any_calibration_enabled := false
  for index in range(calibration_buttons.size()):
    var calibration_button := calibration_buttons[index]
    var action: Dictionary = calibration_button_actions[index]
    var action_enabled := calibration_enabled and _is_calibration_action_supported(
      str(action["side"]),
      str(action["kind"])
    )
    calibration_button.disabled = not action_enabled
    _set_focusable(calibration_button, action_enabled)
    any_calibration_enabled = any_calibration_enabled or action_enabled
  _set_focus_container_enabled(calibration_container, any_calibration_enabled)
  var cancel_enabled := enabled and not active_calibration_side.is_empty()
  calibration_cancel_button.disabled = not cancel_enabled
  _set_focusable(calibration_cancel_button, cancel_enabled and calibration_cancel_button.visible)


func _refresh_fan() -> void:
  if fan_busy:
    return
  if not FileAccess.file_exists(FAN_HELPER_PATH):
    fan_ready = false
    fan_status_row.text = "Setup required"
    _show_message(fan_message_row, "")
    _set_fan_controls_enabled(false)
    return

  fan_busy = true
  if not fan_ready:
    _set_fan_controls_enabled(false)
  var state := await _run_fan_helper(["status"], false)
  if not is_inside_tree():
    return
  fan_busy = false
  _apply_fan_status(state)


func _run_fan_helper(arguments: Array[String], privileged: bool) -> Dictionary:
  var executable := FAN_HELPER_PATH
  var command_arguments: Array[String] = arguments.duplicate()
  if privileged:
    executable = PKEXEC_PATH
    command_arguments.push_front(FAN_HELPER_PATH)
  return await _run_json_command(executable, command_arguments, 20.0, "fan")


func _run_json_command(
  executable: String,
  arguments: Array[String],
  timeout: float,
  component: String
) -> Dictionary:
  var command := Command.create(executable, arguments)
  command.timeout = timeout
  if command.execute() != OK:
    return {
      "ok": false,
      "code": "start-failed",
      "message": "The %s backend did not start." % component,
    }

  var exit_code := await command.finished as int
  var parsed: Variant = JSON.parse_string(command.stdout.strip_edges())
  if parsed is Dictionary:
    var result := parsed as Dictionary
    result["exit_code"] = exit_code
    return result

  var message := "The %s backend returned an invalid response." % component
  if executable == PKEXEC_PATH and exit_code in [126, 127]:
    message = "The request was not authorized."
  return {
    "ok": false,
    "code": "invalid-response",
    "message": message,
    "exit_code": exit_code,
  }


func _apply_fan_status(state: Dictionary) -> void:
  if not bool(state.get("ok", false)):
    fan_ready = false
    fan_status_row.text = "Unavailable"
    _show_message(fan_message_row, "")
    _set_fan_controls_enabled(false)
    return

  var curve := _normalize_fan_curve(state.get("curve", []))
  if not _is_valid_fan_curve(curve):
    fan_ready = false
    fan_status_row.text = "Unavailable"
    _show_message(fan_message_row, "The fan backend did not return a valid curve.")
    _set_fan_controls_enabled(false)
    return

  fan_ready = true
  var rpm := int(state.get("rpm", 0))
  fan_full_speed_enabled = bool(state.get("full_speed", false))
  fan_firmware_curve = curve.duplicate()
  var mode := _fan_curve_label(fan_firmware_curve)
  if not fan_custom_selected:
    fan_custom_curve = fan_firmware_curve.duplicate()
    fan_custom_selected = mode not in ["Quiet", "Balanced", "Performance"]

  fan_status_row.text = "%d RPM" % rpm
  fan_status_row.description = "%s curve" % mode
  if fan_full_speed_enabled:
    fan_status_row.description = "Full Speed on • %s curve" % mode

  fan_syncing = true
  fan_full_speed_toggle.button_pressed = fan_full_speed_enabled
  fan_syncing = false
  _sync_fan_mode_buttons("Custom" if fan_custom_selected else mode)
  _sync_fan_curve_sliders()
  _show_message(fan_message_row, "")
  _set_fan_controls_enabled(true)


func _normalize_fan_curve(value: Variant) -> Array[int]:
  var normalized: Array[int] = []
  if not value is Array:
    return normalized
  var points := value as Array
  if points.size() != 10:
    return normalized
  for point in points:
    normalized.append(int(point))
  return normalized


func _fan_curve_matches(curve: Array[int], preset: Array[int]) -> bool:
  if curve.size() != preset.size():
    return false
  for index in range(curve.size()):
    if curve[index] != preset[index]:
      return false
  return true


func _is_valid_fan_curve(curve: Array[int]) -> bool:
  if curve.size() != 10:
    return false
  if _fan_curve_matches(curve, FAN_QUIET_CURVE) or _fan_curve_matches(
    curve,
    FAN_BALANCED_CURVE
  ):
    return true
  var previous := FAN_MIN_LEVEL
  for index in range(10):
    var point := curve[index]
    if point < FAN_HARD_MIN[index] or point > FAN_MAX_LEVEL or point < previous:
      return false
    previous = point
  return true


func _fan_curve_label(curve: Array[int]) -> String:
  if _fan_curve_matches(curve, FAN_AUTOMATIC_CURVE):
    return "Automatic"
  if _fan_curve_matches(curve, FAN_QUIET_CURVE):
    return "Quiet"
  if _fan_curve_matches(curve, FAN_BALANCED_CURVE):
    return "Balanced"
  if _fan_curve_matches(curve, FAN_PERFORMANCE_CURVE):
    return "Performance"
  return "Custom"


func _on_fan_mode_pressed(mode: String) -> void:
  if fan_syncing or fan_busy:
    return
  if mode == "Custom":
    if fan_firmware_curve.size() != 10:
      return
    fan_custom_selected = true
    fan_custom_curve = fan_firmware_curve.duplicate()
    _sync_fan_mode_buttons("Custom")
    _sync_fan_curve_sliders()
    _set_fan_controls_enabled(true)
    return

  fan_custom_selected = false
  _sync_fan_mode_buttons(mode)
  var curve: Array
  match mode:
    "Quiet":
      curve = FAN_QUIET_CURVE
    "Balanced":
      curve = FAN_BALANCED_CURVE
    "Performance":
      curve = FAN_PERFORMANCE_CURVE
    _:
      return
  _run_fan_action(_curve_arguments(curve), "Applying %s…" % mode)


func _sync_fan_mode_buttons(selected_mode: String) -> void:
  for index in range(fan_mode_buttons.size()):
    var mode_name: String = FAN_UI_MODE_NAMES[index]
    fan_mode_buttons[index].text = (
      "● %s" % mode_name if mode_name == selected_mode else mode_name
    )


func _on_fan_full_speed_toggled(enabled: bool) -> void:
  if fan_syncing or fan_busy:
    return
  _run_fan_action(
    ["set-fullspeed", "1" if enabled else "0"],
    "Changing Full Speed…"
  )


func _on_fan_curve_value_changed(value: float, index: int) -> void:
  if fan_syncing or not fan_custom_selected or fan_custom_curve.size() != 10:
    return
  fan_custom_curve[index] = int(value)


func _sync_fan_curve_sliders() -> void:
  var displayed_curve: Array[int] = (
    fan_custom_curve if fan_custom_selected else fan_firmware_curve
  )
  if displayed_curve.size() != 10:
    return
  fan_syncing = true
  for index in range(fan_curve_sliders.size()):
    var recommended := str(FAN_RECOMMENDED_MIN[index])
    if FAN_RECOMMENDED_MIN[index] != FAN_RECOMMENDED_MAX[index]:
      recommended += "–%d" % FAN_RECOMMENDED_MAX[index]
    var curve_slider: ValueSlider = fan_curve_sliders[index]
    curve_slider.description = "Lenovo: %s" % recommended
    curve_slider.min_value = FAN_HARD_MIN[index]
    curve_slider.max_value = FAN_MAX_LEVEL
    curve_slider.value = displayed_curve[index]
  fan_syncing = false


func _curve_arguments(curve: Array) -> Array[String]:
  var arguments: Array[String] = ["set-curve"]
  for value in curve:
    arguments.append(str(int(value)))
  return arguments


func _on_apply_custom_curve() -> void:
  if not fan_custom_selected or fan_custom_curve.size() != 10:
    return
  var arguments: Array[String] = ["set-curve"]
  var previous := 0
  var outside_recommended := false
  for index in range(10):
    var value: int = fan_custom_curve[index]
    if value < FAN_HARD_MIN[index]:
      _show_message(
        fan_message_row,
        "%d °C needs %d or higher." % [(index + 1) * 10, FAN_HARD_MIN[index]]
      )
      return
    if value > FAN_MAX_LEVEL:
      _show_message(fan_message_row, "Levels cannot exceed %d." % FAN_MAX_LEVEL)
      return
    if value < previous:
      _show_message(fan_message_row, "Levels must not decrease.")
      return
    if value < FAN_RECOMMENDED_MIN[index] or value > FAN_RECOMMENDED_MAX[index]:
      outside_recommended = true
    previous = value
    arguments.append(str(value))

  if outside_recommended:
    var dialog := get_tree().get_first_node_in_group("dialog") as Dialog
    if dialog == null:
      _show_message(fan_message_row, "Could not open the confirmation dialog.")
      return
    dialog.cancel_visible = true
    dialog.open(
      fan_apply_custom_button,
      "Outside Lenovo's range. Low levels can raise heat. Apply?",
      "Apply",
      "Cancel"
    )
    var accepted := await dialog.choice_selected as bool
    if not accepted:
      return

  _run_fan_action(arguments, "Applying custom curve…")


func _run_fan_action(arguments: Array[String], progress_text: String) -> void:
  if fan_busy:
    return
  fan_busy = true
  _show_message(fan_message_row, progress_text)
  var result := await _run_fan_helper(arguments, true)
  if not is_inside_tree():
    return
  fan_busy = false
  if bool(result.get("ok", false)):
    await _refresh_fan()
    return

  var error_message := "Could not change the fan setting: %s" % str(
    result.get("message", "Request failed.")
  )
  await _refresh_fan()
  _show_message(fan_message_row, error_message)


func _set_fan_controls_enabled(enabled: bool) -> void:
  var controls_disabled := not enabled
  for mode_button in fan_mode_buttons:
    if mode_button.disabled != controls_disabled:
      mode_button.disabled = controls_disabled
    _set_focusable(mode_button, enabled)
  _set_focus_container_enabled(fan_mode_container, enabled)
  if fan_full_speed_toggle.disabled != controls_disabled:
    fan_full_speed_toggle.disabled = controls_disabled
  _set_focusable(fan_full_speed_toggle, enabled)
  var custom_enabled := enabled and fan_custom_selected
  for curve_slider in fan_curve_sliders:
    if curve_slider.editable != custom_enabled:
      curve_slider.editable = custom_enabled
    _set_focusable(curve_slider, custom_enabled)
  var apply_disabled := not custom_enabled
  if fan_apply_custom_button.disabled != apply_disabled:
    fan_apply_custom_button.disabled = apply_disabled
  _set_focusable(fan_apply_custom_button, custom_enabled)

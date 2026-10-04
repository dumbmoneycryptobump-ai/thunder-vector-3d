extends CanvasLayer

# A fixed 1280x720 touch overlay. Input events already use the stretched viewport's
# coordinates; each finger owns one role until release/cancellation, never a key.
const JOYSTICK_CENTER := Vector2(120.0, 575.0)
const JOYSTICK_RADIUS := 85.0
const JOYSTICK_DEADZONE := 0.12
const FIRE_CENTER := Vector2(1170.0, 610.0)
const FIRE_RADIUS := 64.0

class TouchSurface:
    extends Control
    var controller: Node

    func _draw() -> void:
        if is_instance_valid(controller):
            controller.call("_draw_controls", self)

class TouchButton:
    extends RefCounted
    var action := ""
    var title := ""
    var rect := Rect2()
    var label: Label
    var settings_only := false

var _game: Node
var _surface: TouchSurface
var _buttons: Array[TouchButton] = []
var _hint: Label
var _enabled := false
var _explicit_enabled := false
var _finger_roles: Dictionary = {}
var _joystick_id := -1
var _move := Vector2.ZERO
var _knob := Vector2.ZERO
var _state_key := ""


func setup(game: Node) -> void:
    if _game != game:
        release_inputs()
    _game = game
    process_mode = Node.PROCESS_MODE_ALWAYS
    layer = 20
    if not _explicit_enabled:
        _enabled = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()
    if _surface == null:
        _surface = TouchSurface.new()
        _surface.name = "TouchSurface"
        _surface.controller = self
        _surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _surface.size = Vector2(1280.0, 720.0)
        add_child(_surface)
        _add_button("fire", "射擊", Rect2(FIRE_CENTER - Vector2.ONE * FIRE_RADIUS, Vector2.ONE * FIRE_RADIUS * 2.0))
        _add_button("bomb", "炸彈 B", Rect2(360.0, 546.0, 80.0, 80.0))
        _add_button("overdrive", "超載 E", Rect2(460.0, 546.0, 80.0, 80.0))
        _add_button("weapon_next", "換武器", Rect2(560.0, 546.0, 80.0, 80.0))
        _add_button("pause", "暫停", Rect2(660.0, 546.0, 80.0, 80.0))
        _add_button("settings", "設定", Rect2(760.0, 546.0, 80.0, 80.0))
        _add_button("restart", "重開", Rect2(860.0, 546.0, 80.0, 80.0))
        _add_button("settings_prev", "上一項", Rect2(380.0, 546.0, 90.0, 80.0), true)
        _add_button("settings_next", "下一項", Rect2(485.0, 546.0, 90.0, 80.0), true)
        _add_button("settings_decrease", "−", Rect2(590.0, 546.0, 90.0, 80.0), true)
        _add_button("settings_increase", "＋", Rect2(695.0, 546.0, 90.0, 80.0), true)
        _add_button("settings_close", "完成", Rect2(805.0, 546.0, 110.0, 80.0), true)
        _hint = Label.new()
        _hint.name = "LandscapeHint"
        _hint.text = "橫向握持可獲得更大的操作空間"
        _hint.position = Vector2(340.0, 682.0)
        _hint.size = Vector2(600.0, 28.0)
        _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _hint.add_theme_font_size_override("font_size", 18)
        _hint.add_theme_color_override("font_color", Color("b7d6e9"))
        _surface.add_child(_hint)
        if get_window() != null and not get_window().focus_exited.is_connected(_on_focus_lost):
            get_window().focus_exited.connect(_on_focus_lost)
    _state_key = ""
    _sync_state()


func _add_button(action: String, title: String, rect: Rect2, settings_only: bool = false) -> void:
    var button := TouchButton.new()
    button.action = action
    button.title = title
    button.rect = rect
    button.settings_only = settings_only
    button.label = Label.new()
    button.label.name = "Touch_" + action
    button.label.text = title
    button.label.position = rect.position
    button.label.size = rect.size
    button.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    button.label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    button.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    button.label.add_theme_font_size_override("font_size", 20 if action != "fire" else 25)
    button.label.add_theme_color_override("font_color", Color("daf5ff"))
    _surface.add_child(button.label)
    _buttons.append(button)


func set_enabled(enabled: bool) -> void:
    _explicit_enabled = true
    _enabled = enabled
    release_inputs()
    _state_key = ""
    _sync_state()


func is_enabled() -> bool:
    return _enabled


func get_touch_mode() -> bool:
    return _enabled


func get_move_vector() -> Vector2:
    _sync_state()
    return _move if _enabled and _can_play() else Vector2.ZERO


func wants_fire() -> bool:
    _sync_state()
    return _enabled and _can_play() and _finger_roles.values().has("fire")


func _can_play() -> bool:
    return is_instance_valid(_game) and not bool(_game.get("is_paused")) and not bool(_game.get("is_game_over")) and not bool(_game.get("settings_open"))


func _settings_open() -> bool:
    return is_instance_valid(_game) and bool(_game.get("settings_open"))


func _button_available(button: TouchButton) -> bool:
    if not is_instance_valid(_game):
        return false
    if button.settings_only:
        return _settings_open()
    if _settings_open():
        return false
    match button.action:
        "restart":
            return bool(_game.get("is_game_over"))
        "settings":
            return true
        "pause":
            return not bool(_game.get("is_game_over"))
    return _can_play()


func _process(_delta: float) -> void:
    _sync_state()


func _sync_state() -> void:
    if _surface == null:
        return
    var valid_game := is_instance_valid(_game)
    var paused := bool(_game.get("is_paused")) if valid_game else false
    var dead := bool(_game.get("is_game_over")) if valid_game else true
    var settings := _settings_open()
    var window_size := DisplayServer.window_get_size()
    var portrait := window_size.y > window_size.x
    var state := "%s/%s/%s/%s/%s" % [_enabled, paused, dead, settings, portrait]
    if state == _state_key:
        return
    _state_key = state
    # A resumed game always needs a fresh finger press, not a held pre-pause input.
    release_inputs()
    _surface.visible = _enabled
    _hint.visible = portrait and _enabled
    for button in _buttons:
        button.label.visible = _button_available(button)
        button.label.text = "繼續" if button.action == "pause" and paused else button.title
    _surface.queue_redraw()


func _input(event: InputEvent) -> void:
    if not _enabled or _surface == null:
        return
    _sync_state()
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.canceled or not touch.pressed:
            if _release_finger(touch.index):
                get_viewport().set_input_as_handled()
            return
        var position := _surface.get_global_transform_with_canvas().affine_inverse() * touch.position
        if _press_finger(touch.index, position):
            get_viewport().set_input_as_handled()
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        if not _finger_roles.has(drag.index):
            return
        var position := _surface.get_global_transform_with_canvas().affine_inverse() * drag.position
        var role := str(_finger_roles[drag.index])
        if role == "move":
            _update_joystick(position)
        elif role == "fire" and position.distance_squared_to(FIRE_CENTER) > FIRE_RADIUS * FIRE_RADIUS:
            _release_finger(drag.index)
        get_viewport().set_input_as_handled()


func _press_finger(index: int, position: Vector2) -> bool:
    if _finger_roles.has(index):
        return true
    if _can_play() and _joystick_id < 0 and position.distance_squared_to(JOYSTICK_CENTER) <= JOYSTICK_RADIUS * JOYSTICK_RADIUS:
        _joystick_id = index
        _finger_roles[index] = "move"
        _update_joystick(position)
        return true
    for button in _buttons:
        if not _button_available(button) or not button.rect.has_point(position):
            continue
        if button.action == "fire" and position.distance_squared_to(FIRE_CENTER) > FIRE_RADIUS * FIRE_RADIUS:
            continue
        _finger_roles[index] = button.action
        if button.action != "fire":
            _game.call("_device_action", button.action)
            _sync_state()
        _surface.queue_redraw()
        return true
    return false


func _update_joystick(position: Vector2) -> void:
    _knob = (position - JOYSTICK_CENTER).limit_length(JOYSTICK_RADIUS)
    var normalized := _knob / JOYSTICK_RADIUS
    var strength := normalized.length()
    _move = Vector2.ZERO if strength <= JOYSTICK_DEADZONE else normalized.normalized() * ((strength - JOYSTICK_DEADZONE) / (1.0 - JOYSTICK_DEADZONE))
    _surface.queue_redraw()


func _release_finger(index: int) -> bool:
    if not _finger_roles.has(index):
        return false
    _finger_roles.erase(index)
    if index == _joystick_id:
        _joystick_id = -1
        _move = Vector2.ZERO
        _knob = Vector2.ZERO
    if _surface != null:
        _surface.queue_redraw()
    return true


func release_inputs() -> void:
    _finger_roles.clear()
    _joystick_id = -1
    _move = Vector2.ZERO
    _knob = Vector2.ZERO
    if _surface != null:
        _surface.queue_redraw()


func _on_focus_lost() -> void:
    release_inputs()


func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
        release_inputs()


func _draw_controls(surface: Control) -> void:
    if not _enabled:
        return
    if _can_play():
        surface.draw_circle(JOYSTICK_CENTER, JOYSTICK_RADIUS, Color(0.08, 0.17, 0.25, 0.42))
        surface.draw_arc(JOYSTICK_CENTER, JOYSTICK_RADIUS, 0.0, TAU, 64, Color(0.45, 0.78, 0.9, 0.6), 2.0, true)
        surface.draw_circle(JOYSTICK_CENTER + _knob * 0.65, 30.0, Color(0.5, 0.82, 0.93, 0.45))
    var held := _finger_roles.values()
    for button in _buttons:
        if not _button_available(button):
            continue
        var pressed := held.has(button.action)
        var fill := Color(0.17, 0.4, 0.51, 0.75) if pressed else Color(0.04, 0.12, 0.19, 0.58)
        var line := Color(0.61, 0.87, 0.97, 0.86) if pressed else Color(0.43, 0.65, 0.78, 0.62)
        if button.action == "fire":
            surface.draw_circle(FIRE_CENTER, FIRE_RADIUS, fill)
            surface.draw_arc(FIRE_CENTER, FIRE_RADIUS, 0.0, TAU, 64, line, 2.0, true)
        else:
            surface.draw_rect(button.rect, fill)
            surface.draw_rect(button.rect, line, false, 2.0)


func get_button_rect(action: String) -> Rect2:
    for button in _buttons:
        if button.action == action:
            return button.rect
    return Rect2()


func get_stats() -> Dictionary:
    var fire_count := 0
    for role in _finger_roles.values():
        if role == "fire":
            fire_count += 1
    return {"enabled": _enabled, "touches": _finger_roles.size(), "joystick_id": _joystick_id,
        "fire_count": fire_count, "move": _move, "buttons": _buttons.size(),
        "settings": _settings_open(), "ready": _surface != null}

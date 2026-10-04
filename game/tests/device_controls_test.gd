extends SceneTree

const DEVICE_SCRIPT := preload("res://scripts/device_controls.gd")

class FakeGame:
    extends Node
    var is_paused := false
    var is_game_over := false
    var settings_open := false
    var actions: Array[String] = []

    func _device_action(action: String) -> void:
        actions.append(action)
        match action:
            "pause":
                is_paused = not is_paused
            "settings":
                settings_open = true
                is_paused = true
            "settings_close":
                settings_open = false
            "restart":
                is_game_over = false
                is_paused = false
                settings_open = false

var game: FakeGame
var controls: CanvasLayer
var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    game = FakeGame.new()
    root.add_child(game)
    controls = DEVICE_SCRIPT.new()
    game.add_child(controls)
    controls.call("setup", game)
    controls.call("set_enabled", true)
    await process_frame
    var initial_nodes := _identities(controls)
    controls.call("setup", game)
    _expect(_identities(controls) == initial_nodes, "setup must be idempotent")
    _expect(controls.call("is_enabled") and controls.call("get_touch_mode"), "explicit touch mode must be usable on non-touch hosts")
    _expect(controls.call("get_stats")["buttons"] == 12, "gameplay and settings buttons must all be precreated")
    _expect(controls.call("get_button_rect", "unknown") == Rect2(), "unknown actions must not create button geometry")
    for action in ["bomb", "overdrive", "weapon_next", "pause", "settings", "restart", "settings_prev", "settings_next", "settings_decrease", "settings_increase", "settings_close"]:
        var rect: Rect2 = controls.call("get_button_rect", action)
        _expect(rect.size.x >= 80.0 and rect.size.y >= 80.0, "touch actions need large fixed targets")
        _expect(Rect2(0.0, 0.0, 1280.0, 720.0).encloses(rect), "touch targets must fit the internal viewport")

    _touch(0, Vector2(120.0, 575.0), true)
    _drag(0, Vector2(205.0, 575.0))
    _expect((controls.call("get_move_vector") as Vector2).is_equal_approx(Vector2.RIGHT), "joystick drag must produce rightward movement")
    _touch(1, Vector2(1170.0, 610.0), true)
    _expect(controls.call("wants_fire"), "a second finger must shoot while the joystick is held")
    _expect(controls.call("get_stats")["touches"] == 2, "move and fire must retain independent finger ownership")
    _touch(2, Vector2(120.0, 575.0), true)
    _drag(2, Vector2(35.0, 575.0))
    _expect((controls.call("get_move_vector") as Vector2).x > 0.99, "another finger cannot steal the joystick")
    _touch(1, Vector2.ZERO, false)
    _expect(not controls.call("wants_fire") and (controls.call("get_move_vector") as Vector2).x > 0.99, "releasing fire must not release movement")
    _touch(0, Vector2.ZERO, false)
    _expect(controls.call("get_move_vector") == Vector2.ZERO, "joystick release must immediately neutralize movement")

    _touch(3, Vector2(120.0, 575.0), true)
    _drag(3, Vector2(125.0, 575.0))
    _expect(controls.call("get_move_vector") == Vector2.ZERO, "deadzone must suppress tiny motion")
    _drag(3, Vector2(1000.0, -1000.0))
    _expect(is_equal_approx((controls.call("get_move_vector") as Vector2).length(), 1.0), "movement must clamp outside joystick radius")
    _touch(3, Vector2.ZERO, false, true)
    _expect(controls.call("get_move_vector") == Vector2.ZERO, "cancellation must release a captured joystick")
    _touch(4, Vector2(1170.0, 610.0), true)
    _touch(5, Vector2(1175.0, 615.0), true)
    _touch(4, Vector2.ZERO, false, true)
    _expect(controls.call("wants_fire") and controls.call("get_stats")["fire_count"] == 1, "canceling one fire finger must preserve another")
    _drag(5, Vector2(900.0, 400.0))
    _expect(not controls.call("wants_fire"), "dragging away from fire must cancel it")
    _touch(6, Vector2(500.0, 350.0), true)
    _expect(controls.call("get_stats")["touches"] == 0, "touches outside control regions must not become gameplay input")

    for action in ["bomb", "overdrive", "weapon_next"]:
        var before := game.actions.size()
        _press_action(7, action)
        _press_action(7, action)
        _expect(game.actions.size() == before + 1 and game.actions.back() == action, "one held finger must dispatch an action only once")
        _touch(7, Vector2.ZERO, false)
    _touch(8, Vector2(1170.0, 610.0), true)
    _touch(9, Vector2(120.0, 575.0), true)
    _drag(9, Vector2(205.0, 575.0))
    _press_action(10, "pause")
    _expect(game.is_paused and not controls.call("wants_fire") and controls.call("get_move_vector") == Vector2.ZERO, "pause action must cancel movement and fire")
    _expect(controls.call("get_stats")["touches"] == 0, "pause must release every old finger")
    var paused_count := game.actions.size()
    _press_action(11, "bomb")
    _touch(12, Vector2(1170.0, 610.0), true)
    _expect(game.actions.size() == paused_count and not controls.call("wants_fire"), "combat buttons must be masked during pause")
    _press_action(13, "pause")
    _expect(not game.is_paused and not controls.call("wants_fire"), "resuming must not resume a held pre-pause finger")
    _touch(13, Vector2.ZERO, false)

    _press_action(14, "settings")
    _expect(game.settings_open and game.is_paused, "settings must be reachable without a keyboard")
    _touch(14, Vector2.ZERO, false)
    for action in ["settings_prev", "settings_next", "settings_decrease", "settings_increase"]:
        _press_action(15, action)
        _expect(game.actions.back() == action, "each settings navigation action must be touch reachable")
        _touch(15, Vector2.ZERO, false)
    _press_action(16, "settings_close")
    _expect(not game.settings_open and game.is_paused, "settings close must return to the owner's paused menu")
    _touch(16, Vector2.ZERO, false)
    _press_action(17, "pause")
    _touch(17, Vector2.ZERO, false)

    _touch(18, Vector2(1170.0, 610.0), true)
    game.is_paused = true
    _expect(not controls.call("wants_fire") and controls.call("get_stats")["touches"] == 0, "external keyboard pause must also clear finger ownership")
    game.is_paused = false
    _expect(not controls.call("wants_fire"), "external resume must require a fresh touch")
    _touch(19, Vector2(1170.0, 610.0), true)
    game.is_game_over = true
    _expect(not controls.call("wants_fire") and controls.call("get_move_vector") == Vector2.ZERO, "death must mask combat inputs immediately")
    var dead_count := game.actions.size()
    _press_action(20, "overdrive")
    _expect(game.actions.size() == dead_count, "dead players cannot trigger combat actions")
    _press_action(21, "restart")
    _expect(not game.is_game_over and not controls.call("wants_fire"), "touch restart must not inherit old held fire")
    _touch(21, Vector2.ZERO, false)

    _touch(22, Vector2(1170.0, 610.0), true)
    controls.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _expect(not controls.call("wants_fire") and controls.call("get_stats")["touches"] == 0, "focus loss must release all fingers")
    _touch(23, Vector2(1170.0, 610.0), true)
    controls.notification(Node.NOTIFICATION_APPLICATION_PAUSED)
    _expect(not controls.call("wants_fire"), "application suspension must release fire")
    _touch(24, Vector2(1170.0, 610.0), true)
    controls.call("set_enabled", false)
    _expect(not controls.call("wants_fire") and not controls.call("is_enabled"), "disabling touch mode must clear and hide its inputs")
    _touch(25, Vector2(1170.0, 610.0), true)
    _expect(controls.call("get_stats")["touches"] == 0, "disabled overlay cannot capture fingers")
    controls.call("set_enabled", true)
    for index in range(100):
        _touch(100 + index, Vector2(120.0, 575.0), true)
        _drag(100 + index, Vector2(145.0, 540.0))
        controls.call("release_inputs")
        _expect(controls.call("get_stats")["touches"] == 0 and controls.call("get_move_vector") == Vector2.ZERO, "repeated release must stay neutral")
    _expect(_identities(controls) == initial_nodes, "input and state transitions cannot allocate or replace nodes")
    game.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("DEVICE_CONTROLS_TEST_PASS assertions=%d multitouch=independent cancellation=neutral lifecycle=masked settings=touch_reachable nodes=stable" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("DEVICE_CONTROLS_TEST_FAIL: " + failure)
        quit(1)


func _touch(index: int, position: Vector2, pressed: bool, canceled: bool = false) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    event.canceled = canceled
    root.push_input(event, true)


func _drag(index: int, position: Vector2) -> void:
    var event := InputEventScreenDrag.new()
    event.index = index
    event.position = position
    root.push_input(event, true)


func _press_action(index: int, action: String) -> void:
    var rect: Rect2 = controls.call("get_button_rect", action)
    _touch(index, rect.get_center(), true)


func _identities(node: Node) -> Array[int]:
    var result: Array[int] = [node.get_instance_id()]
    for child in node.get_children():
        result.append_array(_identities(child))
    return result


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)

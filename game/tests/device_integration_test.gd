extends SceneTree

const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")

class MemorySettings:
    extends "res://scripts/settings_store.gd"
    var saves := 0

    func save_settings(candidate: Dictionary) -> Error:
        values = candidate.duplicate(true)
        saves += 1
        return OK

var game: Node
var settings: MemorySettings
var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    game = (load("res://main.tscn") as PackedScene).instantiate()
    root.add_child(game)
    game.set_physics_process(false)
    game.set_process(false)
    settings = MemorySettings.new()
    game.settings_store = settings
    game.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    game.device_controls.set_enabled(true)
    await process_frame
    _reset()
    _expect(not bool(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch", true)), "touch movement must not be emulated as left-click fire")
    _test_web_validation_and_move()
    _test_combined_inputs_and_lifecycle()
    _test_actual_settings_navigation()
    _test_cooldown_weapons_and_overdrive()
    _test_controller_button_mapping()
    _test_death_and_restart()
    _reset()
    _hold_inputs()
    game.call("prepare_for_shutdown")
    _assert_released("shutdown")
    _expect(not game.call("_device_action", "fire") and not game.call("_device_action", "bomb"), "shutdown must reject gameplay actions")
    game.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("DEVICE_INTEGRATION_TEST_PASS assertions=%d owner=actual_main touch_web=lifecycle_safe callbacks=validated modes=preserved joypad_buttons=mapped settings_writes=0 physical_joy_axes=not_claimed" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("DEVICE_INTEGRATION_TEST_FAIL: " + failure)
        quit(1)


func _test_web_validation_and_move() -> void:
    for invalid in [[], [1], ["1", 0], [0, "1"], [true, 0], [INF, 0.0], [0.0, NAN]]:
        game.call("_on_web_move", invalid)
        _expect(game._web_move == Vector2.ZERO, "malformed/nonfinite Web vectors must be ignored")
    game.call("_on_web_move", [4.0, 3.0])
    _expect((game._web_move as Vector2).is_equal_approx(Vector2(0.8, 0.6)), "Web move must normalize oversized vectors")
    var start: Vector3 = game.player.position
    game.shot_timer = 9.0
    game.call("_update_player", 0.05)
    _assert_movement_step(start, 0.05, "Web")
    game.call("_on_web_move", [-0.3, 0.0])
    _expect((game._web_move as Vector2).is_equal_approx(Vector2(-0.3, 0.0)), "Web joystick must preserve analog magnitude")
    game.call("_on_web_move", [0, 0])
    for invalid in [[], [12], ["fire", "true"], ["fire", 1], ["unknown_action"]]:
        game.call("_on_web_action", invalid)
        _expect(not game._web_fire, "Web action callback must reject malformed/unknown requests")
    game.call("_on_web_action", ["fire", true])
    _expect(game._web_fire, "Web boolean fire press must reach the actual main owner")
    game.call("_on_web_action", ["fire", false])
    _expect(not game._web_fire, "Web boolean fire release must neutralize fire")
    _expect(not game.call("_device_action", "unknown_action"), "device dispatcher must be allowlisted")
    _expect(not game.call("_device_action", "restart"), "restart must not reset a living run")
    _reset()
    game.call("_on_web_move", [1.0, 1.0])
    for index in range(120):
        game.call("_update_player", 1.0 / 60.0)
        _expect(game.player.position.x <= game.PLAYER_MAX_X and game.player.position.z <= game.PLAYER_MAX_Z, "device movement must respect expanded world bounds")
    _reset()


func _test_combined_inputs_and_lifecycle() -> void:
    _hold_inputs()
    var initial_volley: int = game.volley_count
    var start: Vector3 = game.player.position
    game.shot_timer = 0.0
    game.call("_update_player", 0.03)
    _expect(game.volley_count == initial_volley + 1, "touch and Web fire together must produce one shared volley")
    _assert_movement_step(start, 0.03, "combined touch/Web")
    game.call("_device_action", "pause")
    _expect(game.is_paused, "device pause must reach the owner state")
    _assert_released("pause")
    var paused_volley: int = game.volley_count
    var paused_position: Vector3 = game.player.position
    game.call("_on_web_move", [1.0, 0.0])
    game.call("_on_web_action", ["fire", true])
    _expect(not game.call("_device_action", "bomb") and not game.call("_device_action", "overdrive") and not game.call("_device_action", "weapon_next"), "paused combat actions must be rejected")
    game.call("_physics_process", 0.1)
    _expect(game.volley_count == paused_volley and game.player.position == paused_position, "paused physics must not move or shoot")
    _assert_released("paused callbacks")
    game.call("_device_action", "pause")
    _assert_released("resume")
    _hold_inputs()
    game.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
    _expect(game.is_paused, "application focus loss must pause the actual game")
    _assert_released("focus loss")
    game.call("_device_action", "pause")
    _hold_inputs()
    _key(KEY_P)
    _expect(game.is_paused, "keyboard pause must share device lifecycle behavior")
    _assert_released("keyboard pause")
    _key(KEY_P)
    _assert_released("keyboard resume")
    _reset()


func _test_actual_settings_navigation() -> void:
    _hold_inputs()
    game.call("_device_action", "settings")
    _expect(game.settings_open and game.is_paused and game.settings_overlay.visible, "device settings must expose the real settings UI")
    _assert_released("settings open")
    var bombs: int = game.bombs
    var mode: int = game.weapon_mode
    for action in ["bomb", "overdrive", "weapon_next", "pause", "restart"]:
        _expect(not game.call("_device_action", action), "settings must mask non-settings actions")
    _expect(game.bombs == bombs and game.weapon_mode == mode, "settings navigation must not alter combat state")
    _expect(game.call("_device_action", "settings_decrease"), "touch settings decrease must be accepted")
    _expect(is_equal_approx(float(game.settings_values["master_volume"]), 0.9), "device action must adjust the selected real setting")
    _expect(game.call("_device_action", "settings_next") and game.settings_index == 1, "touch next must change the selected row")
    _expect(game.call("_device_action", "settings_prev") and game.settings_index == 0, "touch previous must change the selected row")
    game.call("_device_action", "settings_increase")
    _expect(is_equal_approx(float(game.settings_values["master_volume"]), 1.0), "touch increase must restore the selected value")
    var saves_before := settings.saves
    _expect(game.call("_device_action", "settings_close"), "touch settings must have an exit without a keyboard")
    _expect(not game.settings_open and game.is_paused and settings.saves == saves_before + 1, "settings close must invoke the in-memory save and return to pause")
    _assert_released("settings close")
    game.call("_device_action", "pause")
    _reset()


func _test_cooldown_weapons_and_overdrive() -> void:
    game.weapon_rank = 5
    game.call("_device_action", "fire", true)
    game.shot_timer = 0.0
    game.call("_update_player", 0.0)
    _expect(game.last_volley_size == 40, "normal mode must preserve the rank-five barrage with wingmen")
    var volley: int = game.volley_count
    var cooldown: float = game.shot_timer
    _expect(game.call("_device_action", "weapon_next") and game.weapon_mode == 2, "device weapon cycling must select missiles")
    _expect(is_equal_approx(game.shot_timer, cooldown), "device weapon switch must preserve shared cooldown")
    game.call("_update_player", 0.0)
    _expect(game.volley_count == volley, "mode switch while held cannot create a free volley")
    game.shot_timer = 0.0
    game.call("_update_player", 0.0)
    _expect(game.special_weapons.get_stats()["missiles_active"] == 4 and game.last_volley_size == 16, "device missile fire must launch four missiles plus twelve wing shots")
    for expected_mode in [3, 4]:
        game.call("_device_action", "weapon_cycle")
        game.shot_timer = 0.0
        game.call("_update_player", 0.0)
        _expect(game.weapon_mode == expected_mode and game.special_weapons.get_stats()["shots_by_mode"][expected_mode] == 1, "device cycle must invoke the actual selected special attack")
        _expect(game.last_volley_size == 12, "energy weapon modes must retain all rank-five wing shots")
    var laser_count: int = game.special_weapons.get_stats()["shots_by_mode"][4]
    _expect(game.call("_device_action", "overdrive"), "charged device overdrive must activate")
    game.call("_update_player", 0.0)
    _expect(game.last_volley_size == 100 and game.weapon_mode == 4, "overdrive must temporarily emit exactly100 while preserving selection")
    _expect(game.special_weapons.get_stats()["shots_by_mode"][4] == laser_count, "overdrive must not also emit a special attack")
    game.overdrive_timer = 0.0
    game.shot_timer = 0.0
    game.call("_update_player", 0.0)
    _expect(game.special_weapons.get_stats()["shots_by_mode"][4] == laser_count + 1 and game.last_volley_size == 12, "selected special weapon must resume after overdrive")
    game.call("_device_action", "fire", false)
    game.call("_device_action", "weapon_next")
    _expect(game.weapon_mode == 1, "cycling after mode4 must wrap to the original barrage")
    var bombs_before: int = game.bombs
    _expect(game.call("_device_action", "bomb") and game.bombs == bombs_before - 1, "device bomb must consume exactly one bomb")
    _reset()


func _test_controller_button_mapping() -> void:
    var mode: int = game.weapon_mode
    _joy(JOY_BUTTON_X, false)
    _expect(game.weapon_mode == mode, "controller button release must not dispatch an action")
    _joy(JOY_BUTTON_X)
    _expect(game.weapon_mode == 2, "controller X must cycle weapons")
    var bombs_before: int = game.bombs
    _joy(JOY_BUTTON_B)
    _expect(game.bombs == bombs_before - 1, "controller B must use one bomb")
    _joy(JOY_BUTTON_Y)
    _expect(game.overdrive_timer > 0.0, "controller Y must start charged overdrive")
    _joy(JOY_BUTTON_START)
    _expect(game.is_paused, "controller Start must pause")
    _assert_released("controller pause")
    _joy(JOY_BUTTON_START)
    _expect(not game.is_paused, "controller Start must resume")
    _joy(JOY_BUTTON_BACK)
    _expect(game.settings_open, "controller Back must open settings")
    _joy(JOY_BUTTON_DPAD_DOWN)
    _expect(game.settings_index == 1, "controller D-pad down must navigate settings")
    _joy(JOY_BUTTON_DPAD_UP)
    _expect(game.settings_index == 0, "controller D-pad up must navigate settings")
    _joy(JOY_BUTTON_DPAD_LEFT)
    _expect(is_equal_approx(float(game.settings_values["master_volume"]), 0.9), "controller D-pad left must adjust settings")
    _joy(JOY_BUTTON_DPAD_RIGHT)
    _joy(JOY_BUTTON_A)
    _expect(not game.settings_open and game.is_paused, "controller A must confirm and close settings")
    _joy(JOY_BUTTON_START)
    _reset()


func _test_death_and_restart() -> void:
    _hold_inputs()
    game.call("_game_over")
    _assert_released("death")
    _expect(not game.call("_device_action", "bomb") and not game.call("_device_action", "overdrive") and not game.call("_device_action", "weapon_next") and not game.call("_device_action", "pause"), "terminal game state must reject combat and pause toggles")
    game.call("_on_web_move", [1.0, 0.0])
    game.call("_on_web_action", ["fire", true])
    _assert_released("dead Web callbacks")
    _joy(JOY_BUTTON_A)
    _expect(not game.is_game_over and game.weapon_mode == 1, "controller A must restart a dead run")
    _assert_released("controller restart")
    _hold_inputs()
    game.call("_restart_game")
    _assert_released("direct restart")
    game.call("_game_over")
    var restart_rect: Rect2 = game.device_controls.get_button_rect("restart")
    _touch(30, restart_rect.get_center(), true)
    _expect(not game.is_game_over, "native touch restart must reach actual main")
    _assert_released("touch restart")
    _touch(30, Vector2.ZERO, false)


func _reset() -> void:
    game.call("_restart_game")
    game.spawn_timer = 1000.0
    game.swarm_timer = 1000.0
    game.rng.seed = 88213
    game.device_controls.get_move_vector()


func _hold_inputs() -> void:
    game.call("_on_web_move", [0.5, -0.5])
    game.call("_on_web_action", ["fire", true])
    _touch(0, Vector2(120.0, 575.0), true)
    var drag := InputEventScreenDrag.new()
    drag.index = 0
    drag.position = Vector2(170.0, 545.0)
    root.push_input(drag, true)
    _touch(1, Vector2(1170.0, 610.0), true)
    _expect(game._web_fire and game.device_controls.wants_fire(), "fixture must hold both Web and native touch fire")
    _expect((game._web_move as Vector2).length() > 0.0 and (game.device_controls.get_move_vector() as Vector2).length() > 0.0, "fixture must hold both movement sources")


func _assert_released(context: String) -> void:
    _expect(not game._web_fire and game._web_move == Vector2.ZERO, context + " must release Web inputs")
    _expect(not game.device_controls.wants_fire() and game.device_controls.get_move_vector() == Vector2.ZERO, context + " must release native touch inputs")
    _expect(game.device_controls.get_stats()["touches"] == 0, context + " must release native finger ownership")


func _touch(index: int, position: Vector2, pressed: bool) -> void:
    var event := InputEventScreenTouch.new()
    event.index = index
    event.position = position
    event.pressed = pressed
    root.push_input(event, true)


func _assert_movement_step(start: Vector3, helper_delta: float, context: String) -> void:
    # CharacterBody3D.move_and_slide() reads the engine frame delta internally;
    # _update_player's argument only drives banking, not the body's movement step.
    # These direct helper calls run outside a physics callback. See Godot4.7.2
    # scene/3d/physics/character_body_3d.cpp:40-42. Startup/load time must not be
    # mistaken for a speed multiplier, nor should the test weaken its speed limit.
    var engine_delta: float = game.player.get_physics_process_delta_time() if Engine.is_in_physics_frame() else game.player.get_process_delta_time()
    var velocity: Vector3 = game.player.velocity
    var displacement: Vector3 = game.player.position - start
    var expected := start + velocity * engine_delta
    expected.x = clampf(expected.x, game.PLAYER_MIN_X, game.PLAYER_MAX_X)
    expected.z = clampf(expected.z, game.PLAYER_MIN_Z, game.PLAYER_MAX_Z)
    var probe := "%s speed=%.7f displacement=%.7f engine_delta=%.7f helper_delta=%.7f" % [context, velocity.length(), displacement.length(), engine_delta, helper_delta]
    print("DEVICE_MOVEMENT_PROBE " + probe)
    _expect(velocity.is_finite() and velocity.length() <= game.PLAYER_SPEED + 0.0001, context + " input cannot multiply velocity; " + probe)
    _expect(displacement.length() <= game.PLAYER_SPEED * engine_delta + 0.0001, context + " movement must respect the actual engine step; " + probe)
    _expect(game.player.position.distance_to(expected) <= 0.0001, context + " displacement must equal engine-integrated velocity within world clamps; " + probe)


func _key(code: Key) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = true
    game.call("_unhandled_key_input", event)


func _joy(button: JoyButton, pressed: bool = true) -> void:
    var event := InputEventJoypadButton.new()
    event.button_index = button
    event.pressed = pressed
    game.call("_unhandled_input", event)


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)

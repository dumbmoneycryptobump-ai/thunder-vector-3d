extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings_store.gd")

var failures: Array[String] = []
var _main_scene: Node


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Settings UI test could not load res://main.tscn")
        quit(1)
        return

    var test_path := "user://settings_ui_test_%d.cfg" % OS.get_process_id()
    _remove_test_file(test_path)
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.settings_store = SettingsStoreScript.new(test_path)
    _main_scene.settings_values = SettingsStoreScript.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")

    _send_key(KEY_O)
    _expect(_main_scene.settings_open, "O should open settings")
    _expect(_main_scene.settings_overlay.visible, "settings overlay should be visible")
    _expect(_main_scene.is_paused, "opening settings should pause gameplay")

    _send_key(KEY_LEFT)
    _send_key(KEY_DOWN)
    _send_key(KEY_LEFT)
    _send_key(KEY_DOWN)
    _send_key(KEY_RIGHT)
    _send_key(KEY_DOWN)
    _send_key(KEY_RIGHT)
    _send_key(KEY_DOWN)
    _send_key(KEY_RIGHT)
    _send_key(KEY_ENTER)

    _expect(not _main_scene.settings_open, "Enter should close settings after save")
    _expect(not _main_scene.settings_overlay.visible, "saved settings overlay should hide")
    _expect(_main_scene.is_paused, "closing settings should return to pause")

    var persisted: Dictionary = SettingsStoreScript.new(test_path).load_settings()
    _expect(is_equal_approx(float(persisted["master_volume"]), 0.9), "UI should change master volume")
    _expect(is_equal_approx(float(persisted["sfx_volume"]), 0.9), "UI should change SFX volume")
    _expect(persisted["display_mode"] == "fullscreen", "UI should change display mode")
    _expect(persisted["resolution"] == "1600x900", "UI should change resolution")
    _expect(persisted["difficulty"] == "hard", "UI should change difficulty")
    _expect(is_equal_approx(float(_main_scene.difficulty_profile["enemy_bullet_speed_scale"]), 1.15), "UI difficulty should apply immediately")

    _send_key(KEY_P)
    _expect(not _main_scene.is_paused, "P should resume after returning from settings")

    _remove_test_file(test_path)
    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("SETTINGS_UI_TEST_PASS keyboard=ready pause_flow=ready persistence=ready")
        quit(0)
    else:
        for failure in failures:
            push_error("SETTINGS_UI_TEST_FAIL: %s" % failure)
        quit(1)


func _send_key(keycode: int) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    _main_scene.call("_unhandled_key_input", event)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _remove_test_file(test_path: String) -> void:
    if FileAccess.file_exists(test_path):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))

extends SceneTree

const SettingsStoreScript := preload("res://scripts/settings_store.gd")

var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var test_path := "user://settings_store_test_%d.cfg" % OS.get_process_id()
    _remove_test_file(test_path)

    var store = SettingsStoreScript.new(test_path)
    var save_error: Error = store.save_settings({
        "master_volume": 0.4,
        "sfx_volume": 0.7,
        "display_mode": "fullscreen",
        "resolution": "1600x900",
        "difficulty": "hard",
    })
    _expect(save_error == OK, "valid settings should save")

    var reloaded = SettingsStoreScript.new(test_path)
    var persisted: Dictionary = reloaded.load_settings()
    _expect(is_equal_approx(float(persisted["master_volume"]), 0.4), "master volume should persist")
    _expect(is_equal_approx(float(persisted["sfx_volume"]), 0.7), "SFX volume should persist")
    _expect(persisted["display_mode"] == "fullscreen", "display mode should persist")
    _expect(persisted["resolution"] == "1600x900", "resolution should persist")
    _expect(persisted["difficulty"] == "hard", "difficulty should persist")
    _expect(reloaded.get_resolution_size() == Vector2i(1600, 900), "resolution should map to a window size")
    _expect(store.save_settings({"resolution": "1280x720"}) == OK, "existing small-window preference fixture should save")
    _expect(SettingsStoreScript.new(test_path).load_settings()["resolution"] == "1280x720", "new defaults must preserve an existing 1280x720 preference")

    save_error = store.save_settings({
        "master_volume": 4.0,
        "sfx_volume": -2.0,
        "display_mode": "invalid",
        "resolution": "640x480",
        "difficulty": "nightmare",
    })
    _expect(save_error == OK, "sanitized settings should save")
    var sanitized: Dictionary = SettingsStoreScript.new(test_path).load_settings()
    _expect(is_equal_approx(float(sanitized["master_volume"]), 1.0), "master volume should clamp to one")
    _expect(is_equal_approx(float(sanitized["sfx_volume"]), 0.0), "SFX volume should clamp to zero")
    _expect(sanitized["display_mode"] == "windowed", "invalid display mode should use default")
    _expect(sanitized["resolution"] == "1600x900", "invalid resolution should use the expanded default")
    _expect(sanitized["difficulty"] == "normal", "invalid difficulty should use default")

    var invalid_config := ConfigFile.new()
    invalid_config.set_value("audio", "master_volume", "loud")
    invalid_config.set_value("audio", "sfx_volume", [])
    invalid_config.set_value("display", "mode", 42)
    invalid_config.set_value("display", "resolution", false)
    invalid_config.set_value("gameplay", "difficulty", Vector2.ZERO)
    _expect(invalid_config.save(test_path) == OK, "invalid fixture should save")
    var recovered: Dictionary = SettingsStoreScript.new(test_path).load_settings()
    _expect(recovered == SettingsStoreScript.DEFAULTS, "invalid types should recover all defaults")

    var profiles = SettingsStoreScript.new(test_path)
    var easy: Dictionary = profiles.get_difficulty_profile("easy")
    var normal: Dictionary = profiles.get_difficulty_profile("normal")
    var hard: Dictionary = profiles.get_difficulty_profile("hard")
    _expect(float(easy["spawn_interval_scale"]) > float(normal["spawn_interval_scale"]), "easy should spawn more slowly")
    _expect(float(normal["spawn_interval_scale"]) > float(hard["spawn_interval_scale"]), "hard should spawn faster")
    _expect(float(easy["enemy_bullet_speed_scale"]) < float(normal["enemy_bullet_speed_scale"]), "easy bullets should be slower")
    _expect(float(normal["enemy_bullet_speed_scale"]) < float(hard["enemy_bullet_speed_scale"]), "hard bullets should be faster")
    _expect(float(easy["enemy_fire_interval_scale"]) > float(hard["enemy_fire_interval_scale"]), "easy should fire less often")
    _expect(AudioServer.get_bus_index(&"SFX") >= 0, "SFX audio bus should exist")

    _remove_test_file(test_path)
    if failures.is_empty():
        print("SETTINGS_STORE_TEST_PASS persistence=safe validation=safe profiles=monotonic sfx_bus=ready")
        quit(0)
    else:
        for failure in failures:
            push_error("SETTINGS_STORE_TEST_FAIL: %s" % failure)
        quit(1)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _remove_test_file(test_path: String) -> void:
    var absolute_path := ProjectSettings.globalize_path(test_path)
    if FileAccess.file_exists(test_path):
        DirAccess.remove_absolute(absolute_path)

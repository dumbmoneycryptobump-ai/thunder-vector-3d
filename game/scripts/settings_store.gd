extends RefCounted

const SETTINGS_PATH := "user://settings.cfg"
const DISPLAY_MODES := ["windowed", "fullscreen"]
const RESOLUTIONS := ["1280x720", "1600x900", "1920x1080"]
const DIFFICULTIES := ["easy", "normal", "hard"]
const DEFAULTS := {
    "master_volume": 1.0,
    "sfx_volume": 1.0,
    "display_mode": "windowed",
    "resolution": "1600x900",
    "difficulty": "normal",
}
const DIFFICULTY_PROFILES := {
    "easy": {
        "spawn_interval_scale": 1.20,
        "enemy_bullet_speed_scale": 0.85,
        "enemy_fire_interval_scale": 1.20,
    },
    "normal": {
        "spawn_interval_scale": 1.0,
        "enemy_bullet_speed_scale": 1.0,
        "enemy_fire_interval_scale": 1.0,
    },
    "hard": {
        "spawn_interval_scale": 0.85,
        "enemy_bullet_speed_scale": 1.15,
        "enemy_fire_interval_scale": 0.85,
    },
}

var path: String
var values: Dictionary


func _init(settings_path: String = SETTINGS_PATH) -> void:
    path = settings_path
    values = DEFAULTS.duplicate(true)


func load_settings() -> Dictionary:
    values = DEFAULTS.duplicate(true)
    var config := ConfigFile.new()
    var error := config.load(path)
    if error == ERR_FILE_NOT_FOUND:
        return values.duplicate(true)
    if error != OK:
        push_warning("Could not load settings from %s (error %d); defaults restored." % [path, error])
        return values.duplicate(true)

    values = _sanitize({
        "master_volume": config.get_value("audio", "master_volume", DEFAULTS["master_volume"]),
        "sfx_volume": config.get_value("audio", "sfx_volume", DEFAULTS["sfx_volume"]),
        "display_mode": config.get_value("display", "mode", DEFAULTS["display_mode"]),
        "resolution": config.get_value("display", "resolution", DEFAULTS["resolution"]),
        "difficulty": config.get_value("gameplay", "difficulty", DEFAULTS["difficulty"]),
    })
    return values.duplicate(true)


func save_settings(candidate: Dictionary) -> Error:
    values = _sanitize(candidate)
    var config := ConfigFile.new()
    config.set_value("meta", "schema_version", 1)
    config.set_value("audio", "master_volume", values["master_volume"])
    config.set_value("audio", "sfx_volume", values["sfx_volume"])
    config.set_value("display", "mode", values["display_mode"])
    config.set_value("display", "resolution", values["resolution"])
    config.set_value("gameplay", "difficulty", values["difficulty"])
    var error := config.save(path)
    if error != OK:
        push_warning("Could not save settings to %s (error %d)." % [path, error])
    return error


func get_difficulty_profile(difficulty_name: String = "") -> Dictionary:
    var selected := difficulty_name if difficulty_name in DIFFICULTIES else str(values["difficulty"])
    if selected not in DIFFICULTIES:
        selected = "normal"
    return DIFFICULTY_PROFILES[selected].duplicate(true)


func get_resolution_size(resolution_name: String = "") -> Vector2i:
    var selected := resolution_name if resolution_name in RESOLUTIONS else str(values["resolution"])
    match selected:
        "1600x900":
            return Vector2i(1600, 900)
        "1920x1080":
            return Vector2i(1920, 1080)
        _:
            return Vector2i(1280, 720)


func _sanitize(candidate: Dictionary) -> Dictionary:
    return {
        "master_volume": _sanitize_volume(candidate.get("master_volume", DEFAULTS["master_volume"]), float(DEFAULTS["master_volume"])),
        "sfx_volume": _sanitize_volume(candidate.get("sfx_volume", DEFAULTS["sfx_volume"]), float(DEFAULTS["sfx_volume"])),
        "display_mode": _sanitize_choice(candidate.get("display_mode", DEFAULTS["display_mode"]), DISPLAY_MODES, str(DEFAULTS["display_mode"])),
        "resolution": _sanitize_choice(candidate.get("resolution", DEFAULTS["resolution"]), RESOLUTIONS, str(DEFAULTS["resolution"])),
        "difficulty": _sanitize_choice(candidate.get("difficulty", DEFAULTS["difficulty"]), DIFFICULTIES, str(DEFAULTS["difficulty"])),
    }


func _sanitize_volume(value: Variant, fallback: float) -> float:
    if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
        return fallback
    return clampf(float(value), 0.0, 1.0)


func _sanitize_choice(value: Variant, allowed: Array, fallback: String) -> String:
    if typeof(value) != TYPE_STRING:
        return fallback
    var selected := str(value)
    return selected if selected in allowed else fallback

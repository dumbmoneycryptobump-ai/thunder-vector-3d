extends "res://tests/capture_arcade_preview.gd"

# Staged visual fixture, not evidence of a naturally generated wave or human play.
# Run with a real window: -- --sector 0 --width 1280 --output C:/task-output/map.png
const MAP_SETTINGS := preload("res://scripts/settings_store.gd")
const MAP_SEED := 20261004

var _sector := 0
var _width := 1280
var _map_output := ""
var _capture_finished := false


func _capture_preview() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("MAP_PREVIEW_SKIPPED: requires a real window; no headless frame_post_draw wait")
        quit(1)
        return
    if not _parse_map_arguments():
        quit(1)
        return
    create_timer(45.0, true, false, true).timeout.connect(_capture_watchdog)
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("MAP_PREVIEW_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    # Settings defaults are applied only in memory. No save_settings call is made.
    _main_scene.settings_values = MAP_SETTINGS.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")
    _main_scene.set_process(false)
    _main_scene.set_physics_process(false)
    _main_scene.set_process_unhandled_key_input(false)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_size(Vector2i(_width, _width * 9 / 16))
    var master_bus := AudioServer.get_bus_index(&"Master")
    if master_bus >= 0:
        AudioServer.set_bus_mute(master_bus, true)
    if not is_instance_valid(_main_scene.get("map_scenery")):
        push_error("MAP_PREVIEW_FAIL: map_scenery integration is missing")
        await _close_capture(1)
        return
    _stage_showcase()
    if not _validate_showcase():
        await _close_capture(1)
        return
    # Only render/layout may settle; main gameplay and cosmetics remain frozen.
    for frame_index in range(8):
        await process_frame
    await RenderingServer.frame_post_draw
    if _capture_finished:
        return
    var captured := root.get_texture().get_image()
    if captured == null or captured.is_empty():
        push_error("MAP_PREVIEW_FAIL: empty viewport image")
        await _close_capture(1)
        return
    if captured.get_width() != _width or captured.get_height() != _width * 9 / 16:
        push_error("MAP_PREVIEW_FAIL: requested viewport size did not settle")
        await _close_capture(1)
        return
    var error := captured.save_png(_map_output)
    if error != OK:
        push_error("MAP_PREVIEW_FAIL: PNG save failed: %d" % error)
        await _close_capture(1)
        return
    var scenery: Node = _main_scene.get("map_scenery")
    print("MAP_PREVIEW_JSON " + JSON.stringify({
        "fixture": "staged arcade showcase; not a natural wave or playthrough",
        "sector": _sector,
        "path": _map_output,
        "width": captured.get_width(),
        "height": captured.get_height(),
        "display_driver": DisplayServer.get_name(),
        "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
        "last_volley_size": int(_main_scene.last_volley_size),
        "active_player_bullets": get_nodes_in_group("player_bullet").size(),
        "visible_wingmen": 4,
        "main_process_enabled": _main_scene.is_processing(),
        "main_physics_enabled": _main_scene.is_physics_processing(),
        "scenery": scenery.call("get_stats") if scenery.has_method("get_stats") else {},
        "settings_writes": 0,
    }))
    print("MAP_PREVIEW_PASS sector=%d size=%dx%d" % [_sector, captured.get_width(), captured.get_height()])
    await _close_capture(0)


func _stage_showcase() -> void:
    # Reuse the existing scout/heavy/Boss, interceptor/bomber, pickups and volley.
    super._stage_showcase()
    _main_scene.bosses_defeated = _sector
    _main_scene.call("_set_sector", _sector)
    var scenery: Node = _main_scene.get("map_scenery")
    if scenery.has_method("advance"):
        scenery.call("advance", 1.5)
    var fixture_rng := RandomNumberGenerator.new()
    fixture_rng.seed = MAP_SEED
    for star in _main_scene.stars:
        star.position = Vector3(fixture_rng.randf_range(-11.0, 11.0), fixture_rng.randf_range(-0.7, 3.6), fixture_rng.randf_range(-13.0, 11.0))
        star.scale = Vector3.ONE * fixture_rng.randf_range(0.45, 1.65)
    _main_scene.ui_pool.visible = false
    _main_scene.ui_center.visible = false
    _main_scene.call("_update_ui")


func _validate_showcase() -> bool:
    var roles: Dictionary = {}
    for enemy in get_nodes_in_group("enemy"):
        var role := "boss" if bool(enemy.get_meta("is_boss", false)) else str(enemy.get_meta("archetype", "standard"))
        if role == "standard":
            role = str(enemy.get_meta("pool_kind", ""))
        roles[role] = true
    for expected in ["scout", "heavy", "boss", "interceptor", "bomber", "fodder"]:
        if not roles.has(expected):
            push_error("MAP_PREVIEW_FAIL: staged enemy role missing: %s" % expected)
            return false
    var pickups: Dictionary = {}
    for pickup in get_nodes_in_group("pickup"):
        pickups[str(pickup.get_meta("kind"))] = true
    for expected in ["power", "health", "bomb", "shield"]:
        if not pickups.has(expected):
            push_error("MAP_PREVIEW_FAIL: staged pickup missing: %s" % expected)
            return false
    var visible_wings := 0
    for wing in _main_scene.wingmen:
        if wing.visible:
            visible_wings += 1
    if visible_wings != 4 or int(_main_scene.last_volley_size) != 100:
        push_error("MAP_PREVIEW_FAIL: expected four wingmen and one actual 100-shot volley")
        return false
    return true


func _parse_map_arguments() -> bool:
    var args := OS.get_cmdline_user_args()
    var index := 0
    while index < args.size():
        var option: String = args[index]
        if option not in ["--sector", "--width", "--output"] or index + 1 >= args.size():
            push_error("MAP_PREVIEW_FAIL: expected --sector <0|1|2>, --width <1280|1920>, --output <absolute PNG path>")
            return false
        var value: String = args[index + 1]
        match option:
            "--sector":
                if not value.is_valid_int() or int(value) not in [0, 1, 2]:
                    push_error("MAP_PREVIEW_FAIL: --sector must be 0, 1 or 2")
                    return false
                _sector = int(value)
            "--width":
                if not value.is_valid_int() or int(value) not in [1280, 1920]:
                    push_error("MAP_PREVIEW_FAIL: --width must be 1280 or 1920")
                    return false
                _width = int(value)
            "--output":
                _map_output = value.replace("\\", "/")
        index += 2
    if not _map_output.is_absolute_path() or not _map_output.to_lower().ends_with(".png") or not DirAccess.dir_exists_absolute(_map_output.get_base_dir()):
        push_error("MAP_PREVIEW_FAIL: --output must name a PNG inside an existing absolute task-output directory")
        return false
    return true


func _capture_watchdog() -> void:
    if _capture_finished:
        return
    _capture_finished = true
    push_error("MAP_PREVIEW_FAIL: 45-second rendered-frame watchdog expired")
    if is_instance_valid(_main_scene):
        _main_scene.call("prepare_for_shutdown")
    quit(1)


func _close_capture(code: int) -> void:
    _capture_finished = true
    if is_instance_valid(_main_scene):
        _main_scene.call("prepare_for_shutdown")
        _main_scene.queue_free()
    await process_frame
    await process_frame
    quit(code)

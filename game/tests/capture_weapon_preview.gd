extends "res://tests/capture_map_preview.gd"

# Actual weapon effects against staged durable targets; not natural encounter flow.
# -- --mode 2|3|4 --output C:/task-output/weapon.png [--width 1280|1920]
var _mode := 2
var _weapon_capture_stats: Dictionary = {}


func _parse_map_arguments() -> bool:
    var args := OS.get_cmdline_user_args()
    var index := 0
    while index < args.size():
        var option: String = args[index]
        if option not in ["--mode", "--width", "--output"] or index + 1 >= args.size():
            push_error("WEAPON_PREVIEW_FAIL: expected --mode <2|3|4>, --width <1280|1920> or --output <absolute PNG path>")
            return false
        var value: String = args[index + 1]
        match option:
            "--mode":
                if not value.is_valid_int() or int(value) not in [2, 3, 4]:
                    push_error("WEAPON_PREVIEW_FAIL: --mode must be 2, 3 or 4")
                    return false
                _mode = int(value)
            "--width":
                if not value.is_valid_int() or int(value) not in [1280, 1920]:
                    push_error("WEAPON_PREVIEW_FAIL: --width must be 1280 or 1920")
                    return false
                _width = int(value)
            "--output":
                _map_output = value.replace("\\", "/")
        index += 2
    if not _map_output.is_absolute_path() or not _map_output.to_lower().ends_with(".png") or not DirAccess.dir_exists_absolute(_map_output.get_base_dir()):
        push_error("WEAPON_PREVIEW_FAIL: --output must name a PNG inside an existing absolute task-output directory")
        return false
    _sector = _mode - 2
    return true


func _stage_showcase() -> void:
    if _main_scene.get("special_weapons") == null:
        return
    _main_scene.rng.seed = MAP_SEED
    _main_scene.weapon_rank = 5
    _main_scene.weapon_mode = _mode
    _main_scene.level = 6
    _main_scene.score = 15_420
    _main_scene.combo = 24
    _main_scene.best_combo = 48
    _main_scene.combo_timer = 3.0
    _main_scene.overdrive_timer = 0.0
    _main_scene.overdrive_charge = 100.0
    _main_scene.wave_number = 8
    _main_scene.wave_name = "武器試射展示"
    _main_scene.bosses_defeated = _sector
    _main_scene.call("_set_sector", _sector)
    _main_scene.map_scenery.reset()
    _main_scene.map_scenery.advance(1.5)
    _main_scene.player.position = Vector3(0.0, 0.0, 6.3)
    var target_positions: Array[Vector3] = [Vector3(0.0, 0.0, 1.0), Vector3(-2.5, 0.0, -2.0), Vector3(0.5, 0.0, -5.0), Vector3(3.5, 0.0, -7.0), Vector3(0.0, 0.0, -10.0)]
    if _mode == 4:
        target_positions = [Vector3(-0.65, 0.0, 1.0), Vector3(0.65, 0.0, -2.0), Vector3(-0.65, 0.0, -5.0), Vector3(0.65, 0.0, -8.0), Vector3(0.0, 0.0, -11.0)]
    for index in range(target_positions.size()):
        var enemy: Node3D = _main_scene.call("_activate_enemy", "heavy" if index % 2 == 0 else "scout", target_positions[index], "standard")
        enemy.set_meta("hp", 100)
    _main_scene.is_paused = false
    _main_scene.call("_fire_player")
    if _mode == 2:
        _main_scene.special_weapons.advance(0.15)
    _main_scene.call("_update_bullets", 0.12)
    _main_scene.call("_sync_player_bullet_batch")
    _main_scene.is_paused = true
    _main_scene.ui_pool.visible = false
    _main_scene.ui_center.visible = false
    _main_scene.call("_update_ui")
    _weapon_capture_stats = _main_scene.special_weapons.get_stats()


func _validate_showcase() -> bool:
    if _main_scene.get("special_weapons") == null:
        push_error("WEAPON_PREVIEW_FAIL: weapon integration is missing")
        return false
    var visible_wings := 0
    for wing in _main_scene.wingmen:
        if wing.visible:
            visible_wings += 1
    if visible_wings != 4 or float(_main_scene.overdrive_timer) != 0.0 or int(_main_scene.volley_count) != 1:
        push_error("WEAPON_PREVIEW_FAIL: expected four wings and one successful non-overdrive volley")
        return false
    var expected_missiles := 4 if _mode == 2 else 0
    var expected_segments := 0 if _mode == 2 else (20 if _mode == 3 else 4)
    if int(_weapon_capture_stats.get("missiles_active", -1)) != expected_missiles or int(_weapon_capture_stats.get("segments_active", -1)) != expected_segments:
        push_error("WEAPON_PREVIEW_FAIL: expected actual active selected-weapon visuals")
        return false
    if _mode != 2 and int(_weapon_capture_stats.get("last_hits", -1)) != 5:
        push_error("WEAPON_PREVIEW_FAIL: staged chain/laser did not damage all five intended targets")
        return false
    print("WEAPON_PREVIEW_JSON " + JSON.stringify({"fixture": "actual selected weapon against staged durable targets; not natural encounter flow", "mode": _mode, "sector": _sector, "stats": _weapon_capture_stats, "overdrive": false, "settings_writes": 0}))
    return true


func _close_capture(code: int) -> void:
    if code == 0:
        print("WEAPON_PREVIEW_PASS mode=%d path=%s" % [_mode, _map_output])
    await super._close_capture(code)

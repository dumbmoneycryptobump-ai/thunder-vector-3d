extends "res://tests/arcade_window_benchmark.gd"

# Real GL frame intervals for a staged weapon workload, not universal gameplay FPS.
# Run modes sequentially without --headless/--fixed-fps: -- --mode 2|3|4
# Optional --output C:/task-output/weapon-timing.png is captured AFTER measurement.
const WEAPON_SCOUTS := 16
const WEAPON_HEAVIES := 4
const MEASURED_FRAMES := 600
var _mode := 2
var _missiles_peak := 0
var _segments_peak := 0
var _unexpected_volleys := 0


func _run_benchmark() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("WEAPON_WINDOW_BENCHMARK_SKIPPED: requires a real GL window; no headless timing claims")
        quit(1)
        return
    if not _parse_arguments():
        _print_failures()
        quit(1)
        return
    if ProjectSettings.get_setting("rendering/renderer/rendering_method") != "gl_compatibility":
        push_error("WEAPON_WINDOW_BENCHMARK_FAIL: GL Compatibility is required")
        quit(1)
        return
    create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_watchdog_timeout)
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        push_error("WEAPON_WINDOW_BENCHMARK_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process_unhandled_key_input(false)
    _main_scene.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings") # Memory only: never save personal settings.
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_size(Vector2i(1280, 720))
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    OS.low_processor_usage_mode = false
    var master_bus := AudioServer.get_bus_index(&"Master")
    if master_bus >= 0:
        AudioServer.set_bus_mute(master_bus, true)
    # The existing harmless fixture path invokes the normal cooldown/fire routine.
    # Do not call special_weapons.fire or _fire_player directly from this fixture.
    _main_scene.set("_pool_stress_mode", true)
    _main_scene.weapon_mode = _mode
    _main_scene.weapon_rank = 5
    _main_scene.level = 6
    _main_scene.overdrive_timer = 0.0
    _main_scene.overdrive_charge = 0.0
    _main_scene.hp = _main_scene.PLAYER_MAX_HP
    _main_scene.is_paused = false
    _main_scene.next_boss_kill_target = 2_000_000_000
    _main_scene.spawn_timer = 1000.0
    _main_scene.swarm_timer = 1000.0
    _main_scene.shot_timer = 0.0
    _main_scene.ui_pool.visible = false
    _seed_environment()
    _main_scene.rng.seed = SEED
    _maintain_enemy_fixture()
    var nodes_initial := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
    var pools_initial: Dictionary = _main_scene.call("get_pool_stats")
    print("WEAPON_WINDOW_BENCHMARK_START mode=%d warmup=120 measured=600 size=1280x720 enemies=16_scouts+4_heavies no_overdrive=true audio_muted=true" % _mode)
    var previous_draw_usec := 0
    var start_usec := Time.get_ticks_usec()
    for frame_index in range(WARMUP_FRAMES + MEASURED_FRAMES):
        await process_frame
        if _finished:
            return
        _tick_fixture(frame_index)
        await RenderingServer.frame_post_draw
        if _finished:
            return
        var current_usec := Time.get_ticks_usec()
        if frame_index >= WARMUP_FRAMES and previous_draw_usec > 0:
            _samples_ms.append(float(current_usec - previous_draw_usec) / 1000.0)
        previous_draw_usec = current_usec
        _sample_counts()
        var weapon_stats: Dictionary = _main_scene.special_weapons.get_stats()
        _missiles_peak = maxi(_missiles_peak, int(weapon_stats["missiles_active"]))
        _segments_peak = maxi(_segments_peak, int(weapon_stats["segments_active"]))
    var elapsed_seconds := float(Time.get_ticks_usec() - start_usec) / 1_000_000.0
    var pools_final: Dictionary = _main_scene.call("get_pool_stats")
    var weapons_final: Dictionary = _main_scene.special_weapons.get_stats()
    _validate_run(pools_initial, pools_final, weapons_final)
    # Texture/instance readbacks and optional PNG encoding are not timed samples.
    var viewport_proof := _read_viewport()
    _check_batch_readback("non_overdrive_wingguns")
    _samples_ms.sort()
    var total_ms := 0.0
    for value in _samples_ms:
        total_ms += value
    print("WEAPON_WINDOW_BENCHMARK_JSON " + JSON.stringify({
        "fixture": "16 standard scouts +4 heavies at200HP replenished from fixed pools; rank5 four wingmen; real cooldown autofire; no overdrive; no bosses; audio muted",
        "measurement": "Wall milliseconds between real post-draw signals including fixture/process/render scheduling; not isolated GPU time or general gameplay FPS",
        "mode": _mode, "engine": Engine.get_version_info()["string"],
        "display_driver": DisplayServer.get_name(),
        "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
        "adapter": RenderingServer.get_video_adapter_name(),
        "vsync_mode": DisplayServer.window_get_vsync_mode(),
        "seed": SEED, "warmup_frames": WARMUP_FRAMES,
        "rendered_frames": WARMUP_FRAMES + MEASURED_FRAMES,
        "measured_intervals": _samples_ms.size(), "wall_seconds": elapsed_seconds,
        "simulation_seconds": float(WARMUP_FRAMES + MEASURED_FRAMES) * STEP,
        "frame_ms_mean": total_ms / float(_samples_ms.size()) if not _samples_ms.is_empty() else 0.0,
        "frame_ms_median": _percentile(0.5), "frame_ms_p95": _percentile(0.95),
        "frame_ms_max": _samples_ms.back() if not _samples_ms.is_empty() else 0.0,
        "nodes_initial": nodes_initial, "nodes_peak": _max_nodes,
        "enemies_min": _min_enemies, "enemies_max": _max_enemies,
        "max_player_bullets": _max_player_bullets, "max_enemy_bullets": _max_enemy_bullets,
        "max_missiles": _missiles_peak, "max_segments": _segments_peak,
        "volleys": int(_main_scene.volley_count), "unexpected_volleys": _unexpected_volleys,
        "pool_stats": pools_final, "weapon_stats": weapons_final,
        "viewport_readback": viewport_proof, "batch_readback": _batch_readback,
        "settings_writes": 0, "failures": _failures,
    }))
    _print_failures()
    _finished = true
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    quit(0 if _failures.is_empty() else 1)


func _parse_arguments() -> bool:
    var args := OS.get_cmdline_user_args()
    var index := 0
    while index < args.size():
        var option: String = args[index]
        if option not in ["--mode", "--output"] or index + 1 >= args.size():
            _failures.append("expected --mode <2|3|4> or --output <absolute PNG path>")
            return false
        var value: String = args[index + 1]
        if option == "--mode":
            if not value.is_valid_int() or int(value) not in [2, 3, 4]:
                _failures.append("--mode must be 2, 3 or 4")
                return false
            _mode = int(value)
        else:
            _output = value.replace("\\", "/")
            if not _output.is_absolute_path() or not _output.to_lower().ends_with(".png") or not DirAccess.dir_exists_absolute(_output.get_base_dir()):
                _failures.append("--output must name a PNG inside an existing absolute task-output directory")
                return false
        index += 2
    return true


func _tick_fixture(frame_index: int) -> void:
    _main_scene.weapon_rank = 5
    _main_scene.level = 6
    _main_scene.hp = _main_scene.PLAYER_MAX_HP
    _main_scene.player.position = Vector3(sin(float(frame_index) * STEP * 0.75) * 2.5, 0.0, 6.5)
    _main_scene.spawn_timer = 1000.0
    _main_scene.swarm_timer = 1000.0
    var previous_volleys: int = _main_scene.volley_count
    _main_scene.call("_physics_process", STEP)
    if int(_main_scene.volley_count) > previous_volleys:
        if int(_main_scene.last_volley_size) != (16 if _mode == 2 else 12):
            _unexpected_volleys += 1
    _maintain_enemy_fixture()


func _maintain_enemy_fixture() -> void:
    var counts := {"scout": 0, "heavy": 0}
    for enemy in get_nodes_in_group("enemy"):
        var kind := str(enemy.get_meta("pool_kind", ""))
        if counts.has(kind):
            counts[kind] += 1
    for kind in ["scout", "heavy"]:
        var target_count := WEAPON_SCOUTS if kind == "scout" else WEAPON_HEAVIES
        for index in range(int(counts[kind]), target_count):
            var lane := _spawn_serial % 4
            var row := (_spawn_serial / 4) % 4
            var at := Vector3(-3.0 + float(lane) * 2.0, 0.0, -3.0 - float(row) * 2.2)
            if kind == "heavy":
                at.z -= 1.0
            var enemy: Node3D = _main_scene.call("_activate_enemy", kind, at, "standard")
            if enemy != null:
                enemy.set_meta("hp", 200)
                enemy.set_meta("speed", 0.0)
                enemy.set_meta("wave", 0.0)
            _spawn_serial += 1


func _validate_run(initial: Dictionary, final: Dictionary, weapons: Dictionary) -> void:
    if _samples_ms.size() != MEASURED_FRAMES:
        _failures.append("expected exactly600 measured intervals after120 warmup frames")
    if _min_enemies != 20 or _max_enemies != 20:
        _failures.append("bounded replenished enemy fixture did not stay at20 actors")
    if _unexpected_volleys != 0 or float(_main_scene.overdrive_timer) != 0.0 or int(_main_scene.weapon_mode) != _mode:
        _failures.append("selected non-overdrive weapon workload changed unexpectedly")
    var wings := 0
    for wing in _main_scene.wingmen:
        wings += int(wing.visible)
    if wings != 4 or int(weapons["hits_by_mode"][_mode]) <= 0 or int(weapons["shots_by_mode"][_mode]) != int(_main_scene.volley_count):
        _failures.append("fixture did not exercise actual selected-weapon hits and four-wing volleys")
    if int(weapons["overflow"]) != 0 or _missiles_peak > 64 or _segments_peak > 96:
        _failures.append("special weapon resource capacity overflowed")
    for kind in final:
        if int(final[kind]["created"]) != int(initial[kind]["created"]) or int(final[kind]["exhausted"]) != 0:
            _failures.append("shared pool grew or exhausted: %s" % kind)


func _read_viewport() -> Dictionary:
    var captured := root.get_texture().get_image()
    if captured == null or captured.is_empty():
        _failures.append("real viewport readback was empty")
        return {}
    if captured.get_width() != 1280 or captured.get_height() != 720:
        _failures.append("rendered viewport was not1280x720")
    var colors: Dictionary = {}
    for y in range(9):
        for x in range(16):
            var pixel := captured.get_pixel(int((float(x) + 0.5) * captured.get_width() / 16.0), int((float(y) + 0.5) * captured.get_height() / 9.0))
            colors[pixel.to_rgba32()] = true
    if colors.size() < 5:
        _failures.append("viewport readback was unexpectedly uniform")
    var digest := HashingContext.new()
    digest.start(HashingContext.HASH_SHA256)
    digest.update(captured.get_data())
    if not _output.is_empty():
        var error := captured.save_png(_output)
        if error != OK:
            _failures.append("optional viewport PNG could not save: %d" % error)
    return {"width": captured.get_width(), "height": captured.get_height(), "sampled_unique_colors": colors.size(), "raw_pixels_sha256": digest.finish().hex_encode(), "optional_path": _output, "timed": false}


func _print_failures() -> void:
    for failure in _failures:
        push_error("WEAPON_WINDOW_BENCHMARK_FAIL: " + failure)

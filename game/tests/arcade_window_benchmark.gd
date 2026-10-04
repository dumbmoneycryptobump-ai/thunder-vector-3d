extends SceneTree

# Real rendered-frame fixture, not human play validation or a universal FPS claim.
# Run without --headless/--fixed-fps, optionally append: -- --frames 720 --output C:/task-temp/arcade.png
const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const SEED := 20261004
const WARMUP_FRAMES := 120
const DEFAULT_FRAMES := 720
const STEP := 1.0 / 60.0
const SCOUT_TARGET := 24
const HEAVY_TARGET := 4
const WATCHDOG_SECONDS := 90.0

var _main_scene: Node
var _frames := DEFAULT_FRAMES
var _output := ""
var _failures: Array[String] = []
var _samples_ms: Array[float] = []
var _spawn_serial := 0
var _max_player_bullets := 0
var _max_enemy_bullets := 0
var _max_nodes := 0
var _min_enemies := 2_147_483_647
var _max_enemies := 0
var _hundred_volleys := 0
var _other_volleys := 0
var _finished := false
var _batch_readback: Array[Dictionary] = []


func _initialize() -> void:
    call_deferred("_run_benchmark")


func _run_benchmark() -> void:
    if DisplayServer.get_name() == "headless":
        push_error("ARCADE_WINDOW_BENCHMARK_SKIPPED: requires a real window; frame_post_draw is not awaited under headless")
        quit(1)
        return
    if not _parse_arguments():
        _print_failures()
        quit(1)
        return
    if ProjectSettings.get_setting("rendering/renderer/rendering_method") != "gl_compatibility":
        push_error("ARCADE_WINDOW_BENCHMARK_FAIL: this fixture requires GL Compatibility")
        quit(1)
        return
    create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_watchdog_timeout)
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("ARCADE_WINDOW_BENCHMARK_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process_unhandled_key_input(false)
    _main_scene.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_size(Vector2i(1280, 720))
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
    Engine.max_fps = 0
    OS.low_processor_usage_mode = false
    var master_bus := AudioServer.get_bus_index(&"Master")
    if master_bus >= 0:
        AudioServer.set_bus_mute(master_bus, true)
    _main_scene.set("_pool_stress_mode", true)
    _main_scene.weapon_rank = 5
    _main_scene.level = 6
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
    print("ARCADE_WINDOW_BENCHMARK_START frames=%d warmup=%d fixture=24_fodder+4_heavy rank=5 overdrive=test_forced simulation_step=1/60 output=%s" % [_frames, WARMUP_FRAMES, "requested" if not _output.is_empty() else "none"])
    var previous_draw_usec := 0
    var start_usec := Time.get_ticks_usec()
    for frame_index in range(_frames):
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
    var elapsed_seconds := float(Time.get_ticks_usec() - start_usec) / 1_000_000.0
    var final_pool_stats: Dictionary = _main_scene.call("get_pool_stats")
    if _samples_ms.is_empty():
        _failures.append("no post-warmup rendered intervals were measured")
    if _hundred_volleys <= 0 or _other_volleys != 0:
        _failures.append("fixture did not exclusively exercise genuine 100-projectile volleys")
    if _max_player_bullets > int(_main_scene.PLAYER_BULLET_POOL_SIZE):
        _failures.append("player bullet count exceeded fixed pool capacity")
    for pool_kind in final_pool_stats:
        if int(final_pool_stats[pool_kind]["exhausted"]) != 0:
            _failures.append("pool exhausted during fixture: %s" % pool_kind)
    # Read back every visible GL MultiMesh instance outside the timed sample set.
    var screenshot_info: Dictionary = await _capture_after_measurement()
    _samples_ms.sort()
    var summary := {
        "fixture": "Rank 5 forced sustained overdrive; 24 fodder + 4 heavy replenished through real activation/combat; no bosses; audio muted",
        "measurement": "Wall milliseconds between real post-draw frame signals, including process/render scheduling; not isolated GPU time or general FPS",
        "engine": Engine.get_version_info()["string"],
        "display_driver": DisplayServer.get_name(),
        "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
        "adapter": RenderingServer.get_video_adapter_name(),
        "vsync_mode": DisplayServer.window_get_vsync_mode(),
        "viewport": root.get_visible_rect().size,
        "seed": SEED,
        "rendered_frames": _frames,
        "warmup_frames": WARMUP_FRAMES,
        "measured_intervals": _samples_ms.size(),
        "simulation_seconds": float(_frames) * STEP,
        "wall_seconds": elapsed_seconds,
        "frame_ms_median": _percentile(0.5),
        "frame_ms_p95": _percentile(0.95),
        "frame_ms_p99": _percentile(0.99),
        "frame_ms_max": _samples_ms.back() if not _samples_ms.is_empty() else 0.0,
        "hundred_projectile_volleys": _hundred_volleys,
        "other_volleys": _other_volleys,
        "max_active_player_bullets": _max_player_bullets,
        "max_active_enemy_bullets": _max_enemy_bullets,
        "enemies_min": _min_enemies,
        "enemies_max": _max_enemies,
        "nodes_initial": nodes_initial,
        "nodes_peak": _max_nodes,
        "pool_stats": final_pool_stats,
        "batch_readback": _batch_readback,
        "screenshot": screenshot_info,
        "settings_writes": 0,
        "failures": _failures,
    }
    print("ARCADE_WINDOW_BENCHMARK_JSON " + JSON.stringify(summary))
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
        if option not in ["--frames", "--output"] or index + 1 >= args.size():
            _failures.append("expected --frames <121..3600> or --output <absolute PNG path>; got %s" % option)
            return false
        var value: String = args[index + 1]
        if option == "--frames":
            if not value.is_valid_int() or int(value) <= WARMUP_FRAMES or int(value) > 3600:
                _failures.append("--frames must be an integer between 121 and 3600")
                return false
            _frames = int(value)
        else:
            _output = value.replace("\\", "/")
            if not _output.is_absolute_path() or not _output.to_lower().ends_with(".png") or not DirAccess.dir_exists_absolute(_output.get_base_dir()):
                _failures.append("--output must name a PNG inside an existing absolute task-output directory")
                return false
        index += 2
    return true


func _seed_environment() -> void:
    # main randomizes during _ready; replace cosmetic initial random state explicitly.
    var fixture_rng := RandomNumberGenerator.new()
    fixture_rng.seed = SEED
    for star in _main_scene.stars:
        star.position = Vector3(fixture_rng.randf_range(-11.0, 11.0), fixture_rng.randf_range(-0.7, 3.6), fixture_rng.randf_range(-13.0, 11.0))
        star.scale = Vector3.ONE * fixture_rng.randf_range(0.45, 1.65)
        star.set_meta("speed", fixture_rng.randf_range(2.0, 8.0))
    for grid_line in _main_scene.moving_grid_lines:
        grid_line.set_meta("speed", fixture_rng.randf_range(2.7, 4.2))


func _tick_fixture(frame_index: int) -> void:
    # Deliberate test-only sustained overload. Production duration/charge are unchanged.
    _main_scene.overdrive_timer = 1.0
    _main_scene.weapon_rank = 5
    _main_scene.level = 6
    _main_scene.hp = _main_scene.PLAYER_MAX_HP
    _main_scene.player.position = Vector3(sin(float(frame_index) * STEP * 0.75) * 4.5, 0.0, 6.5)
    _main_scene.spawn_timer = 1000.0
    _main_scene.swarm_timer = 1000.0
    var previous_volleys: int = _main_scene.volley_count
    _main_scene.call("_physics_process", STEP)
    var new_volleys: int = int(_main_scene.volley_count) - previous_volleys
    if new_volleys > 0:
        if int(_main_scene.last_volley_size) == 100:
            _hundred_volleys += new_volleys
        else:
            _other_volleys += new_volleys
    _main_scene.level = 6
    _maintain_enemy_fixture()


func _maintain_enemy_fixture() -> void:
    var scout_count := 0
    var heavy_count := 0
    for enemy in get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
            continue
        if bool(enemy.get_meta("is_boss", false)):
            continue
        if str(enemy.get_meta("pool_kind")) == "heavy":
            heavy_count += 1
        else:
            scout_count += 1
    for index in range(scout_count, SCOUT_TARGET):
        var lane := _spawn_serial % 6
        var row := (_spawn_serial / 6) % 4
        var at := Vector3(lerpf(-6.5, 6.5, float(lane) / 5.0), 0.0, -11.8 + float(row) * 0.7)
        _main_scene.call("_activate_enemy", "scout", at, "fodder")
        _spawn_serial += 1
    for index in range(heavy_count, HEAVY_TARGET):
        var lane := _spawn_serial % 4
        var at := Vector3(-6.0 + float(lane) * 4.0, 0.0, -7.2)
        _main_scene.call("_activate_enemy", "heavy", at, "bomber" if lane % 2 == 0 else "standard")
        _spawn_serial += 1


func _sample_counts() -> void:
    _max_player_bullets = maxi(_max_player_bullets, get_nodes_in_group("player_bullet").size())
    _max_enemy_bullets = maxi(_max_enemy_bullets, get_nodes_in_group("enemy_bullet").size())
    _max_nodes = maxi(_max_nodes, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
    var enemy_count := get_nodes_in_group("enemy").size()
    _min_enemies = mini(_min_enemies, enemy_count)
    _max_enemies = maxi(_max_enemies, enemy_count)


func _capture_after_measurement() -> Dictionary:
    # Numeric GL checks, GPU image readback and encoding are all outside timing.
    _main_scene.overdrive_timer = 1.0
    _main_scene.call("_fire_player")
    _main_scene.call("_sync_player_bullet_batch")
    _main_scene.call("_update_ui")
    await process_frame
    await RenderingServer.frame_post_draw
    _check_batch_readback("staged_burst")
    var screenshot: Dictionary = {}
    if not _output.is_empty():
        var image := root.get_texture().get_image()
        if image == null or image.is_empty():
            _failures.append("optional screenshot readback was empty")
        else:
            var error := image.save_png(_output)
            if error != OK:
                _failures.append("optional screenshot save failed: %d" % error)
            else:
                screenshot = {"path": _output, "width": image.get_width(), "height": image.get_height(), "active_player_bullets": get_nodes_in_group("player_bullet").size(), "timed": false}

    # Non-tail removals exercise dense index compaction, not just the initial upload.
    var before_recycle := get_nodes_in_group("player_bullet")
    for index in range(0, before_recycle.size(), 3):
        _main_scene.call("_release_bullet", before_recycle[index])
    _main_scene.call("_sync_player_bullet_batch")
    await process_frame
    await RenderingServer.frame_post_draw
    _check_batch_readback("after_non_tail_recycle")
    for bullet in get_nodes_in_group("player_bullet"):
        _main_scene.call("_release_bullet", bullet)
    _main_scene.call("_sync_player_bullet_batch")
    await process_frame
    await RenderingServer.frame_post_draw
    _check_batch_readback("empty_after_recycle")
    return screenshot


func _check_batch_readback(phase: String) -> void:
    var batch_node := _main_scene.player_bullet_batch as MultiMeshInstance3D
    if batch_node == null or batch_node.multimesh == null:
        _failures.append("%s: player MultiMesh resource is missing" % phase)
        return
    var batch: MultiMesh = batch_node.multimesh
    var bullets := get_nodes_in_group("player_bullet")
    var visible := batch.visible_instance_count
    var valid_range := visible >= 0 and visible == bullets.size() and visible <= batch.instance_count
    var origin_mismatches := 0
    var color_mismatches := 0
    var invalid_actors := 0
    var checked := 0
    var identities: Dictionary = {}
    var origin_tolerance := 0.0001
    # GL backends may store per-instance color channels as normalized 8-bit values.
    var color_tolerance := 1.0 / 255.0 + 0.0001
    var max_origin_error := 0.0
    var max_color_error := 0.0
    if not valid_range:
        _failures.append("%s: visible MultiMesh count %d differs from %d active nodes (capacity %d)" % [phase, visible, bullets.size(), batch.instance_count])
    if not batch.use_colors:
        _failures.append("%s: MultiMesh instance colors are disabled" % phase)
    for index in range(mini(bullets.size(), batch.instance_count)):
        var bullet := bullets[index] as Node3D
        if bullet == null or not is_instance_valid(bullet) or bullet.is_queued_for_deletion() or not bool(bullet.get_meta("pooled_active", false)):
            invalid_actors += 1
            continue
        if identities.has(bullet.get_instance_id()):
            invalid_actors += 1
        identities[bullet.get_instance_id()] = true
        var actual_origin := batch.get_instance_transform(index).origin
        var origin_error := actual_origin.distance_to(bullet.position)
        max_origin_error = maxf(max_origin_error, origin_error)
        if not actual_origin.is_finite() or origin_error > origin_tolerance:
            origin_mismatches += 1
        var expected_color := Color("79efff") if int(bullet.get_meta("emitter", -1)) < 0 else Color("ffd879")
        if bool(bullet.get_meta("overdrive", false)):
            expected_color = expected_color.lightened(0.22)
        var actual_color := batch.get_instance_color(index)
        var color_error := maxf(maxf(absf(actual_color.r - expected_color.r), absf(actual_color.g - expected_color.g)), maxf(absf(actual_color.b - expected_color.b), absf(actual_color.a - expected_color.a)))
        max_color_error = maxf(max_color_error, color_error)
        if not is_finite(color_error) or color_error > color_tolerance:
            color_mismatches += 1
        checked += 1
    var complete := valid_range and batch.use_colors and checked == bullets.size() and origin_mismatches == 0 and color_mismatches == 0 and invalid_actors == 0
    if not complete:
        _failures.append("%s: GL batch readback mismatched (checked=%d/%d origins=%d colors=%d invalid_actors=%d)" % [phase, checked, bullets.size(), origin_mismatches, color_mismatches, invalid_actors])
    var proof := {
        "phase": phase,
        "display_driver": DisplayServer.get_name(),
        "active_nodes": bullets.size(),
        "visible_instances": visible,
        "checked_in_group_order": checked,
        "capacity": batch.instance_count,
        "hidden_tail_instances": batch.instance_count - visible if valid_range else -1,
        "origin_mismatches": origin_mismatches,
        "color_mismatches": color_mismatches,
        "invalid_actors": invalid_actors,
        "max_origin_error": max_origin_error,
        "max_color_error": max_color_error,
        "origin_tolerance": origin_tolerance,
        "color_tolerance": color_tolerance,
        "passed": complete,
    }
    _batch_readback.append(proof)
    print("ARCADE_GL_BATCH_READBACK " + JSON.stringify(proof))


func _percentile(fraction: float) -> float:
    if _samples_ms.is_empty():
        return 0.0
    var index := clampi(ceili(float(_samples_ms.size()) * fraction) - 1, 0, _samples_ms.size() - 1)
    return _samples_ms[index]


func _watchdog_timeout() -> void:
    if _finished:
        return
    _finished = true
    push_error("ARCADE_WINDOW_BENCHMARK_FAIL: 90-second watchdog expired while waiting for rendered frames")
    if is_instance_valid(_main_scene):
        _main_scene.call("prepare_for_shutdown")
    quit(1)


func _print_failures() -> void:
    for failure in _failures:
        push_error("ARCADE_WINDOW_BENCHMARK_FAIL: " + failure)

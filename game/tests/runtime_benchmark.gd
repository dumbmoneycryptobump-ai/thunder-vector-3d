extends SceneTree

# Reproducible CPU microbenchmarks, not an FPS or GPU benchmark.
# Run: godot --headless --path game --fixed-fps 60 --script res://tests/runtime_benchmark.gd
# The normal effect workload stays below capacity. Saturation is reported separately.
const BENCHMARK_SEED := 20260913
const WARMUP_BATCHES := 5
const MEASURED_BATCHES := 25
const UI_ITERATIONS := 1000
const COLLISION_ITERATIONS := 20
const EFFECT_BATCHES := 30
const EFFECTS_PER_BATCH := 10

var _main_scene: Node
var _boss: Node3D
var _ui_iteration := 0
var _failures: Array[String] = []
var _summary: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run_benchmark")


func _run_benchmark() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Runtime benchmark requires --headless; it must not change the user's display settings.")
        quit(1)
        return
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Runtime benchmark could not load res://main.tscn")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.is_paused = true
    _main_scene.rng.seed = BENCHMARK_SEED
    _main_scene.difficulty_profile = _main_scene.settings_store.get_difficulty_profile("normal")
    _main_scene.ui_pool.visible = false
    await process_frame
    _summary = {
        "schema_version": 1,
        "seed": BENCHMARK_SEED,
        "engine": Engine.get_version_info()["string"],
        "display_driver": DisplayServer.get_name(),
        "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
        "measurement": "Synchronous GDScript CPU microseconds per operation; no FPS/GPU claim",
        "baseline_counts": _counts(),
        "metrics": {},
    }

    _summary["metrics"]["hud_unchanged"] = _measure(_ui_unchanged, UI_ITERATIONS)
    _summary["metrics"]["hud_changed"] = _measure(_ui_changed, UI_ITERATIONS)
    await _reset_scenario()
    _main_scene.call("_spawn_boss")
    for enemy in get_nodes_in_group("enemy"):
        if bool(enemy.get_meta("is_boss", false)):
            _boss = enemy as Node3D
            break
    if _boss == null:
        _failures.append("boss fixture failed to spawn")
    else:
        _summary["metrics"]["hud_boss_unchanged"] = _measure(_ui_unchanged, UI_ITERATIONS)
        _summary["metrics"]["hud_boss_changed"] = _measure(_ui_boss_changed, UI_ITERATIONS)

    await _reset_scenario()
    _prepare_collision_fixture()
    var fixture_counts: Dictionary = _counts()
    if get_nodes_in_group("player_bullet").size() == 96 and get_nodes_in_group("enemy").size() == 48:
        _summary["metrics"]["collision_96_bullets_48_enemies"] = _measure(_collisions, COLLISION_ITERATIONS)
        if get_nodes_in_group("player_bullet").size() != 96 or get_nodes_in_group("enemy").size() != 48:
            _failures.append("noncolliding fixture changed active actors")
        if _main_scene.score != 0 or _main_scene.hp != 5:
            _failures.append("noncolliding fixture damaged an actor or awarded score")
    else:
        _failures.append("collision fixture did not fill 96 player bullets and 48 ordinary enemies")
    _summary["collision_fixture"] = {
        "player_bullets": get_nodes_in_group("player_bullet").size(),
        "ordinary_enemies": get_nodes_in_group("enemy").size(),
        "before": fixture_counts,
        "after": _counts(),
    }

    await _reset_scenario()
    await _measure_effects()
    await _reset_scenario()
    _summary["reset_counts"] = _counts()
    _summary["pool_stats_after_reset"] = _main_scene.call("get_pool_stats")
    if int(_summary["reset_counts"]["nodes"]) != int(_summary["baseline_counts"]["nodes"]):
        _failures.append("reset did not restore initial scene node count")
    _summary["failures"] = _failures
    print("RUNTIME_BENCHMARK_JSON " + JSON.stringify(_summary))
    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    for failure in _failures:
        push_error("RUNTIME_BENCHMARK_FAIL: " + failure)
    if _failures.is_empty():
        print("RUNTIME_BENCHMARK_PASS")
    quit(0 if _failures.is_empty() else 1)


func _measure(operation: Callable, iterations: int) -> Dictionary:
    var samples: Array[float] = []
    for batch in range(WARMUP_BATCHES + MEASURED_BATCHES):
        var start_usec: int = Time.get_ticks_usec()
        for iteration in range(iterations):
            operation.call()
        var elapsed_usec: int = Time.get_ticks_usec() - start_usec
        if batch >= WARMUP_BATCHES:
            samples.append(float(elapsed_usec) / float(iterations))
    return _distribution(samples, iterations, WARMUP_BATCHES)


func _distribution(samples: Array[float], iterations: int, warmups: int) -> Dictionary:
    samples.sort()
    var sample_count: int = samples.size()
    var median: float = samples[sample_count / 2]
    if sample_count % 2 == 0:
        median = (samples[sample_count / 2 - 1] + median) * 0.5
    return {
        "median_us": median,
        "p95_us": samples[mini(sample_count - 1, ceili(float(sample_count) * 0.95) - 1)],
        "min_us": samples[0],
        "max_us": samples[sample_count - 1],
        "measured_batches": sample_count,
        "operations_per_batch": iterations,
        "warmup_batches": warmups,
    }


func _ui_unchanged() -> void:
    _main_scene.call("_update_ui")


func _ui_changed() -> void:
    _ui_iteration += 1
    _main_scene.score = _ui_iteration
    _main_scene.hp = 1 + _ui_iteration % 5
    _main_scene.level = 1 + _ui_iteration % 12
    _main_scene.bombs = _ui_iteration % 6
    _main_scene.call("_update_ui")


func _ui_boss_changed() -> void:
    _ui_iteration += 1
    _boss.set_meta("hp", 1 + _ui_iteration % 50)
    _main_scene.call("_update_ui")


func _collisions() -> void:
    _main_scene.call("_resolve_collisions")


func _prepare_collision_fixture() -> void:
    _main_scene.level = 6
    _main_scene.rng.seed = BENCHMARK_SEED
    # Random selection can target a full pool. Stop when both existing pools fill.
    for attempt in range(1000):
        if get_nodes_in_group("enemy").size() == 48:
            break
        _main_scene.call("_spawn_enemy")
    for enemy in get_nodes_in_group("enemy"):
        (enemy as Node3D).position = Vector3(7.0, 0.0, -10.0)
    for index in range(96):
        _main_scene.call("_spawn_bullet", Vector3(-7.0, 0.0, -10.0), true, 0.0)
    _main_scene.player.position = Vector3(0.0, 0.0, 6.2)


func _measure_effects() -> void:
    var samples: Array[float] = []
    var peak_nodes: int = int(_counts()["nodes"])
    var peak_objects: int = int(_counts()["objects"])
    var peak_active: int = 0
    var before: Dictionary = _counts()
    for batch in range(WARMUP_BATCHES + EFFECT_BATCHES):
        var start_usec: int = Time.get_ticks_usec()
        for index in range(EFFECTS_PER_BATCH):
            _main_scene.call("_spawn_explosion", Vector3(float(index) - 5.0, 0.0, 0.0), Color("ff5a19"), 1.0)
        var elapsed_usec: int = Time.get_ticks_usec() - start_usec
        if batch >= WARMUP_BATCHES:
            samples.append(float(elapsed_usec) / float(EFFECTS_PER_BATCH))
        var current: Dictionary = _counts()
        peak_nodes = maxi(peak_nodes, int(current["nodes"]))
        peak_objects = maxi(peak_objects, int(current["objects"]))
        peak_active = maxi(peak_active, get_nodes_in_group("fx").size())
        # Both legacy Tween/SceneTreeTimer FX and the pooled process-driven FX run.
        await create_timer(0.5).timeout
        await process_frame
    _summary["metrics"]["effects_normal_spawn"] = _distribution(samples, EFFECTS_PER_BATCH, WARMUP_BATCHES)
    _summary["effects_normal"] = {
        "measured_spawns": EFFECT_BATCHES * EFFECTS_PER_BATCH,
        "before": before,
        "after_drain": _counts(),
        "peak_nodes": peak_nodes,
        "peak_objects": peak_objects,
        "peak_fx_group_members": peak_active,
        "runtime_stats": _effect_stats(),
    }
    var burst_start: int = Time.get_ticks_usec()
    for index in range(300):
        _main_scene.call("_spawn_explosion", Vector3.ZERO, Color("25dcff"), 0.7)
    var burst_usec: int = Time.get_ticks_usec() - burst_start
    _summary["effects_overload"] = {
        "requested_spawns": 300,
        "total_spawn_cpu_us": burst_usec,
        "counts_at_peak": _counts(),
        "fx_group_members_at_peak": get_nodes_in_group("fx").size(),
        "runtime_stats_at_peak": _effect_stats(),
        "note": "Overload may be capped by the optimized FX pool; this is not a normal-throughput comparison.",
    }
    await create_timer(0.5).timeout
    await process_frame
    _summary["effects_overload"]["counts_after_drain"] = _counts()
    _summary["effects_overload"]["runtime_stats_after_drain"] = _effect_stats()


func _effect_stats() -> Dictionary:
    for child in _main_scene.get_children():
        if child.has_method("get_stats") and child.has_method("spawn_explosion"):
            return child.call("get_stats") as Dictionary
    return {"implementation": "unpooled", "active_fx": get_nodes_in_group("fx").size()}


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = BENCHMARK_SEED
    _boss = null
    await process_frame
    await process_frame


func _counts() -> Dictionary:
    return {
        "nodes": _count_nodes(root),
        "objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
        "resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
        "orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
    }


func _count_nodes(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _count_nodes(child)
    return total

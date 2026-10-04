extends SceneTree

# End-to-end arsenal/pool/render contracts. No settings are saved by this test.
const EXPECTED_NORMAL_COUNTS: Array[int] = [10, 14, 24, 32, 40]
const EXPECTED_CAPACITIES := {"player_bullet": 1024, "enemy_bullet": 128, "scout": 64, "heavy": 16}

var _main_scene: Node
var _batch: MultiMeshInstance3D
var _batch_transform_readback := false
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Arcade combat test requires --headless")
        quit(1)
        return
    var packed: PackedScene = load("res://main.tscn") as PackedScene
    if packed == null:
        push_error("ARCADE_COMBAT_TEST_FAIL: could not load main scene")
        quit(1)
        return
    _main_scene = packed.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    _main_scene.is_paused = true
    _batch = _main_scene.player_bullet_batch as MultiMeshInstance3D
    _probe_transform_readback()
    _test_precreated_rendering()
    await _test_normal_ranks()
    await _test_hundred_shot_profiles()
    await _test_atomic_capacity()
    await _test_pause_overdrive_and_reset()
    await _test_batch_sync()
    await _test_bulk_deaths_once()
    await _test_full_collision_workload()
    await _test_resource_stability()
    await _reset_scenario()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("ARCADE_COMBAT_TEST_PASS assertions=%d normal_ranks=5 overdrive=100 wings=2_and_4 capacity=atomic batch_counts=synchronized transform_readback=%s pause=frozen reset=clean resources=stable settings_writes=0" % [_assertions, "checked" if _batch_transform_readback else "unavailable_headless"])
    else:
        for failure in _failures:
            push_error("ARCADE_COMBAT_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_precreated_rendering() -> void:
    _expect_pools_consistent()
    _expect(_batch != null and _batch.multimesh != null, "friendly bullets need one precreated MultiMesh batch")
    if _batch == null or _batch.multimesh == null:
        return
    _expect(_batch.multimesh.instance_count == 1024, "render batch must preallocate every friendly slot")
    _expect(_batch.multimesh.visible_instance_count == 0, "initial batch must show no unused bullets")
    _expect(_batch.multimesh.mesh == _main_scene.player_bullet_mesh, "batch must use the same immutable friendly bullet geometry")
    var batch_count := 0
    for child in _main_scene.get_children():
        if child is MultiMeshInstance3D and (child as MultiMeshInstance3D).multimesh == _batch.multimesh:
            batch_count += 1
    _expect(batch_count == 1, "friendly bullet geometry must have a single render batch")
    for bullet in _main_scene.idle_player_bullets:
        var meshes := 0
        for child in bullet.get_children():
            _expect(not (child is OmniLight3D), "friendly bullet slots must not carry individual OmniLights")
            if child is MeshInstance3D:
                meshes += 1
                _expect(not child.visible, "compatibility Mesh children must stay hidden to prevent duplicate drawing")
                _expect(child.mesh == _main_scene.player_bullet_mesh, "compatibility children must retain the shared mesh identity")
        _expect(meshes == 1, "each friendly slot must retain its one API-compatible hidden Mesh child")
    _expect(_main_scene.wingmen.size() == 4, "all four wingman nodes must be precreated")


func _probe_transform_readback() -> void:
    # Headless's dummy renderer may discard transform buffers while preserving
    # MultiMesh capacity/count properties. Do not misreport GPU validation there.
    var probe := MultiMesh.new()
    probe.transform_format = MultiMesh.TRANSFORM_3D
    probe.mesh = BoxMesh.new()
    probe.instance_count = 1
    var expected := Transform3D(Basis.IDENTITY, Vector3(1.0, 2.0, 3.0))
    probe.set_instance_transform(0, expected)
    _batch_transform_readback = probe.get_instance_transform(0).is_equal_approx(expected)
    if not _batch_transform_readback:
        print("ARCADE_BATCH_TRANSFORM_READBACK unavailable=headless_dummy_renderer real_GL_capture_required=true")


func _test_normal_ranks() -> void:
    for rank in range(1, 6):
        await _reset_scenario()
        _main_scene.weapon_rank = rank
        _main_scene.call("_update_wingmen", 1.0)
        _main_scene.is_paused = false
        var emitted: int = _main_scene.call("_fire_player")
        var expected: int = EXPECTED_NORMAL_COUNTS[rank - 1]
        _expect(emitted == expected and _live_count("player_bullet") == expected, "rank %d must fire its entire %d-shot normal volley" % [rank, expected])
        _expect(_main_scene.last_volley_size == expected and _main_scene.volley_count == 1, "successful normal volley must update telemetry once")
        _expect(_visible_wing_count() == (2 if rank < 3 else 4), "rank %d must expose the correct wing count" % rank)
        _verify_shot_recipe(rank, false)
        _expect(_batch.multimesh.visible_instance_count == expected, "normal firing must immediately synchronize rendered bullet count")
        _expect_pools_consistent()


func _test_hundred_shot_profiles() -> void:
    for rank in [1, 3, 5]:
        await _reset_scenario()
        _main_scene.weapon_rank = rank
        _main_scene.call("_update_wingmen", 1.0)
        _main_scene.is_paused = false
        _expect(bool(_main_scene.call("_start_overdrive")), "fully charged rank %d must start overdrive" % rank)
        var emitted: int = _main_scene.call("_fire_player")
        _expect(emitted == 100 and _live_count("player_bullet") == 100, "overdrive must emit exactly 100 bullets with rank %d" % rank)
        _expect(_visible_wing_count() == (2 if rank < 3 else 4), "100-shot mode must preserve its two/four-wing formation")
        _expect(_main_scene.last_volley_size == 100 and _main_scene.volley_count == 1, "100-shot volley telemetry must count one complete volley")
        _verify_shot_recipe(rank, true)
        _expect(_batch.multimesh.visible_instance_count == 100, "100-shot firing must synchronize its batch before drawing")


func _verify_shot_recipe(rank: int, overdrive: bool) -> void:
    var shots: Array = _main_scene.arsenal.get_shots(rank, overdrive)
    var remaining: Array[Node] = get_nodes_in_group("player_bullet")
    var matched := 0
    for shot in shots:
        var emitter: int = int(shot["emitter"])
        var origin: Vector3 = _main_scene.player.position
        if emitter >= 0:
            var wing: Node3D = _main_scene.wingmen[emitter] as Node3D
            origin = _main_scene.to_local(wing.global_position)
        var expected_position: Vector3 = origin + Vector3(shot["offset"])
        for index in range(remaining.size()):
            var bullet: Node3D = remaining[index] as Node3D
            if bullet.position.is_equal_approx(expected_position) and is_equal_approx(float(bullet.get_meta("velocity_x")), float(shot["velocity_x"])) and is_equal_approx(float(bullet.get_meta("speed")), float(shot["speed"])):
                if bullet.has_meta("emitter"):
                    _expect(int(bullet.get_meta("emitter")) == emitter, "emitter metadata must match actual wing/main origin")
                remaining.remove_at(index)
                matched += 1
                break
    _expect(matched == shots.size() and remaining.is_empty(), "actual bullet positions and speeds must match every arsenal emitter recipe (rank=%d overdrive=%s)" % [rank, overdrive])


func _test_atomic_capacity() -> void:
    await _reset_scenario()
    _main_scene.weapon_rank = 5
    _main_scene.call("_update_wingmen", 1.0)
    _main_scene.is_paused = false
    _main_scene.call("_start_overdrive")
    _main_scene.call("_fire_player")
    while _main_scene.idle_player_bullets.size() > 99:
        _main_scene.call("_spawn_bullet", Vector3(8.0, 0.0, -12.0), true, 0.0)
    _main_scene.call("_sync_player_bullet_batch")
    var before: Dictionary = _volley_state()
    var live_ids: Array[int] = _group_ids("player_bullet")
    var visible_before: int = _batch.multimesh.visible_instance_count
    for attempt in range(3):
        _expect(int(_main_scene.call("_fire_player")) == 0, "99 remaining slots must reject the entire 100-shot volley")
    _expect(_volley_state() == before and _group_ids("player_bullet") == live_ids, "rejected volleys must preserve pool counts, live identities and firing counters")
    _expect(_batch.multimesh.visible_instance_count == visible_before, "rejected volley must not alter the render batch")
    var released: Node3D = get_nodes_in_group("player_bullet")[0] as Node3D
    _main_scene.call("_release_bullet", released)
    _expect(_main_scene.idle_player_bullets.size() == 100, "capacity fixture must free exactly 100 slots")
    var count_before: int = int(_main_scene.volley_count)
    _expect(int(_main_scene.call("_fire_player")) == 100, "exactly 100 free slots must admit the whole volley")
    _expect(_live_count("player_bullet") == 1024 and _main_scene.idle_player_bullets.is_empty(), "capacity-success volley must fill the fixed pool exactly")
    _expect(_main_scene.volley_count == count_before + 1 and _main_scene.last_volley_size == 100, "capacity-success volley must update counters exactly once")
    _expect(_batch.multimesh.visible_instance_count == 1024, "fully occupied pool must render all its live bullets")
    var after: Dictionary = _main_scene.call("get_pool_stats")
    _expect(int(after["player_bullet"]["exhausted"]) == int(before["pools"]["player_bullet"]["exhausted"]), "atomic preflight must not increment underlying exhaustion")
    _expect_pools_consistent()


func _test_pause_overdrive_and_reset() -> void:
    await _reset_scenario()
    var wing_ids: Array[int] = _wing_ids()
    _expect(not bool(_main_scene.call("_start_overdrive")), "paused game must not enter overdrive")
    _expect(int(_main_scene.call("_fire_player")) == 0, "paused game must not fire")
    _main_scene.is_paused = false
    _main_scene.overdrive_charge = 99.0
    _expect(not bool(_main_scene.call("_start_overdrive")), "insufficient charge must block overdrive")
    _main_scene.overdrive_charge = 100.0
    _expect(bool(_main_scene.call("_start_overdrive")), "full charge must start overdrive")
    _expect(is_equal_approx(float(_main_scene.overdrive_timer), 6.0), "overdrive must begin with six seconds")
    _expect(not bool(_main_scene.call("_start_overdrive")), "active overdrive must not retrigger or stack")
    _main_scene.combo = 7
    _main_scene.combo_timer = 3.0
    _main_scene.call("_fire_player")
    var bullet: Node3D = get_nodes_in_group("player_bullet")[0] as Node3D
    var bullet_position: Vector3 = bullet.position
    var timer_before: float = float(_main_scene.overdrive_timer)
    var state_before: Dictionary = _volley_state()
    _main_scene.is_paused = true
    _main_scene.call("_update_arcade", 2.0)
    _main_scene.call("_physics_process", 2.0)
    _expect(is_equal_approx(float(_main_scene.overdrive_timer), timer_before) and bullet.position == bullet_position, "pause must freeze overdrive and bullet simulation")
    _expect(_main_scene.combo == 7 and is_equal_approx(float(_main_scene.combo_timer), 3.0), "pause must freeze the combo window")
    _expect(int(_main_scene.call("_fire_player")) == 0 and _volley_state() == state_before, "paused firing must preserve every counter and active bullet")
    _main_scene.is_paused = false
    _main_scene.is_game_over = true
    _main_scene.call("_update_arcade", 2.0)
    _expect(is_equal_approx(float(_main_scene.overdrive_timer), timer_before), "terminal gameplay must freeze arcade timers")
    _expect(_main_scene.combo == 7 and is_equal_approx(float(_main_scene.combo_timer), 3.0), "terminal gameplay must freeze the combo window")
    _expect(int(_main_scene.call("_fire_player")) == 0 and not bool(_main_scene.call("_start_overdrive")), "game over must block firing and overdrive")
    _main_scene.is_game_over = false
    _main_scene.call("_update_arcade", 6.1)
    _expect(is_zero_approx(float(_main_scene.overdrive_timer)), "active overdrive must expire and clamp at zero")
    _expect(_main_scene.combo == 0 and is_zero_approx(float(_main_scene.combo_timer)), "active gameplay must expire the combo window")
    _main_scene.weapon_rank = 5
    _main_scene.combo = 17
    _main_scene.combo_timer = 2.0
    await _reset_scenario()
    _expect(_main_scene.weapon_rank == 1 and is_equal_approx(float(_main_scene.overdrive_charge), 100.0) and is_zero_approx(float(_main_scene.overdrive_timer)), "restart must restore base weapon and full unused overdrive")
    _expect(_main_scene.volley_count == 0 and _main_scene.last_volley_size == 0, "restart must reset volley counters")
    _expect(_main_scene.combo == 0 and is_zero_approx(float(_main_scene.combo_timer)), "restart must clear combo and its timer")
    _expect(_wing_ids() == wing_ids and _visible_wing_count() == 2, "restart must reuse all four wing nodes and show the base pair")
    _expect(_batch.multimesh.visible_instance_count == 0 and _live_count("player_bullet") == 0, "paused restart must immediately clear rendered and physical bullets")
    _expect_pools_consistent()


func _test_batch_sync() -> void:
    await _reset_scenario()
    var bullet: Node3D = _main_scene.call("_spawn_bullet", Vector3(1.0, 0.0, 2.0), true, 2.0, 35.0) as Node3D
    _expect(bullet != null, "spawn helper must return the acquired pooled node")
    if bullet == null:
        return
    _main_scene.call("_sync_player_bullet_batch")
    _expect(_batch.multimesh.visible_instance_count == 1, "batch must expose the single spawned bullet")
    if _batch_transform_readback:
        _expect(_batch.multimesh.get_instance_transform(0).origin.is_equal_approx(bullet.position), "batch must place its visible instance at the actual bullet")
    _main_scene.call("_update_bullets", 0.1)
    _main_scene.call("_sync_player_bullet_batch")
    _expect(bullet.position.is_equal_approx(Vector3(1.2, 0.0, -1.5)), "speed override and lateral velocity must advance the bullet correctly")
    if _batch_transform_readback:
        _expect(_batch.multimesh.get_instance_transform(0).origin.is_equal_approx(bullet.position), "moving bullet must synchronize its batch transform")
    _main_scene.call("_release_bullet", bullet)
    _main_scene.call("_sync_player_bullet_batch")
    _expect(_batch.multimesh.visible_instance_count == 0, "manual release plus sync must hide the old instance")
    _main_scene.call("_release_bullet", bullet)
    _expect(_main_scene.idle_player_bullets.size() == 1024, "duplicate release must not duplicate pool entries")
    bullet = _main_scene.call("_spawn_bullet", Vector3(1.0, 0.0, -18.4), true, 0.0, 35.0) as Node3D
    _main_scene.call("_update_bullets", 0.1)
    _main_scene.call("_process", 0.0)
    _expect(_live_count("player_bullet") == 0 and _batch.multimesh.visible_instance_count == 0, "offscreen expiry must be reflected before the next draw")


func _test_bulk_deaths_once() -> void:
    await _reset_scenario()
    for index in range(64):
        var enemy: Node3D = _main_scene.call("_activate_enemy", "scout", Vector3.ZERO, "standard") as Node3D
        enemy.set_meta("hp", 1)
    for index in range(100):
        _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_resolve_collisions")
    var score_after: int = _main_scene.score
    _expect(_main_scene.kills == 64 and score_after > 0 and _live_count("enemy") == 0, "100 overlapping bullets must defeat all 64 ordinary targets once")
    _expect(_live_count("player_bullet") == 36, "ordinary deaths must consume exactly one bullet per target")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.score == score_after and _main_scene.kills == 64 and _live_count("player_bullet") == 36, "repeated collision pass must not duplicate pooled kills")
    _main_scene.call("_spawn_boss")
    var boss: Node3D = get_nodes_in_group("enemy")[0] as Node3D
    boss.position = Vector3.ZERO
    boss.set_meta("hp", 1)
    _main_scene.call("_resolve_collisions")
    score_after = _main_scene.score
    _expect(_main_scene.kills == 69 and _live_count("player_bullet") == 35 and boss.is_queued_for_deletion(), "queued boss death must consume only one of the remaining volley")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.score == score_after and _main_scene.kills == 69 and _live_count("player_bullet") == 35, "repeated boss collision pass must not duplicate rewards")
    _main_scene.call("_process", 0.0)
    _expect(_batch.multimesh.visible_instance_count == 35, "collision releases must reach the batch before drawing")


func _test_full_collision_workload() -> void:
    await _reset_scenario()
    for pool_kind in ["scout", "heavy"]:
        for index in range(int(EXPECTED_CAPACITIES[pool_kind])):
            _main_scene.call("_activate_enemy", pool_kind, Vector3(7.0, 0.0, -10.0), "standard")
    for index in range(1024):
        _main_scene.call("_spawn_bullet", Vector3(-7.0, 0.0, -10.0), true, 0.0)
    for warmup in range(5):
        _main_scene.call("_resolve_collisions")
    var samples: Array[int] = []
    for sample in range(25):
        var started: int = Time.get_ticks_usec()
        _main_scene.call("_resolve_collisions")
        samples.append(Time.get_ticks_usec() - started)
    samples.sort()
    _expect(_live_count("player_bullet") == 1024 and _live_count("enemy") == 80 and _main_scene.score == 0, "full noncolliding workload must preserve all actors and score")
    print("ARCADE_COLLISION_CPU fixture=1024_bullets_80_enemies samples=25 median_us=%d p95_us=%d note=CPU_microbenchmark_not_FPS" % [samples[12], samples[23]])
    _expect_pools_consistent()


func _test_resource_stability() -> void:
    await _reset_scenario()
    var before: Dictionary = _inventory()
    var wing_ids: Array[int] = _wing_ids()
    for cycle in range(30):
        _main_scene.weapon_rank = 1 if cycle % 2 == 0 else 5
        _main_scene.call("_update_wingmen", 0.25)
        _main_scene.is_paused = false
        _main_scene.call("_start_overdrive")
        _expect(int(_main_scene.call("_fire_player")) == 100, "resource-cycle volley must fire 100 actual bullets")
        _main_scene.call("_update_bullets", 0.1)
        _main_scene.call("_process", 0.1)
        _main_scene.call("_restart_game")
        _main_scene.is_paused = true
    await process_frame
    await process_frame
    _expect(_inventory() == before, "30 fire/move/restart cycles must preserve every scene node, mesh, material and MultiMesh identity")
    _expect(_wing_ids() == wing_ids, "wingmen must never be recreated during weapon/reset cycles")
    _expect(_batch.multimesh.visible_instance_count == 0, "resource stress must finish with no stale batch instances")
    _expect_pools_consistent()


func _inventory() -> Dictionary:
    var nodes: Dictionary = {}
    var resources: Dictionary = {}
    _collect_inventory(_main_scene, nodes, resources)
    var node_ids: Array = nodes.keys()
    var resource_ids: Array = resources.keys()
    node_ids.sort()
    resource_ids.sort()
    return {"nodes": node_ids, "resources": resource_ids}


func _collect_inventory(node: Node, nodes: Dictionary, resources: Dictionary) -> void:
    nodes[node.get_instance_id()] = true
    if node is MeshInstance3D:
        var mesh_node: MeshInstance3D = node as MeshInstance3D
        _record_resource(mesh_node.mesh, resources)
        _record_resource(mesh_node.material_override, resources)
    if node is MultiMeshInstance3D:
        var batch_node: MultiMeshInstance3D = node as MultiMeshInstance3D
        _record_resource(batch_node.multimesh, resources)
        _record_resource(batch_node.material_override, resources)
        if batch_node.multimesh != null:
            _record_resource(batch_node.multimesh.mesh, resources)
    if node is Sprite3D:
        _record_resource((node as Sprite3D).texture, resources)
    for child in node.get_children():
        _collect_inventory(child, nodes, resources)


func _record_resource(resource: Resource, resources: Dictionary) -> void:
    if resource != null:
        resources[resource.get_instance_id()] = true


func _volley_state() -> Dictionary:
    return {
        "pools": (_main_scene.call("get_pool_stats") as Dictionary).duplicate(true),
        "last": int(_main_scene.last_volley_size),
        "volleys": int(_main_scene.volley_count),
        "charge": float(_main_scene.overdrive_charge),
        "overdrive_timer": float(_main_scene.overdrive_timer),
        "shot_timer": float(_main_scene.shot_timer),
    }


func _wing_ids() -> Array[int]:
    var result: Array[int] = []
    for wing in _main_scene.wingmen:
        result.append(wing.get_instance_id())
    return result


func _visible_wing_count() -> int:
    var count := 0
    for wing in _main_scene.wingmen:
        if wing.visible:
            count += 1
    return count


func _group_ids(group_name: String) -> Array[int]:
    var result: Array[int] = []
    for node in get_nodes_in_group(group_name):
        result.append(node.get_instance_id())
    result.sort()
    return result


func _live_count(group_name: String) -> int:
    var count := 0
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            count += 1
    return count


func _expect_pools_consistent() -> void:
    var stats: Dictionary = _main_scene.call("get_pool_stats")
    for kind in EXPECTED_CAPACITIES:
        _expect(int(stats[kind]["created"]) == int(EXPECTED_CAPACITIES[kind]), "%s must retain its designed capacity" % kind)
        _expect(int(stats[kind]["active"]) + int(stats[kind]["idle"]) == int(stats[kind]["created"]), "%s must conserve every precreated slot" % kind)


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = 424242
    await process_frame
    await process_frame


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

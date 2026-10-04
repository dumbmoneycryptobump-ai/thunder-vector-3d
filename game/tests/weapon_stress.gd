extends "res://tests/arcade_stress.gd"

# Reuse the original pool partition checks; this fixture adds three real weapon
# modes, lifecycle probes and persistent resource identities. No timing/FPS test.
# Only this fixture refills E charge and grants immunity. Damage, targeting,
# cooldowns, projectile movement, ordinary waves and pickups remain real.
const WEAPON_SEED := 20261004
const MODE_FRAMES := 1200
const OVERDRIVE_CYCLE_FRAMES := 600
const LIFECYCLE_FRAMES := 6000

var _special: Node3D
var _normal_by_mode := {2: 0, 3: 0, 4: 0}
var _overdrive_by_mode := {2: 0, 3: 0, 4: 0}
var _special_peak := {"missiles": 0, "segments": 0}
var _special_inventory: Dictionary = {}
var _initial_inventory: Dictionary = {}
var _initial_nodes := 0
var _ticks := 0
var _lifecycle_probes := 0


func _run() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("WEAPON_STRESS_FAIL: requires --headless")
        quit(1)
        return
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("WEAPON_STRESS_FAIL: main scene unavailable")
        quit(1)
        return
    main = scene.instantiate()
    root.add_child(main)
    main.set_process(false)
    main.set_physics_process(false)
    main.set_process_unhandled_key_input(false)
    main.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    main.call("_apply_settings")
    main.rng.seed = WEAPON_SEED
    _special = main.get("special_weapons") as Node3D
    if _special == null:
        _expect(false, "main must expose the precreated special-weapons module")
    else:
        await process_frame
        await process_frame
        _initial_nodes = _count_nodes(main)
        _initial_inventory = _inventory(main)
        _special_inventory = _inventory(_special)
        _configure_fixture()
        _sample_state()
        for frame in range(FRAMES):
            if frame > 0 and frame % LIFECYCLE_FRAMES == 0:
                await _probe_lifecycle()
                _configure_fixture()
            if frame % MODE_FRAMES == 0:
                var cooldown_before: float = float(main.shot_timer)
                _expect(bool(main.call("_set_weapon_mode", 2 + (frame / MODE_FRAMES) % 3)), "active stress phase must select its next real weapon mode")
                _expect(float(main.shot_timer) == cooldown_before, "mode selection must preserve the shared cooldown")
            var mode: int = int(main.weapon_mode)
            if frame % OVERDRIVE_CYCLE_FRAMES == 0:
                _expect(float(main.overdrive_timer) <= 0.0, "each six-second overdrive must expire before the next ten-second cycle")
                main.overdrive_charge = 100.0 # Explicit test-only charge injection.
                _expect(bool(main.call("_start_overdrive")), "full test charge must start E in every selected weapon mode")
                activations += 1
            var seconds := float(frame) * STEP
            main.player.position = Vector3(sin(seconds * 0.8) * 8.2, 0.0, 6.0 + sin(seconds * 0.43) * 1.8)
            var before_volley: int = int(main.volley_count)
            var will_overdrive := float(main.overdrive_timer) > STEP
            # Physics owns the real cooldown, main attack dispatch and special
            # movement/damage. No helper injects target hits or resets shot_timer.
            main.call("_physics_process", STEP)
            main.call("_process", STEP)
            _ticks += 1
            var fired_count := int(main.volley_count) - before_volley
            _expect(fired_count >= 0 and fired_count <= 1, "automatic/stress fire must share one cooldown and never double-fire a physics tick")
            if fired_count == 1:
                if will_overdrive:
                    _overdrive_by_mode[mode] = int(_overdrive_by_mode[mode]) + 1
                    _expect(int(main.last_volley_size) == 100, "E must emit exactly one hundred bullets regardless of selected weapon")
                else:
                    _normal_by_mode[mode] = int(_normal_by_mode[mode]) + 1
                    _expect(int(main.last_volley_size) > 0 and int(main.last_volley_size) < 100, "ordinary selected-mode fire must be distinguishable from E100")
            _expect(not main.is_game_over and int(main.weapon_rank) == 5, "test immunity and monotonic max rank must remain intact")
            _check_special_counts()
            if frame % 60 == 59:
                await process_frame
            if (frame + 1) % SAMPLE_INTERVAL == 0:
                _sample_state()
            if failures.size() >= 30:
                break
        await _finish_checks()
    main.call("prepare_for_shutdown")
    main.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("WEAPON_STRESS_PASS assertions=%d simulated_seconds=600 capacities=64_missiles,96_segments exhaustion=0 actual_hits=all_modes lifecycle=5 reset=exact rendering_measured=false settings_writes=0" % assertions)
    else:
        for failure in failures:
            push_error("WEAPON_STRESS_FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)


func _configure_fixture() -> void:
    main.set("_pool_stress_mode", true)
    main.weapon_rank = 5
    main.level = 6
    main.is_paused = false
    main.is_game_over = false
    # Natural ordinary/fodder waves remain enabled. Prevent a long-lived Boss
    # from blocking the repeatable pooled-target workload; do not fake a kill.
    main.next_boss_kill_target = 2_000_000_000


func _sample_state() -> void:
    super._sample_state()
    _check_special_counts()
    _expect(_inventory(_special) == _special_inventory, "every stress sample must preserve all special-weapon nodes, meshes and material identities")
    _expect(_count_nodes(main) <= _initial_nodes + 128, "natural pickup/FX nodes must remain bounded above the fixed scene baseline")


func _check_special_counts() -> void:
    var stats: Dictionary = _special.call("get_stats")
    var missiles := int(stats["missiles_active"])
    var segments := int(stats["segments_active"])
    _special_peak["missiles"] = maxi(int(_special_peak["missiles"]), missiles)
    _special_peak["segments"] = maxi(int(_special_peak["segments"]), segments)
    _expect(int(stats["missile_capacity"]) == 64 and missiles >= 0 and missiles <= 64, "missile capacity and active count must remain bounded")
    _expect(int(stats["segment_capacity"]) == 96 and segments >= 0 and segments <= 96, "beam/chain capacity and active count must remain bounded")
    _expect(int(stats["overflow"]) == 0, "ordinary cadence plus E100 must not exhaust a special-weapon pool")


func _probe_lifecycle() -> void:
    var snapshot: Dictionary = _special.call("get_stats")
    var poses: Dictionary = _poses(_special)
    var pool_snapshot: Dictionary = main.call("get_pool_stats")
    var volley_before: int = int(main.volley_count)
    var elapsed_before: float = float(main.elapsed)
    main.is_paused = true
    for frame in range(30):
        main.call("_physics_process", STEP)
        main.call("_process", STEP)
    _expect(_special.call("get_stats") == snapshot and _poses(_special) == poses, "pause must freeze special lifetime, transforms, damage and counters")
    _expect(main.call("get_pool_stats") == pool_snapshot and int(main.volley_count) == volley_before, "pause must preserve ordinary active/idle partitions and firing counters")
    _expect(float(main.elapsed) == elapsed_before, "paused probes must not advance gameplay elapsed time")
    main.is_paused = false
    main.call("_game_over")
    snapshot = _special.call("get_stats")
    poses = _poses(_special)
    for frame in range(30):
        main.call("_physics_process", STEP)
        main.call("_process", STEP)
    _expect(_special.call("get_stats") == snapshot and _poses(_special) == poses, "terminal frames must not advance, fire or damage through special weapons")
    _expect(int(main.volley_count) == volley_before, "game over must not emit a late volley")
    var rng_state: int = main.rng.state
    main.call("_restart_game")
    main.is_paused = true
    await process_frame
    await process_frame
    var reset_stats: Dictionary = _special.call("get_stats")
    _expect(int(reset_stats["missiles_active"]) == 0 and int(reset_stats["segments_active"]) == 0, "restart must empty both special pools")
    _expect(int(main.weapon_mode) == 1 and int(main.weapon_rank) == 1, "restart must restore base bullets and base rank")
    _expect(_inventory(main) == _initial_inventory and _count_nodes(main) == _initial_nodes, "each restart must restore every original node and drawing-resource identity after queued pickup cleanup")
    _expect(main.rng.state == rng_state, "weapon cleanup/restart must not consume or reseed gameplay randomness")
    _lifecycle_probes += 1


func _finish_checks() -> void:
    var stats: Dictionary = _special.call("get_stats")
    _expect(_ticks == FRAMES and activations == 60 and _lifecycle_probes == 5, "stress must finish 36000 active ticks, sixty E cycles and five lifecycle probes")
    for mode in [2, 3, 4]:
        _expect(int(_normal_by_mode[mode]) > 20 and int(_overdrive_by_mode[mode]) > 20, "mode %d must exercise many ordinary and hundred-shot volleys" % mode)
        _expect(int((stats["shots_by_mode"] as Dictionary).get(mode, 0)) > 20, "mode %d must dispatch actual special-weapon attacks" % mode)
        _expect(int((stats["hits_by_mode"] as Dictionary).get(mode, 0)) > 0, "mode %d must inflict real hits on pooled combat targets" % mode)
    _expect(int(stats["missile_reused"]) > 64 and int(stats["segment_reused"]) > 96, "stress must reuse both entire precreated special pools repeatedly")
    _sample_state()
    var peak_nodes := _initial_nodes
    for sample in node_samples:
        peak_nodes = maxi(peak_nodes, sample)
    main.call("disable_pool_stress_mode")
    main.call("_restart_game")
    main.is_paused = true
    await process_frame
    await process_frame
    var reset_stats: Dictionary = _special.call("get_stats")
    _expect(_inventory(main) == _initial_inventory and _count_nodes(main) == _initial_nodes, "final restart must restore the exact persistent scene")
    _expect(int(reset_stats["missiles_active"]) == 0 and int(reset_stats["segments_active"]) == 0, "final restart must hide all special effects")
    _expect(main.player_bullet_batch.multimesh.visible_instance_count == 0, "final restart must hide the overdrive bullet batch")
    print("WEAPON_STRESS_JSON " + JSON.stringify({
        "engine": Engine.get_version_info()["string"],
        "seed": WEAPON_SEED,
        "active_ticks": _ticks,
        "simulated_seconds": float(_ticks) * STEP,
        "overdrive_activations": activations,
        "normal_volleys_by_mode": _normal_by_mode,
        "overdrive_volleys_by_mode": _overdrive_by_mode,
        "lifecycle_probes": _lifecycle_probes,
        "special_pool_peaks": _special_peak,
        "special_stats": stats,
        "nodes_initial": _initial_nodes,
        "nodes_reset": _count_nodes(main),
        "nodes_peak_sampled": peak_nodes,
        "regular_pool_stats": main.call("get_pool_stats"),
        "charge_refill": "fixture_only",
        "immunity_and_boss_gate": "fixture_only",
        "damage_and_targeting": "actual_gameplay",
        "rendering_measured": false,
        "settings_writes": 0,
        "failures": failures,
    }))


func _poses(node: Node) -> Dictionary:
    var nodes: Array[Node] = []
    _collect_nodes(node, nodes)
    var result: Dictionary = {}
    for child in nodes:
        if child is Node3D:
            result[child.get_instance_id()] = (child as Node3D).transform
    return result


func _inventory(node: Node) -> Dictionary:
    var nodes: Array[Node] = []
    _collect_nodes(node, nodes)
    var node_ids: Array[int] = []
    var resource_ids: Dictionary = {}
    for child in nodes:
        node_ids.append(child.get_instance_id())
        if child is MeshInstance3D:
            _record_resource((child as MeshInstance3D).mesh, resource_ids)
            _record_resource((child as MeshInstance3D).material_override, resource_ids)
        if child is MultiMeshInstance3D:
            _record_resource((child as MultiMeshInstance3D).multimesh, resource_ids)
            _record_resource((child as MultiMeshInstance3D).material_override, resource_ids)
        if child is Sprite3D:
            _record_resource((child as Sprite3D).texture, resource_ids)
        if child == _special:
            # Segment slots switch among prewarmed lightning/laser materials.
            # Include the entire retained catalog, not only currently bound ones.
            for property in child.get_property_list():
                if int(property["type"]) == TYPE_OBJECT:
                    var value: Variant = child.get(str(property["name"]))
                    if value is Resource:
                        _record_resource(value as Resource, resource_ids)
    node_ids.sort()
    var sorted_resources: Array = resource_ids.keys()
    sorted_resources.sort()
    return {"nodes": node_ids, "resources": sorted_resources}


func _record_resource(resource: Resource, ids: Dictionary) -> void:
    if resource == null or ids.has(resource.get_instance_id()):
        return
    ids[resource.get_instance_id()] = true
    if resource is MultiMesh:
        _record_resource((resource as MultiMesh).mesh, ids)
    if resource is Mesh:
        for surface in range((resource as Mesh).get_surface_count()):
            _record_resource((resource as Mesh).surface_get_material(surface), ids)
    if resource is ShaderMaterial:
        _record_resource((resource as ShaderMaterial).shader, ids)


func _collect_nodes(node: Node, result: Array[Node]) -> void:
    result.append(node)
    for child in node.get_children():
        _collect_nodes(child, result)

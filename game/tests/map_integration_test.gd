extends SceneTree

# Headless integration only: no settings persistence, screenshots or timing claims.
const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const SEED := 20261004
const SAFE_SIDE_X := 12.5
const SAFE_DECK_Y := -1.3

var _main_scene: Node
var _scenery: Node3D
var _route: Control
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("MAP_INTEGRATION_TEST_FAIL: requires --headless")
        quit(1)
        return
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("MAP_INTEGRATION_TEST_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    _main_scene.set_process_unhandled_key_input(false)
    _main_scene.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")
    _scenery = _main_scene.get("map_scenery") as Node3D
    _route = _main_scene.get("map_route") as Control
    if _scenery == null or _route == null:
        _expect(false, "main must expose its persistent scenery and route controls")
    else:
        await _reset_scenario()
        _test_initial_contract()
        _test_sector_switches_and_geometry()
        await _test_physics_pause_death_and_reset()
        await _test_pickup_reach_at_expanded_edge()
        await _test_real_progression()
        await _test_rng_separation()
        await _test_reuse_and_reset_stability()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("MAP_INTEGRATION_TEST_PASS assertions=%d sectors=3 switch_reset_cycles=120 geometry=actual_mesh_AABB rng=isolated settings_writes=0 GPU_visual_validation=separate" % _assertions)
    else:
        for failure in _failures:
            push_error("MAP_INTEGRATION_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_initial_contract() -> void:
    var stats: Dictionary = _scenery.call("get_stats")
    _expect(bool(stats["ready"]) and int(stats["themes"]) == 3, "all three scenery themes must be precreated")
    _expect(int(stats["sector"]) == 0 and is_zero_approx(float(stats["travel"])), "initial map must start in sector zero at zero travel")
    _expect(_main_scene.ui_route == _route.get("status_label"), "main route label must be the persistent route status control")
    _expect(_main_scene.stars.is_empty() and _main_scene.moving_grid_lines.is_empty(), "legacy environment arrays must stay compatible but empty")
    _expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "map must preserve GL Compatibility")
    _expect(float(_main_scene.PLAYER_MIN_X) <= -10.2 and float(_main_scene.PLAYER_MAX_X) >= 10.2, "expanded map must expose the wider player movement range")
    _expect(float(_main_scene.PLAYER_MIN_Z) <= 0.5 and float(_main_scene.PLAYER_MAX_Z) >= 10.2, "expanded map must expose its extended depth range")
    _expect_route(0, 0, false, false)
    _expect(String(_main_scene.ui_route.text).contains("00 / 20"), "initial route must show the real zero-of-twenty boss quota")
    var inventory: Dictionary = _inventory(_scenery)
    _scenery.call("setup")
    _scenery.call("setup")
    _expect(_inventory(_scenery) == inventory, "repeated setup must not allocate duplicate scenery")
    var nodes: Array[Node] = []
    _collect_nodes(_scenery, nodes)
    var mesh_count := 0
    for node in nodes:
        _expect(not (node is CollisionObject3D) and not (node is CollisionShape3D), "decorative scenery must not introduce gameplay collisions")
        _expect(not (node is Light3D), "decorative scenery must not create per-prop runtime lights")
        for group_name in ["enemy", "player_bullet", "enemy_bullet", "pickup", "player"]:
            _expect(not node.is_in_group(group_name), "scenery must stay out of gameplay group %s" % group_name)
        if node is MeshInstance3D:
            mesh_count += 1
            _expect((node as MeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "scenery meshes must not add shadow casters")
    _expect(mesh_count == int(stats["mesh_instances"]) and mesh_count <= 256, "reported scenery mesh count must match the bounded real scene")
    _expect(int(stats["meshes"]) <= 12 and int(stats["materials"]) <= 16, "all sector geometry must use a bounded shared resource catalog")


func _test_sector_switches_and_geometry() -> void:
    var names: Dictionary = {}
    var inventory: Dictionary = _inventory(_scenery)
    for selected in [-99, 0, 1, 2, 99]:
        var expected := clampi(selected, 0, 2)
        _main_scene.call("_set_sector", selected)
        var stats: Dictionary = _scenery.call("get_stats")
        var descriptor: Dictionary = _main_scene.encounter_director.get_sector(expected)
        _expect(_main_scene.sector_index == expected and int(stats["sector"]) == expected, "main and scenery must share the clamped selected sector")
        _expect(str(stats["name"]) == str(descriptor["name"]), "scenery names must agree with the gameplay sector catalog")
        _expect(String(_main_scene.ui_sector.text).contains(str(descriptor["name"])), "existing sector HUD must keep its actual sector name")
        _expect_route(expected, 0, false, false)
        names[str(stats["name"])] = true
        var visible_roots := 0
        for child in _scenery.get_children():
            if str(child.name).begins_with("Sector_") and (child as Node3D).visible:
                visible_roots += 1
        _expect(visible_roots == 1, "exactly one precreated sector root may be visible")
        _verify_safe_geometry()
        _scenery.call("advance", 17.25)
        _verify_safe_geometry()
        var travel: float = float((_scenery.call("get_stats") as Dictionary)["travel"])
        _main_scene.call("_set_sector", selected)
        _expect(is_equal_approx(float((_scenery.call("get_stats") as Dictionary)["travel"]), travel), "sector changes must preserve continuous scroll travel")
        _expect(_inventory(_scenery) == inventory, "sector changes must reuse every node and drawing resource")
    _expect(names.size() == 3, "three sector themes must have distinct catalog names")
    _scenery.call("reset")
    _main_scene.call("_set_sector", 0)


func _verify_safe_geometry() -> void:
    var nodes: Array[Node] = []
    _collect_nodes(_scenery, nodes)
    var visible_meshes := 0
    for node in nodes:
        if not (node is MeshInstance3D):
            continue
        var mesh_node := node as MeshInstance3D
        if not mesh_node.is_visible_in_tree():
            continue
        visible_meshes += 1
        _expect(mesh_node.mesh != null, "visible scenery must contain a real mesh")
        if mesh_node.mesh == null:
            continue
        var bounds: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
        var low_deck := bounds.end.y <= SAFE_DECK_Y + 0.0001
        var outside_corridor := bounds.position.x >= SAFE_SIDE_X - 0.0001 or bounds.end.x <= -SAFE_SIDE_X + 0.0001
        _expect(low_deck or outside_corridor, "actual transformed scenery AABB must remain below combat or outside the expanded corridor: %s %s" % [str(mesh_node.get_path()), str(bounds)])
    var stats: Dictionary = _scenery.call("get_stats")
    _expect(visible_meshes == int(stats["visible_mesh_instances"]) and visible_meshes <= 96, "visible-mesh telemetry must match the actual bounded sector")


func _test_physics_pause_death_and_reset() -> void:
    await _reset_scenario()
    var initial_pose: Dictionary = _poses(_scenery)
    _quiet_gameplay()
    _main_scene.is_paused = false
    _main_scene.call("_physics_process", 0.25)
    var travel: float = float((_scenery.call("get_stats") as Dictionary)["travel"])
    _expect(is_equal_approx(travel, 0.25 * 2.6), "active physics must advance scenery by exactly one fixed-time step")
    _expect(_poses(_scenery) != initial_pose, "active physics must move actual scrolling nodes")
    var active_pose: Dictionary = _poses(_scenery)
    _main_scene.call("_process", 0.5)
    _expect(_poses(_scenery) == active_pose, "render/cosmetic processing must not double-advance scenery")
    _main_scene.is_paused = true
    _main_scene.call("_physics_process", 1.0)
    _main_scene.call("_process", 1.0)
    _expect(_poses(_scenery) == active_pose and is_equal_approx(float((_scenery.call("get_stats") as Dictionary)["travel"]), travel), "pause must freeze floor and all scrolling nodes")
    var route_before: Dictionary = _route.call("get_snapshot")
    _main_scene.call("_update_ui")
    _expect(_route.call("get_snapshot") == route_before, "paused UI refresh must preserve route progress")
    _main_scene.is_paused = false
    _main_scene.call("_game_over")
    _main_scene.call("_physics_process", 1.0)
    _main_scene.call("_process", 1.0)
    _expect(_poses(_scenery) == active_pose and is_equal_approx(float((_scenery.call("get_stats") as Dictionary)["travel"]), travel), "game over must freeze all map layers")
    _expect_route(0, 0, false, true)
    _expect(String(_main_scene.ui_route.text).contains("任務失敗"), "terminal route status must visibly identify failure")
    _main_scene.call("_set_sector", 2)
    await _reset_scenario()
    _expect(int((_scenery.call("get_stats") as Dictionary)["sector"]) == 0 and is_zero_approx(float((_scenery.call("get_stats") as Dictionary)["travel"])), "main restart must reset map sector and all travel")
    _expect(_poses(_scenery) == initial_pose, "restart must restore exact initial scenery transforms")
    _expect_route(0, 0, false, false)


func _test_real_progression() -> void:
    await _reset_scenario()
    var fodder := _main_scene.call("_activate_enemy", "scout", Vector3(4.0, 0.0, -6.0), "fodder") as Node3D
    _main_scene.call("_damage_enemy", fodder, 99999)
    _main_scene.call("_update_ui")
    _expect_route(0, 0, false, false)
    var ordinary := _main_scene.call("_activate_enemy", "scout", Vector3(4.0, 0.0, -6.0), "standard") as Node3D
    _main_scene.call("_damage_enemy", ordinary, 99999)
    _main_scene.call("_update_ui")
    _expect_route(0, 1, false, false)
    _expect(String(_main_scene.ui_route.text).contains("01 / 20"), "ordinary kill must advance the route quota once")
    for index in range(3):
        _quiet_gameplay()
        _main_scene.kills = _main_scene.next_boss_kill_target
        _main_scene.is_paused = false
        _main_scene.call("_physics_process", 0.0)
        var boss := _main_scene.get("_active_boss") as Node3D
        _expect(boss != null and _main_scene.boss_active, "actual quota must spawn the real boss")
        if boss == null:
            continue
        _expect_route(mini(index, 2), 0, true, false)
        _expect(String(_main_scene.ui_route.text).contains("交戰中"), "boss mode must replace the ordinary quota label")
        if index == 0:
            _main_scene.is_game_over = true
            _main_scene.call("_update_ui")
            _expect_route(0, 0, true, true)
            _expect(String(_main_scene.ui_route.text).contains("任務失敗"), "failure must take priority even while a boss is alive")
            _main_scene.is_game_over = false
        _main_scene.call("_damage_enemy", boss, int(boss.get_meta("hp")))
        _main_scene.call("_update_ui")
        _expect_route(mini(index + 1, 2), 5, false, false)
        _expect(int((_scenery.call("get_stats") as Dictionary)["sector"]) == mini(index + 1, 2), "real boss defeat must change the displayed map and clamp the final sector")
        _expect(String(_main_scene.ui_route.text).contains("05 / 20"), "existing five-kill boss reward must count toward the next unchanged quota")
        var snapshot: Dictionary = _route.call("get_snapshot")
        _main_scene.call("_damage_enemy", boss, 99999)
        _main_scene.call("_update_ui")
        _expect(_route.call("get_snapshot") == snapshot, "queued boss death must not advance route twice")
        _main_scene.is_paused = true
        await process_frame
        await process_frame
    await _reset_scenario()
    _expect_route(0, 0, false, false)
    _expect(String(_main_scene.ui_route.text).contains("00 / 20"), "restart must invalidate final-sector and terminal route caches")


func _test_pickup_reach_at_expanded_edge() -> void:
    await _reset_scenario()
    _main_scene.player.position = Vector3(0.0, 0.0, float(_main_scene.PLAYER_MAX_Z))
    _main_scene.hp = int(_main_scene.PLAYER_MAX_HP) - 2
    _main_scene.call("_spawn_pickup", Vector3(0.0, 0.0, 10.99), "health")
    var pickup: Node3D = get_nodes_in_group("pickup")[0] as Node3D
    _main_scene.call("_update_pickups", 0.01)
    _expect(pickup.position.distance_squared_to(_main_scene.player.position) <= 1.05 * 1.05, "expanded-edge fixture pickup must actually be within collection distance")
    _expect(not pickup.is_queued_for_deletion(), "pickup crossing the old z=11 boundary must remain collectible in the expanded field")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.hp == _main_scene.PLAYER_MAX_HP and pickup.is_queued_for_deletion(), "expanded-edge collision must collect the reachable health pickup before expiry")
    await process_frame
    await process_frame
    _main_scene.call("_spawn_pickup", Vector3(0.0, 0.0, float(_main_scene.ENEMY_EXIT_Z) + 0.1), "health")
    pickup = get_nodes_in_group("pickup")[0] as Node3D
    _main_scene.call("_update_pickups", 0.0)
    _expect(pickup.is_queued_for_deletion(), "pickups must still expire after leaving the expanded reachable area")
    await _reset_scenario()


func _test_rng_separation() -> void:
    await _reset_scenario()
    _main_scene.rng.seed = SEED
    var rng_state: int = _main_scene.rng.state
    for index in range(30):
        _main_scene.call("_set_sector", index % 3)
        _scenery.call("advance", 31.75)
        _scenery.call("reset")
        _scenery.call("setup")
        _main_scene.call("_update_ui")
    _expect(_main_scene.rng.state == rng_state, "scenery construction/switching/scroll/reset and route refresh must not consume gameplay RNG")
    _main_scene.call("_restart_game")
    _expect(_main_scene.rng.state == rng_state, "map integration must not add a gameplay RNG draw during restart")
    _quiet_gameplay()
    _main_scene.call("_physics_process", 60.0)
    _expect(_main_scene.rng.state == rng_state, "active map wrapping must not consume gameplay RNG during physics")
    _main_scene.is_paused = true
    var before: Dictionary = _poses(_scenery)
    var travel: float = float((_scenery.call("get_stats") as Dictionary)["travel"])
    for invalid_delta in [-1.0, 0.0, INF, NAN]:
        _scenery.call("advance", invalid_delta)
    _expect(_poses(_scenery) == before and is_equal_approx(float((_scenery.call("get_stats") as Dictionary)["travel"]), travel), "invalid map deltas must not alter transforms or contaminate state")
    var expected_rng := RandomNumberGenerator.new()
    expected_rng.seed = SEED
    for sample in range(20):
        _expect(_main_scene.rng.randi() == expected_rng.randi(), "map-only work must preserve the subsequent gameplay random sequence")


func _test_reuse_and_reset_stability() -> void:
    await _reset_scenario()
    var inventory: Dictionary = _inventory(_main_scene)
    var initial_pose: Dictionary = _poses(_scenery)
    var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
    for cycle in range(120):
        _main_scene.call("_set_sector", cycle % 3)
        _scenery.call("advance", 120.125 + float(cycle))
        var stats: Dictionary = _scenery.call("get_stats")
        _expect(float(stats["travel"]) >= 0.0 and float(stats["travel"]) < 56.0, "long scrolling runs must retain a bounded phase")
        _main_scene.call("_restart_game")
        _main_scene.is_paused = true
        _expect(_poses(_scenery) == initial_pose, "every restart must restore the same zero-phase transforms")
    await process_frame
    await process_frame
    _expect(_inventory(_main_scene) == inventory, "120 sector-switch/advance/restart cycles must preserve all scene node and drawing-resource identities")
    _expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == node_count, "repeated map resets must not leak nodes into the scene tree")
    _expect_route(0, 0, false, false)


func _expect_route(sector: int, completed: int, boss: bool, dead: bool) -> void:
    var snapshot: Dictionary = _route.call("get_snapshot")
    _expect(snapshot == {"sector": sector, "completed": completed, "boss": boss, "dead": dead}, "route snapshot must reflect real progression: actual=%s expected=%s" % [str(snapshot), str([sector, completed, boss, dead])])


func _quiet_gameplay() -> void:
    _main_scene.spawn_timer = 99999.0
    _main_scene.swarm_timer = 99999.0
    _main_scene.shot_timer = 99999.0
    _main_scene.overdrive_timer = 0.0


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = SEED
    await process_frame
    await process_frame


func _poses(node: Node) -> Dictionary:
    var result: Dictionary = {}
    var nodes: Array[Node] = []
    _collect_nodes(node, nodes)
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
    if resource is BaseMaterial3D:
        _record_resource((resource as BaseMaterial3D).albedo_texture, ids)


func _collect_nodes(node: Node, result: Array[Node]) -> void:
    result.append(node)
    for child in node.get_children():
        _collect_nodes(child, result)


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

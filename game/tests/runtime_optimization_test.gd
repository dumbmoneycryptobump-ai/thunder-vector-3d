extends SceneTree

# Regression coverage for shared resources, collision ordering and pooled FX.
var _main_scene: Node
var _transient: Node
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Runtime optimization test requires --headless")
        quit(1)
        return
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Runtime optimization test could not load the main scene")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    _main_scene.is_paused = true
    _transient = _main_scene.get("transient_effects") as Node

    _test_shared_bullet_meshes()
    await _test_collision_order()
    await _test_ordinary_death_once()
    await _test_queued_boss_death_once()
    await _test_collision_boundaries()
    await _test_float32_collision_boundary()
    if _transient == null or not _main_scene.has_method("_process"):
        _expect(false, "main must own transient_effects and advance it through _process")
    else:
        await _test_effect_lifecycle()
        await _test_resource_stability()

    await _reset_scenario()
    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("RUNTIME_OPTIMIZATION_TEST_PASS assertions=%d meshes=shared collision_order=preserved deaths=once boundary=inclusive fx_pause=advances resources=stable" % _assertions)
    else:
        for failure in _failures:
            push_error("RUNTIME_OPTIMIZATION_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_shared_bullet_meshes() -> void:
    var friendly: Array = _main_scene.idle_player_bullets
    var hostile: Array = _main_scene.idle_enemy_bullets
    _expect(friendly.size() == 1024 and hostile.size() == 128, "all bullet slots must be prewarmed")
    if friendly.is_empty() or hostile.is_empty():
        return
    var friendly_mesh: BoxMesh = _bullet_mesh(friendly[0])
    var hostile_mesh: BoxMesh = _bullet_mesh(hostile[0])
    _expect(friendly_mesh != null and hostile_mesh != null, "bullet visuals must have BoxMesh geometry")
    if friendly_mesh == null or hostile_mesh == null:
        return
    _expect(friendly_mesh != hostile_mesh, "friendly and hostile bullets need distinct shared mesh resources")
    _expect(friendly_mesh.size.is_equal_approx(Vector3(0.13, 0.13, 0.92)), "friendly bullet dimensions must remain unchanged")
    _expect(hostile_mesh.size.is_equal_approx(Vector3(0.18, 0.13, 0.62)), "hostile bullet dimensions must remain unchanged")
    for bullet in friendly:
        _expect(_bullet_mesh(bullet) == friendly_mesh, "every friendly bullet must reuse one shared mesh")
    for bullet in hostile:
        _expect(_bullet_mesh(bullet) == hostile_mesh, "every hostile bullet must reuse one shared mesh")


func _bullet_mesh(bullet: Node) -> BoxMesh:
    for child in bullet.get_children():
        if child is MeshInstance3D:
            return (child as MeshInstance3D).mesh as BoxMesh
    return null


func _test_collision_order() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_enemy")
    _main_scene.call("_spawn_enemy")
    var enemies: Array[Node] = get_nodes_in_group("enemy")
    _expect(enemies.size() == 2, "ordering fixture needs two enemies")
    if enemies.size() != 2:
        return
    # Capture the actual pre-optimization group order, not pool allocation order.
    var first: Node3D = enemies[0] as Node3D
    var second: Node3D = enemies[1] as Node3D
    first.position = Vector3.ZERO
    second.position = Vector3.ZERO
    first.set_meta("hp", 2)
    first.set_meta("score", 100)
    second.set_meta("hp", 3)
    second.set_meta("score", 260)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_resolve_collisions")
    _expect(not first.is_in_group("enemy"), "simultaneous bullets must hit the first enumerated enemy first")
    _expect(second.is_in_group("enemy") and int(second.get_meta("hp")) == 3, "later overlapping enemy must remain unharmed until the first dies")
    _expect(_main_scene.score == 100 and _main_scene.kills == 1, "ordering fixture should award exactly one first-enemy kill")
    _expect(_live_count("player_bullet") == 0, "both hits on the first enemy must consume their bullets")

    # Both enemies dying in one pass exercises mutation of active containers.
    await _reset_scenario()
    _main_scene.call("_spawn_enemy")
    _main_scene.call("_spawn_enemy")
    for enemy in get_nodes_in_group("enemy"):
        (enemy as Node3D).position = Vector3.ZERO
        enemy.set_meta("hp", 1)
        enemy.set_meta("score", 100)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.score == 200 and _main_scene.kills == 2, "container mutation must not skip the second enemy or award a duplicate kill")
    _expect(_live_count("enemy") == 0 and _live_count("player_bullet") == 0, "two simultaneous kills must release both enemies and bullets")


func _test_ordinary_death_once() -> void:
    await _reset_scenario()
    var enemy: Node3D = _spawn_scout(Vector3.ZERO, 1)
    if enemy == null:
        return
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_resolve_collisions")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.score == 100 and _main_scene.kills == 1, "multiple bullets and repeated collision passes must score a pooled enemy only once")
    _expect(_live_count("player_bullet") == 1, "the extra bullet must survive after the only enemy dies")
    var before: Dictionary = _main_scene.call("get_pool_stats")
    _main_scene.call("_release_enemy", enemy)
    var after: Dictionary = _main_scene.call("get_pool_stats")
    _expect(int(before["scout"]["idle"]) == int(after["scout"]["idle"]), "duplicate enemy release must not duplicate an idle slot")
    _expect(int(after["scout"]["active"]) + int(after["scout"]["idle"]) == int(after["scout"]["created"]), "ordinary death must conserve pool capacity")


func _test_queued_boss_death_once() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_boss")
    var bosses: Array[Node] = get_nodes_in_group("enemy")
    _expect(bosses.size() == 1, "boss fixture must create one boss")
    if bosses.size() != 1:
        return
    var boss: Node3D = bosses[0] as Node3D
    boss.position = Vector3.ZERO
    boss.set_meta("hp", 1)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_resolve_collisions")
    _expect(boss.is_queued_for_deletion(), "defeated boss should be queued for deferred deletion")
    _main_scene.call("_resolve_collisions")
    _main_scene.call("_damage_enemy", boss, 1)
    _expect(_main_scene.score == 2500 and _main_scene.kills == 5, "queued boss must award score and progression once")
    _expect(_main_scene.bombs == 3, "queued boss must award its bomb only once")
    _expect(_live_count("pickup") == 2, "queued boss must drop exactly two pickups")
    _expect(_live_count("player_bullet") == 1, "queued boss must not consume a second bullet")
    _expect(not _main_scene.boss_active, "queued boss must clear the active encounter flag")


func _test_collision_boundaries() -> void:
    # 0.5 + 0.5 is exactly representable: a stable test of <= versus <.
    for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
        await _reset_scenario()
        var enemy: Node3D = _spawn_scout(Vector3.ZERO, 2)
        if enemy == null:
            return
        enemy.set_meta("radius", 0.5)
        _main_scene.call("_spawn_bullet", axis, true, 0.0)
        var bullets: Array[Node] = get_nodes_in_group("player_bullet")
        bullets[0].set_meta("radius", 0.5)
        _main_scene.call("_resolve_collisions")
        _expect(int(enemy.get_meta("hp")) == 1 and _live_count("player_bullet") == 0, "exact distance boundary must hit on axis %s" % axis)

        _main_scene.call("_spawn_bullet", axis * 1.0001, true, 0.0)
        bullets = get_nodes_in_group("player_bullet")
        bullets[0].set_meta("radius", 0.5)
        _main_scene.call("_resolve_collisions")
        _expect(int(enemy.get_meta("hp")) == 1 and _live_count("player_bullet") == 1, "near miss beyond the boundary must not hit on axis %s" % axis)


func _test_float32_collision_boundary() -> void:
    await _reset_scenario()
    var enemy: Node3D = _spawn_scout(Vector3(-0.2499999850988388, 0.0, 0.0), 2)
    if enemy == null:
        return
    enemy.set_meta("radius", 0.78)
    _main_scene.call("_spawn_bullet", Vector3(-1.5099999904632568, 0.0, 0.0), true, 0.0)
    var bullets: Array[Node] = get_nodes_in_group("player_bullet")
    var bullet: Node3D = bullets[0] as Node3D
    bullet.set_meta("radius", 0.48)
    var radius_sum: float = float(bullet.get_meta("radius")) + float(enemy.get_meta("radius"))
    # Vector3 uses single precision here. A scalar-double axis rejection would
    # disagree with the original authoritative distance_squared_to predicate.
    var baseline_hits: bool = bullet.position.distance_squared_to(enemy.position) <= radius_sum * radius_sum
    _expect(baseline_hits, "float32 precision fixture must hit under the original distance predicate")
    _expect(absf(bullet.position.x - enemy.position.x) > radius_sum, "precision fixture must expose the scalar-axis rejection discrepancy")
    _main_scene.call("_resolve_collisions")
    _expect(int(enemy.get_meta("hp")) == 1 and _live_count("player_bullet") == 0, "optimized collision must preserve the original float32 boundary hit")


func _test_effect_lifecycle() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_explosion", Vector3.ZERO, Color("ff5a19"), 1.0)
    _expect(_fx_active() == 1, "main explosion must activate a pooled effect")
    var elapsed_before: float = _main_scene.elapsed
    _main_scene.is_paused = true
    _main_scene.call("_process", 0.20)
    _expect(_fx_active() == 1, "paused effect must remain alive before lifetime expires")
    _main_scene.call("_process", 0.23)
    _expect(_fx_active() == 0, "effects must expire while the game is paused")
    _expect(is_equal_approx(float(_main_scene.elapsed), elapsed_before), "presentation advance must not advance gameplay time while paused")

    _main_scene.is_game_over = true
    _main_scene.call("_spawn_explosion", Vector3.ZERO, Color("25dcff"), 0.7)
    _main_scene.call("_process", 0.43)
    _expect(_fx_active() == 0, "effects must expire during game over")

    _main_scene.call("_spawn_explosion", Vector3.ZERO, Color.RED, 2.3)
    _main_scene.call("_process", 0.20)
    _transient.call("clear")
    _expect(_fx_active() == 0 and _live_count("fx") == 0, "clear must immediately release effects and group membership")
    _main_scene.call("_spawn_explosion", Vector3(1.0, 0.0, 0.0), Color.BLUE, 0.7)
    _main_scene.call("_process", 0.23)
    _expect(_fx_active() == 1, "reused effect must have a fresh lifetime independent of its predecessor")
    _main_scene.call("_process", 0.20)
    _expect(_fx_active() == 0, "reused effect must expire at its own lifetime")

    _main_scene.call("_spawn_explosion", Vector3.ZERO, Color.WHITE, 1.0)
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _expect(_fx_active() == 0 and _live_count("fx") == 0, "restart must clear pooled effects synchronously")
    var stats: Dictionary = _transient.call("get_stats")
    _expect(int(stats["audio"]["active"]) == 0, "restart must leave no active transient audio")


func _test_resource_stability() -> void:
    await _reset_scenario()
    # Warm rendering-independent resources before taking the identity baseline.
    _main_scene.call("_spawn_explosion", Vector3.ZERO, Color.WHITE, 1.0)
    _main_scene.call("_process", 0.43)
    _transient.call("clear")
    var before: Dictionary = _resource_inventory()
    var before_stats: Dictionary = _transient.call("get_stats")
    var capacity: int = int(before_stats["fx"]["capacity"])
    for cycle in range(50):
        for index in range(capacity + 3):
            _main_scene.call("_spawn_explosion", Vector3(float(index), 0.0, 0.0), Color("ff5a19"), 1.0)
        _expect(_fx_active() == capacity, "effect overload must stay at fixed capacity")
        _main_scene.call("_process", 0.10)
        _transient.call("clear")
        _main_scene.call("_restart_game")
        _main_scene.is_paused = true
    await process_frame
    await process_frame
    var after: Dictionary = _resource_inventory()
    var after_stats: Dictionary = _transient.call("get_stats")
    _expect(before == after, "50 overload/clear/restart cycles must preserve node, mesh and material identities")
    _expect(int(after_stats["fx"]["created"]) == int(before_stats["fx"]["created"]), "effect pool must never allocate extra slots")
    _expect(int(after_stats["audio"]["created"]) == int(before_stats["audio"]["created"]), "audio pool must never allocate extra slots")
    _expect(_fx_active() == 0 and _live_count("fx") == 0, "stress restart must return every effect to idle")
    print("RUNTIME_OPTIMIZATION_RESOURCES nodes=%d meshes=%d materials=%d cycles=50 fx_capacity=%d" % [
        (after["nodes"] as Array).size(), (after["meshes"] as Array).size(),
        (after["materials"] as Array).size(), capacity,
    ])


func _resource_inventory() -> Dictionary:
    var nodes: Dictionary = {}
    var meshes: Dictionary = {}
    var materials: Dictionary = {}
    _collect_resources(_main_scene, nodes, meshes, materials)
    var node_ids: Array = nodes.keys()
    var mesh_ids: Array = meshes.keys()
    var material_ids: Array = materials.keys()
    node_ids.sort()
    mesh_ids.sort()
    material_ids.sort()
    return {"nodes": node_ids, "meshes": mesh_ids, "materials": material_ids}


func _collect_resources(node: Node, nodes: Dictionary, meshes: Dictionary, materials: Dictionary) -> void:
    nodes[node.get_instance_id()] = true
    if node is MeshInstance3D:
        var instance: MeshInstance3D = node as MeshInstance3D
        if instance.mesh != null:
            meshes[instance.mesh.get_instance_id()] = true
        if instance.material_override != null:
            materials[instance.material_override.get_instance_id()] = true
    for child in node.get_children():
        _collect_resources(child, nodes, meshes, materials)


func _spawn_scout(position_value: Vector3, health: int) -> Node3D:
    _main_scene.level = 1
    _main_scene.call("_spawn_enemy")
    var enemies: Array[Node] = get_nodes_in_group("enemy")
    _expect(enemies.size() == 1, "scout fixture needs exactly one active enemy")
    if enemies.size() != 1:
        return null
    var enemy: Node3D = enemies[0] as Node3D
    enemy.position = position_value
    enemy.set_meta("hp", health)
    enemy.set_meta("score", 100)
    return enemy


func _fx_active() -> int:
    var stats: Dictionary = _transient.call("get_stats")
    return int(stats["fx"]["active"])


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = 424242
    await process_frame
    await process_frame


func _live_count(group_name: String) -> int:
    var count := 0
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            count += 1
    return count


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

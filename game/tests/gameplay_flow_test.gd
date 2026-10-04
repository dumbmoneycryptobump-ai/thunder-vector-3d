extends SceneTree

const EXPECTED_CAPACITIES := {
    "player_bullet": 1024,
    "enemy_bullet": 128,
    "scout": 64,
    "heavy": 16,
}

var failures: Array[String] = []
var _main_scene: Node


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Gameplay flow test could not load res://main.tscn")
        quit(1)
        return

    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.is_paused = true
    _main_scene.rng.seed = 424242

    await _test_player_bullet_kill()
    await _test_pickup_collection()
    await _test_bomb_clear()
    await _test_boss_defeat()
    await _test_lethal_damage_precedes_pickup()
    await _test_game_over_restart()

    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame

    if failures.is_empty():
        print("GAMEPLAY_FLOW_TEST_PASS combat=ready pickups=3 lethal_order=ready bomb=ready boss=ready boss_bullets=pooled restart=ready pools=restored")
        quit(0)
    else:
        for failure in failures:
            push_error("GAMEPLAY_FLOW_TEST_FAIL: %s" % failure)
        quit(1)


func _test_player_bullet_kill() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_enemy")
    var enemy := _first_live_node("enemy") as Node3D
    _expect(enemy != null, "enemy spawn should activate one pooled enemy")
    if enemy == null:
        return

    enemy.position = Vector3.ZERO
    enemy.set_meta("hp", 1)
    enemy.set_meta("score", 100)
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _expect(_live_count("player_bullet") == 1, "player bullet spawn should activate one pooled bullet")
    _main_scene.call("_resolve_collisions")

    _expect(_main_scene.score == 100, "player bullet kill should award enemy score")
    _expect(_main_scene.kills == 1, "player bullet kill should increment kill count")
    _expect(_live_count("enemy") == 0, "destroyed ordinary enemy should return to its pool")
    _expect(_live_count("player_bullet") == 0, "colliding player bullet should return to its pool")
    _expect_pool_active_zero(["player_bullet", "scout", "heavy"])


func _test_pickup_collection() -> void:
    await _reset_scenario()
    _main_scene.hp = 2
    _main_scene.bombs = 1

    _main_scene.call("_spawn_pickup", _main_scene.player.position, "health")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.hp == 4, "health pickup should restore two HP without exceeding the cap")
    _expect(_main_scene.score == 150, "health pickup should award 150 points")

    _main_scene.call("_spawn_pickup", _main_scene.player.position, "bomb")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.bombs == 2, "bomb pickup should add one bomb")
    _expect(_main_scene.score == 350, "bomb pickup should award 200 points")

    _main_scene.call("_spawn_pickup", _main_scene.player.position, "power")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.level == 2, "power pickup should raise the weapon level")
    _expect(_main_scene.score == 800, "power pickup should award 450 points")

    await process_frame
    await process_frame
    _expect(_live_count("pickup") == 0, "collected pickups should leave the scene tree")


func _test_bomb_clear() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_enemy")
    _main_scene.call("_spawn_enemy")
    for index in range(3):
        _main_scene.call("_spawn_bullet", Vector3(float(index), 0.0, -2.0), false, 0.0)

    _expect(_live_count("enemy") == 2, "bomb scenario should begin with two ordinary enemies")
    _expect(_live_count("enemy_bullet") == 3, "bomb scenario should begin with three enemy bullets")
    _main_scene.call("_use_bomb")

    _expect(_main_scene.bombs == 1, "using a bomb should consume exactly one bomb")
    _expect(_main_scene.score == 200, "bomb should award score for both destroyed scouts")
    _expect(_main_scene.kills == 2, "bomb should count both destroyed ordinary enemies")
    _expect(_live_count("enemy") == 0, "bomb should clear ordinary enemies")
    _expect(_live_count("enemy_bullet") == 0, "bomb should clear enemy bullets")
    _expect_pool_active_zero(["enemy_bullet", "scout", "heavy"])


func _test_boss_defeat() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_boss")
    var boss := _first_live_node("enemy") as Node3D
    _expect(boss != null and bool(boss.get_meta("is_boss", false)), "boss spawn should create an active boss")
    _expect(_main_scene.boss_active, "boss_active should be true during the encounter")
    if boss == null:
        return

    _main_scene.call("_damage_enemy", boss, int(boss.get_meta("hp", 1)))
    _expect(not _main_scene.boss_active, "defeating the boss should clear boss_active")
    _expect(_main_scene.score == 2500, "defeating the boss should award 2500 points")
    _expect(_main_scene.kills == 5, "defeating the boss should add five progression kills")
    _expect(_main_scene.bombs == 3, "defeating the boss should award one bomb")
    _expect(_live_count("pickup") == 2, "defeating the boss should drop power and health pickups")

    await process_frame
    await process_frame
    _expect(_live_count("enemy") == 0, "defeated boss should leave the scene tree")


func _test_lethal_damage_precedes_pickup() -> void:
    await _reset_scenario()
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.call("_spawn_bullet", _main_scene.player.position, false, 0.0)
    _main_scene.call("_spawn_pickup", _main_scene.player.position, "health")
    _main_scene.call("_resolve_collisions")

    _expect(_main_scene.is_game_over, "lethal enemy bullet should enter game over")
    _expect(_main_scene.hp == 0, "same-frame health pickup must not revive a game-over player")
    _expect(_main_scene.score == 0, "same-frame pickup must not award score after lethal damage")
    _expect(_live_count("pickup") == 1, "uncollected same-frame pickup should remain until restart cleanup")
    _expect(_live_count("enemy_bullet") == 0, "lethal enemy bullet should return to its pool")


func _test_game_over_restart() -> void:
    await _reset_scenario()
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.call("_damage_player", 1)
    _expect(_main_scene.is_game_over, "lethal player damage should enter game over")
    _expect(_main_scene.hp == 0, "lethal player damage should clamp HP to zero")
    _expect(not _main_scene.player.visible, "game over should hide the player")
    _expect(_main_scene.ui_center.visible, "game over should show restart instructions")

    _main_scene.call("_spawn_enemy")
    _main_scene.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    _main_scene.call("_spawn_pickup", Vector3.ZERO, "bomb")
    _main_scene.call("_spawn_boss")
    var boss := _first_boss()
    _expect(boss != null, "restart scenario should create a boss")
    if boss != null:
        _main_scene.call("_fire_enemy", boss)
    _expect(_live_count("enemy_bullet") == 5, "boss should fire five bullets from the shared enemy-bullet pool")
    _main_scene.call("_restart_game")

    _expect(not _main_scene.is_game_over, "restart should leave game over")
    _expect(not _main_scene.is_paused, "restart should resume gameplay")
    _expect(_main_scene.hp == 5, "restart should restore full HP")
    _expect(_main_scene.bombs == 2, "restart should restore the starting bomb count")
    _expect(_main_scene.score == 0 and _main_scene.kills == 0 and _main_scene.level == 1, "restart should reset progression")
    _expect(not _main_scene.boss_active, "restart should clear boss state")
    _expect(_main_scene.player.visible, "restart should show the player")
    _expect(_main_scene.player.position.is_equal_approx(Vector3(0.0, 0.0, 6.2)), "restart should restore the player start position")

    _main_scene.is_paused = true
    await process_frame
    await process_frame
    _expect(_live_count("enemy") == 0, "restart should remove every enemy and boss")
    _expect(_live_count("player_bullet") == 0 and _live_count("enemy_bullet") == 0, "restart should return all bullets to pools")
    _expect(_live_count("pickup") == 0, "restart should remove every pickup")
    _expect_pool_active_zero(EXPECTED_CAPACITIES.keys())
    var stats: Dictionary = _main_scene.call("get_pool_stats")
    for pool_kind in EXPECTED_CAPACITIES:
        _expect(int(stats[pool_kind]["created"]) == int(EXPECTED_CAPACITIES[pool_kind]), "%s pool capacity should remain fixed after restart" % pool_kind)
        _expect(int(stats[pool_kind]["idle"]) == int(stats[pool_kind]["created"]), "%s restart should return every object to the idle pool" % pool_kind)


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = 424242
    await process_frame
    await process_frame


func _first_live_node(group_name: String) -> Node:
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            return node
    return null


func _first_boss() -> Node3D:
    for node in get_nodes_in_group("enemy"):
        if is_instance_valid(node) and not node.is_queued_for_deletion() and bool(node.get_meta("is_boss", false)):
            return node as Node3D
    return null


func _live_count(group_name: String) -> int:
    var count := 0
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            count += 1
    return count


func _expect_pool_active_zero(pool_kinds: Array) -> void:
    var stats: Dictionary = _main_scene.call("get_pool_stats")
    for pool_kind in pool_kinds:
        _expect(int(stats[str(pool_kind)]["active"]) == 0, "%s pool should have zero active objects" % pool_kind)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)

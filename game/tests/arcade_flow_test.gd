extends SceneTree

const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const CAPACITIES := {"player_bullet": 1024, "enemy_bullet": 128, "scout": 64, "heavy": 16}

var main: Node
var failures: Array[String] = []
var assertions := 0
var initial_nodes := 0
var initial_wings: Array[int] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Arcade flow test requires --headless; no personal settings are written")
        quit(1)
        return
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("ARCADE_FLOW_TEST_FAIL: main scene unavailable")
        quit(1)
        return
    main = scene.instantiate()
    root.add_child(main)
    main.set_process(false)
    main.set_physics_process(false)
    main.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    main.call("_apply_settings")
    initial_nodes = _count_nodes(main)
    for wing in main.wingmen:
        initial_wings.append(wing.get_instance_id())
    _expect(initial_wings.size() == 4, "four wingmen must be precreated")
    await _test_rank_and_rewards()
    await _test_combo_and_charge_guards()
    await _test_overdrive_input_and_expiry()
    await _test_fodder_squads()
    await _test_fodder_normal_headroom()
    await _test_boss_hits_and_once_only_death()
    await _test_same_frame_and_restart()
    await _reset()
    _expect(_count_nodes(main) == initial_nodes, "final reset must restore exact baseline nodes")
    _expect_pools()
    main.call("prepare_for_shutdown")
    main.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("ARCADE_FLOW_TEST_PASS assertions=%d rank=monotonic charge=guarded combo=guarded input=non_echo expiry=exact fodder=atomic boss=once restart=stable settings_writes=0" % assertions)
    else:
        for failure in failures:
            push_error("ARCADE_FLOW_TEST_FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)


func _test_rank_and_rewards() -> void:
    await _reset()
    main.overdrive_charge = 0.0
    for index in range(40):
        var enemy := _spawn("fodder")
        _expect(enemy != null, "fodder reward fixture must acquire a scout")
        if enemy == null:
            break
        _expect(int(enemy.get_meta("hp")) == 1 and int(enemy.get_meta("score")) == 40, "fodder must retain one HP and forty points")
        main.call("_damage_enemy", enemy, 1)
        _expect(main.arcade_kills == index + 1, "every actual combat death must increment arcade kills once")
        _expect(main.weapon_rank == mini(5, 1 + (index + 1) / 8), "weapon rank must rise each eight kills and cap at five")
        _expect(main.kills == 0 and main.next_boss_kill_target == 20, "fodder must not advance boss quota")
        _expect(is_equal_approx(float(main.overdrive_charge), minf(100.0, float(index + 1) * 2.5)), "inactive fodder kills must award exactly 2.5 charge, capped at one hundred")
    _expect(main.score == 1600, "forty fodder deaths must award exactly 1600 before pickup collection")
    await _reset()
    for index in range(4):
        _collect("power")
    _expect(main.weapon_rank == 5, "four power pickups must upgrade to rank five")
    main.score = 0
    main.level = 1
    var ordinary := _spawn("standard")
    main.call("_damage_enemy", ordinary, 999)
    _expect(main.weapon_rank == 5 and main.level == 1, "score-derived level changes must never downgrade a pickup-earned rank")
    _collect("power")
    _expect(main.weapon_rank == 5, "extra power pickups must preserve rank cap")


func _test_combo_and_charge_guards() -> void:
    await _reset()
    main.overdrive_charge = 0.0
    var ordinary := _spawn("standard")
    main.call("_damage_enemy", ordinary, 999)
    var snapshot := _reward_state()
    main.call("_damage_enemy", ordinary, 999)
    _expect(_reward_state() == snapshot, "released enemy repeated damage must not duplicate any arcade reward")
    _expect(main.combo == 1 and main.best_combo == 1 and main.combo_timer == 3.0 and main.overdrive_charge == 5.0, "ordinary defeat must grant one combo and five charge")
    main.is_paused = true
    main.call("_update_arcade", 99.0)
    _expect(main.combo == 1 and main.combo_timer == 3.0, "pause must freeze combo expiry")
    main.is_paused = false
    main.call("_update_arcade", -5.0)
    _expect(main.combo_timer == 3.0, "negative delta must not extend combo duration")
    main.call("_update_arcade", 2.9)
    _expect(main.combo == 1, "combo must survive until its entire window elapses")
    main.call("_update_arcade", 0.11)
    _expect(main.combo == 0 and main.best_combo == 1, "expiry must clear current chain but preserve best")
    main.call("_damage_enemy", _spawn("standard"), 999)
    main.shield_timer = 12.0
    main.call("_damage_player", 1)
    _expect(main.combo == 1 and main.hp == 5, "shield absorption must not break an undamaged combo")
    main.invulnerability_timer = 0.0
    main.call("_damage_player", 1)
    _expect(main.combo == 0 and main.combo_timer == 0.0 and main.best_combo == 1, "real health damage must break only the current combo")
    main.overdrive_charge = 95.0
    _collect("health")
    _expect(main.overdrive_charge == 100.0, "pickup charge must saturate at one hundred")
    _expect(bool(main.call("_start_overdrive")), "full charge must activate overdrive")
    main.call("_damage_enemy", _spawn("fodder"), 1)
    main.call("_damage_enemy", _spawn("standard"), 999)
    _collect("health")
    _expect(main.overdrive_charge == 0.0, "active overdrive must suppress both kill and pickup recharging")
    main.call("_update_arcade", 6.0)
    _collect("health")
    _expect(main.overdrive_charge == 10.0, "pickup after expiry must resume charging")


func _test_overdrive_input_and_expiry() -> void:
    await _reset()
    main.is_paused = true
    _key(KEY_E)
    _expect(main.overdrive_timer == 0.0 and main.overdrive_charge == 100.0, "paused E must not consume charge")
    main.is_paused = false
    _key(KEY_E, true)
    _expect(main.overdrive_timer == 0.0, "held-key echo must not activate overdrive")
    _key(KEY_E, false, false)
    _expect(main.overdrive_timer == 0.0, "key release must not activate overdrive")
    main.is_game_over = true
    _key(KEY_E)
    _expect(main.overdrive_timer == 0.0 and main.overdrive_charge == 100.0, "game-over E must not consume charge")
    main.is_game_over = false
    main.overdrive_charge = 99.0
    _key(KEY_E)
    _expect(main.overdrive_timer == 0.0 and main.overdrive_charge == 99.0, "undercharged E must be inert")
    main.overdrive_charge = 100.0
    _key(KEY_E)
    _expect(main.overdrive_timer == 6.0 and main.overdrive_charge == 0.0 and main.shot_timer == 0.0, "E must start one six-second window and prepare immediate fire")
    main.call("_update_arcade", 1.0)
    _key(KEY_E)
    _key(KEY_E, true)
    _expect(main.overdrive_timer == 5.0 and main.overdrive_charge == 0.0, "pressing or holding E during overdrive must not refresh its duration")
    main.is_paused = true
    main.call("_physics_process", 20.0)
    _expect(main.overdrive_timer == 5.0 and main.volley_count == 0, "paused physics must neither expire overdrive nor fire")
    main.is_paused = false
    main.weapon_rank = 5
    main.set("_pool_stress_mode", true)
    main.call("_physics_process", 1.0 / 60.0)
    _expect(main.volley_count == 1 and main.last_volley_size == 100, "normal overdrive auto-fire and stress auto-fire must produce only one hundred-shot volley per tick")
    _expect(get_nodes_in_group("player_bullet").size() == 100, "first hundred-shot burst must activate exactly one hundred nodes")
    main.set("_pool_stress_mode", false)
    _clear_bullets()
    main.overdrive_timer = 0.001
    main.shot_timer = 0.0
    var volleys: int = main.volley_count
    main.call("_physics_process", 1.0 / 60.0)
    _expect(main.overdrive_timer == 0.0 and main.volley_count == volleys, "expiry before input update must not emit one extra automatic volley on the last frame")
    main.overdrive_charge = 100.0
    _key(KEY_E, true)
    _expect(main.overdrive_timer == 0.0, "held echo after expiry must not start the next charged window")


func _test_fodder_squads() -> void:
    for rank_value in range(1, 6):
        await _reset()
        main.weapon_rank = rank_value
        var expected := 6 + mini(rank_value, 3) * 2
        _expect(int(main.call("_spawn_fodder_squad")) == expected, "fodder count must scale eight, ten, then twelve")
        for enemy in get_nodes_in_group("enemy"):
            enemy.position.z = 0.0
            enemy.set_meta("shoot_timer", -5.0)
        main.call("_update_enemies", 0.1)
        _expect(get_nodes_in_group("enemy_bullet").is_empty(), "fodder update must never fire hostile bullets")
        for enemy in get_nodes_in_group("enemy"):
            enemy.position.z = main.ENEMY_EXIT_Z + 0.1
        main.call("_update_enemies", 0.0)
        _expect(main.hp == 5 and get_nodes_in_group("enemy").is_empty(), "escaped fodder must recycle with no HP penalty")
        _expect(main.kills == 0 and main.arcade_kills == 0 and main.combo == 0, "escape must grant no combat rewards or boss credit")
    await _reset()
    main.weapon_rank = 5
    var occupied: Array[Node3D] = []
    for index in range(17):
        occupied.append(_spawn("standard"))
    var before: Dictionary = main.call("get_pool_stats")
    _expect(int(main.call("_spawn_fodder_squad")) == 0 and get_nodes_in_group("enemy").size() == 17, "scout-family budget must reject a partial twelve-member squad at seventeen active")
    main.call("_release_enemy", occupied[0])
    _expect(int(main.call("_spawn_fodder_squad")) == 12 and get_nodes_in_group("enemy").size() == 28, "one released slot must allow the complete squad at exact family budget")
    _expect(main.call("get_pool_stats")["scout"]["exhausted"] == before["scout"]["exhausted"], "budget preflight must not increment pool exhaustion")
    await _reset()
    for index in range(64):
        _spawn("standard")
    _expect(int(main.call("_spawn_fodder_squad")) == 0 and main.idle_scouts.is_empty(), "full fixed pool must reject the whole squad without allocating")
    _expect(main.call("get_pool_stats")["scout"]["exhausted"] == 0, "atomic full-pool guard must not call an exhausted acquisition")
    await _reset()
    for gate in ["is_paused", "is_game_over", "boss_active"]:
        main.set(gate, true)
        _expect(int(main.call("_spawn_fodder_squad")) == 0 and get_nodes_in_group("enemy").is_empty(), "%s must gate fodder spawns" % gate)
        main.set(gate, false)


func _test_fodder_normal_headroom() -> void:
    await _reset()
    main.weapon_rank = 3
    _expect(int(main.call("_spawn_fodder_squad")) == 12, "starvation fixture must begin with twelve live fodder")
    _expect(int(main.call("_spawn_encounter")) == 1, "twelve fodder must not starve the first ordinary scout formation")
    _expect(_scout_count(true) == 12 and _scout_count(false) == 1, "ordinary formation must share the scout pool with, not count against, fodder's separate budget")
    _expect(int(main.call("_spawn_fodder_squad")) == 0, "second twelve-fodder squad must defer above fodder-only sixteen even when shared pool has room")
    var released := 0
    for enemy in get_nodes_in_group("enemy"):
        if str(enemy.get_meta("archetype", "")) == "fodder" and released < 8:
            main.call("_release_enemy", enemy)
            released += 1
    _expect(released == 8 and _scout_count(true) == 4, "refill fixture must leave four surviving fodder")
    _expect(int(main.call("_spawn_fodder_squad")) == 12 and _scout_count(true) == 16, "fodder refill must allow exactly sixteen without removing ordinary enemies")
    # Director waves after the opening scout are pair, triangle, escort, scout,
    # pair: their scout counts are 2,3,2,1,2, leaving eleven ordinary scouts.
    for expected_spawn in [2, 3, 3, 1, 2]:
        _expect(int(main.call("_spawn_encounter")) == expected_spawn, "ordinary formations must keep making progress while sixteen fodder remain active")
    _expect(_scout_count(true) == 16 and _scout_count(false) == 11, "ordinary progression fixture must reach sixteen fodder plus eleven ordinary scouts")
    var stats_before: Dictionary = main.call("get_pool_stats")
    _expect(int(main.call("_spawn_encounter")) == 0, "three-scout formation must defer atomically with only one ordinary slot remaining")
    var held_plan: Dictionary = main.pending_encounter.duplicate(true)
    _expect(int(main.call("_spawn_encounter")) == 0 and main.pending_encounter == held_plan, "ordinary backpressure must preserve the same pending formation")
    _expect(_scout_count(false) == 11 and _scout_count(true) == 16, "blocked ordinary plan must not consume any partial shared-pool slots")
    released = 0
    for enemy in get_nodes_in_group("enemy"):
        if str(enemy.get_meta("pool_kind", "")) == "scout" and str(enemy.get_meta("archetype", "")) != "fodder" and released < 2:
            main.call("_release_enemy", enemy)
            released += 1
    _expect(released == 2, "ordinary retry fixture must release exactly two scouts")
    _expect(int(main.call("_spawn_encounter")) == 3, "held triangle must resume completely after three ordinary slots become free")
    _expect(_scout_count(true) == 16 and _scout_count(false) == 12, "shared family must support sixteen fodder plus all twelve ordinary scouts")
    var stats_after: Dictionary = main.call("get_pool_stats")
    _expect(int(stats_after["scout"]["active"]) == 28, "mixed scout-family active count must reach but never exceed twenty-eight")
    _expect(int(main.call("_spawn_fodder_squad")) == 0 and int(main.call("_spawn_encounter")) == 0, "both spawners must defer atomically at their joint shared-family boundary")
    _expect(stats_after["scout"]["exhausted"] == stats_before["scout"]["exhausted"], "headroom preflight and retries must never exhaust the actual fixed pool")
    _expect_pools()

    # Exercise each guard independently rather than relying only on their sum.
    await _reset()
    main.weapon_rank = 3
    for index in range(12):
        _spawn("standard")
    _expect(int(main.call("_spawn_encounter")) == 0 and _scout_count(false) == 12, "ordinary-only twelve cap must hold while the shared twenty-eight budget still has space")
    _expect(int(main.call("_spawn_fodder_squad")) == 12, "a full ordinary formation budget must still permit its separate fodder allocation")
    await _reset()
    main.weapon_rank = 3
    # Low-level activation intentionally builds an over-fodder fixture to test
    # the shared guard independently: next pair fits ordinary <=12 but not total.
    for index in range(17):
        _spawn("fodder")
    for index in range(10):
        _spawn("standard")
    main.encounter_director.next_wave(0)
    _expect(int(main.call("_spawn_encounter")) == 0, "ordinary pair must not exceed shared twenty-eight even when ordinary-only count would remain twelve")
    _expect(_scout_count(true) == 17 and _scout_count(false) == 10, "shared-limit rejection must leave the complete fixture untouched")
    _expect_pools()


func _scout_count(fodder: bool) -> int:
    var count := 0
    for enemy in get_nodes_in_group("enemy"):
        if str(enemy.get_meta("pool_kind", "")) == "scout" and (str(enemy.get_meta("archetype", "")) == "fodder") == fodder:
            count += 1
    return count


func _test_boss_hits_and_once_only_death() -> void:
    await _reset()
    main.weapon_rank = 3
    main.bosses_defeated = 2
    main.overdrive_charge = 0.0
    main.call("_spawn_boss")
    var boss: Node3D = main.get("_active_boss")
    var expected_hp := 320 + 2 * 140 + 3 * 35
    _expect(int(boss.get_meta("hp")) == expected_hp and int(boss.get_meta("max_hp")) == expected_hp, "boss HP must scale by defeated bosses and independent weapon rank")
    boss.position = Vector3(0.0, 0.0, -5.0)
    main.call("_spawn_bullet", boss.position, true)
    main.call("_resolve_collisions")
    _expect(int(boss.get_meta("hp")) == expected_hp - 1 and main.arcade_kills == 0 and main.combo == 0, "ordinary one-damage bullet must hurt but not reward a surviving boss")
    _expect(float(boss.get_meta("hit_flash")) > 0.0, "surviving boss damage must trigger hit feedback")
    boss.set_meta("hp", 1)
    main.call("_spawn_bullet", boss.position, true)
    main.call("_spawn_bullet", boss.position, true)
    main.call("_resolve_collisions")
    _expect(boss.is_queued_for_deletion() and main.bosses_defeated == 3 and main.arcade_kills == 1 and main.kills == 5, "same-frame lethal bullets must complete boss death exactly once")
    _expect(main.score == 2500 and main.combo == 1 and main.overdrive_charge == 5.0, "one boss death must award one reward bundle")
    _expect(get_nodes_in_group("player_bullet").size() == 1, "second bullet must remain live after queued boss is excluded")
    var reward := _reward_state()
    main.call("_damage_enemy", boss, 999)
    _expect(_reward_state() == reward, "queued boss damage must not duplicate arcade state")


func _test_same_frame_and_restart() -> void:
    await _reset()
    main.hp = 1
    main.overdrive_charge = 0.0
    main.call("_spawn_pickup", main.player.position, "power")
    main.call("_spawn_bullet", main.player.position, false)
    main.call("_resolve_collisions")
    _expect(main.is_game_over and main.hp == 0 and main.weapon_rank == 1 and main.overdrive_charge == 0.0, "same-frame lethal hit must prevent rank and charge pickup rewards")
    _expect(int(main.call("_fire_player")) == 0 and not bool(main.call("_start_overdrive")), "dead-player fire and activation must be inert")
    for wing in main.wingmen:
        _expect(not wing.visible, "game over must hide all wingmen")
    await _reset()
    _expect(main.weapon_rank == 1 and main.arcade_kills == 0 and main.combo == 0 and main.best_combo == 0, "restart must clear arcade progression")
    _expect(main.overdrive_charge == 100.0 and main.overdrive_timer == 0.0 and main.volley_count == 0, "restart must restore charged but inactive overdrive")
    _expect(main.player_bullet_batch.multimesh.visible_instance_count == 0, "restart must clear stale multimesh bullets")
    for index in range(4):
        _expect(main.wingmen[index].get_instance_id() == initial_wings[index], "restart must retain all four wingman identities")
        _expect(main.wingmen[index].visible == (index < 2), "rank-one restart must display exactly two wingmen")
    _expect(_count_nodes(main) == initial_nodes, "queued cleanup after restart must recover the exact node count")


func _reset() -> void:
    main.call("_restart_game")
    main.is_paused = true
    main.set("_pool_stress_mode", false)
    main.rng.seed = 20261004
    main.spawn_timer = 999.0
    main.swarm_timer = 999.0
    await process_frame
    await process_frame
    main.is_paused = false


func _spawn(archetype: String) -> Node3D:
    return main.call("_activate_enemy", "scout", Vector3(5.0, 0.0, -7.0), archetype) as Node3D


func _collect(kind: String) -> void:
    main.call("_spawn_pickup", main.player.position, kind)
    for pickup in get_nodes_in_group("pickup"):
        if not pickup.is_queued_for_deletion() and pickup.position == main.player.position:
            main.call("_collect_pickup", pickup)
            pickup.queue_free()


func _key(code: int, echo_event: bool = false, pressed_event: bool = true) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed_event
    event.echo = echo_event
    main.call("_unhandled_key_input", event)


func _clear_bullets() -> void:
    for group_name in ["player_bullet", "enemy_bullet"]:
        for bullet in get_nodes_in_group(group_name):
            main.call("_release_bullet", bullet)


func _reward_state() -> Array:
    return [main.score, main.arcade_kills, main.weapon_rank, main.kills, main.combo, main.best_combo, main.combo_timer, main.overdrive_charge, main.bosses_defeated]


func _expect_pools() -> void:
    var stats: Dictionary = main.call("get_pool_stats")
    for kind in CAPACITIES:
        _expect(int(stats[kind]["created"]) == CAPACITIES[kind], "%s capacity must remain fixed" % kind)
        _expect(int(stats[kind]["active"]) + int(stats[kind]["idle"]) == CAPACITIES[kind], "%s partition must account for every pooled node" % kind)


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

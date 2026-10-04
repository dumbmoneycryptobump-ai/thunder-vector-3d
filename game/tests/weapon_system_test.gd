extends SceneTree

# Headless damage/state integration tests. No personal settings writes or GL claims.
var _main_scene: Node
var _weapons: Node
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("WEAPON_SYSTEM_TEST_FAIL: use --headless")
        quit(1)
        return
    var packed := load("res://main.tscn") as PackedScene
    if packed == null:
        push_error("WEAPON_SYSTEM_TEST_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_process(false)
    _main_scene.set_physics_process(false)
    _main_scene.set_process_unhandled_key_input(false)
    _weapons = _main_scene.get("special_weapons")
    if _weapons == null:
        push_error("WEAPON_SYSTEM_TEST_FAIL: special_weapons integration missing")
        quit(1)
        return
    await _test_selection_and_profiles()
    await _test_missile_homing_and_reuse()
    await _test_missile_sweep_and_splash()
    await _test_missile_same_frame_death_and_stale_record()
    await _test_lightning_chain()
    await _test_degenerate_lightning_segments()
    await _test_laser_capsules()
    await _test_deaths_once()
    await _test_atomic_capacity()
    await _test_wingguns_and_overdrive()
    await _test_pause_death_restart()
    await _test_resources()
    await _fresh()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("WEAPON_SYSTEM_TEST_PASS assertions=%d modes=4 missile=swept_homing_and_splash chain=unique5 laser=full_capsule_unique pools=atomic pause_death_reset=guarded resources=stable settings_writes=0" % _assertions)
    else:
        for failure in _failures:
            push_error("WEAPON_SYSTEM_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_selection_and_profiles() -> void:
    await _fresh()
    _expect(int(_main_scene.weapon_mode) == 1, "fresh run defaults to original bullets")
    for mode in [2, 3, 4]:
        var profile: Dictionary = _weapons.call("get_profile", mode, 3)
        _expect(not str(profile.get("name", "")).is_empty() and not str(profile.get("description", "")).is_empty(), "mode %d has a readable profile" % mode)
        _expect(float(profile.get("interval", 0.0)) > 0.0 and int(profile.get("projectiles", -1)) >= 0, "mode %d has valid cadence/projectile metadata" % mode)
        _main_scene.shot_timer = 0.77
        _key(KEY_1 + mode - 1)
        _expect(int(_main_scene.weapon_mode) == mode, "number key selects mode %d" % mode)
        _expect(is_equal_approx(float(_main_scene.shot_timer), 0.77), "switching modes does not bypass cooldown")
    _key(KEY_1, true, true)
    _expect(int(_main_scene.weapon_mode) == 4, "held-key echoes do not select modes")
    _key(KEY_1, false)
    _expect(int(_main_scene.weapon_mode) == 4, "key release does not select modes")
    _main_scene.is_paused = true
    _key(KEY_1)
    _expect(int(_main_scene.weapon_mode) == 4, "pause rejects weapon switching")
    _main_scene.is_paused = false
    _main_scene.is_game_over = true
    _key(KEY_1)
    _expect(int(_main_scene.weapon_mode) == 4, "game over rejects weapon switching")
    _main_scene.is_game_over = false
    _expect(not bool(_main_scene.call("_set_weapon_mode", 0)) and not bool(_main_scene.call("_set_weapon_mode", 5)), "out-of-range mode selections are rejected")
    for mode in [0, 1, 5]:
        _expect(not bool(_weapons.call("fire", mode, Vector3.ZERO, 3)), "special module rejects unsupported mode %d" % mode)
    _expect(not bool(_weapons.call("fire", 2, Vector3(NAN, 0.0, 0.0), 3)), "non-finite origins do not allocate missiles")
    _expect_active(0, 0, "invalid requests leave both pools idle")


func _test_missile_homing_and_reuse() -> void:
    await _fresh()
    var target := _enemy(Vector3(8.0, 0.0, -10.0))
    _expect(bool(_weapons.call("fire", 2, Vector3.ZERO, 3)), "missile burst is accepted")
    var before: Array = _weapons.call("get_active_missiles")
    _expect(before.size() == 4, "one missile burst activates exactly four slots")
    var first: Dictionary = before[0]
    var old_position: Vector3 = first["position"]
    var aim := (target.position - old_position).normalized()
    var old_velocity: Vector3 = first["velocity"]
    _weapons.call("advance", 0.05)
    var after: Array = _weapons.call("get_active_missiles")
    var new_velocity: Vector3 = after[0]["velocity"]
    _expect(new_velocity.normalized().dot(aim) > old_velocity.normalized().dot(aim), "homing rotates velocity toward its live target")
    _expect(is_equal_approx(new_velocity.length(), 22.0), "homing preserves missile speed")
    _expect(is_equal_approx(float(after[0]["age"]), 0.05), "manual advance uses simulation delta")
    _expect(int(after[0]["target_id"]) == target.get_instance_id(), "missile stores the selected target identity")
    var old_id := target.get_instance_id()
    var old_activation := int(target.get_meta("activation_id"))
    _main_scene.call("_release_enemy", target)
    var recycled := _enemy(Vector3(8.0, 0.0, 5.0))
    _expect(recycled.get_instance_id() == old_id, "reuse fixture reacquires the same pooled enemy node")
    _expect(int(recycled.get_meta("activation_id")) > old_activation, "each enemy activation receives a newer identity token")
    _weapons.call("advance", 0.05)
    for missile in _weapons.call("get_active_missiles"):
        _expect(int(missile["target_id"]) == 0, "recycled target behind missile must invalidate its old homing lock")
    _expect(_hp(recycled) == 100, "stale homing lock cannot damage a new behind-player enemy")


func _test_missile_sweep_and_splash() -> void:
    await _fresh()
    # Lock the near target first, then make it LAST in scene group iteration.
    # A large advance crosses both spheres, so insertion-order collision is wrong.
    var primary := _enemy(Vector3.ZERO, 1.0)
    _expect(bool(_weapons.call("fire", 2, Vector3(0.0, 0.0, 4.0), 3)), "sweep fixture launches four rank3 missiles")
    var far_target := _enemy(Vector3(0.0, 0.0, -6.0), 3.0)
    var splash := _enemy(Vector3(1.2, 0.0, 1.2), 0.05)
    primary.remove_from_group("enemy")
    primary.add_to_group("enemy")
    _weapons.call("advance", 0.8)
    _expect(_hp(primary) == 80, "all four swept missiles hit earliest target for5 each, without adding own splash2")
    _expect(_hp(far_target) == 100, "a farther sphere earlier in group order must not steal swept hits")
    _expect(_hp(splash) == 92, "four impacts deal2 splash each to the nearby non-primary target")
    _expect_active(0, 0, "impact recycles every missile")
    var stats: Dictionary = _weapons.call("get_stats")
    _expect(int(stats["last_hits"]) == 8, "primary and splash recipients are each damaged once per impact")
    _weapons.call("advance", 0.8)
    _expect(_hp(primary) == 80 and _hp(splash) == 92, "released missile slots cannot deal repeated damage")


func _test_lightning_chain() -> void:
    await _fresh()
    var targets: Array[Node3D] = []
    for index in range(6):
        targets.append(_enemy(Vector3(0.0, 0.0, 3.0 - float(index) * 4.0)))
    var behind := _enemy(Vector3(0.0, 0.0, 9.0))
    var disconnected := _enemy(Vector3(8.0, 0.0, 2.0))
    _expect(bool(_weapons.call("fire", 3, Vector3(0.0, 0.0, 8.0), 3)), "five-target lightning chain is accepted")
    for index in range(targets.size()):
        _expect(_hp(targets[index]) == (97 if index < 5 else 100), "lightning damages unique target%d exactly once, capped at5" % index)
    _expect(_hp(behind) == 100 and _hp(disconnected) == 100, "chain excludes behind-origin and disconnected targets")
    _expect_active(0, 20, "five chain links use the reserved20 visual segments")
    _weapons.call("advance", 0.05)
    _expect(_hp(targets[0]) == 97, "visible lightning does not repeatedly apply damage each frame")
    await _fresh()
    var first := _enemy(Vector3(0.0, 0.0, -24.0))
    var chained := _enemy(Vector3(0.0, 0.0, -25.9))
    var out_of_range := _enemy(Vector3(0.0, 0.0, -26.1))
    _expect(bool(_weapons.call("fire", 3, Vector3.ZERO, 1)), "exact24 first-target boundary can fire")
    _expect(_hp(first) == 97 and _hp(chained) == 97 and _hp(out_of_range) == 100, "chain first24/global26 boundaries are respected")
    await _fresh()
    var too_far := _enemy(Vector3(0.0, 0.0, -24.1))
    _expect(bool(_weapons.call("fire", 3, Vector3.ZERO, 1)), "empty-range lightning still shows a bounded discharge")
    _expect(_hp(too_far) == 100, "first target beyond24 is not struck")
    _expect_active(0, 4, "empty lightning allocates just one four-segment discharge")


func _test_missile_same_frame_death_and_stale_record() -> void:
    await _fresh()
    var primary := _enemy(Vector3.ZERO, 1.0, 5)
    var primary_id := primary.get_instance_id()
    var primary_token := int(primary.get_meta("activation_id"))
    var primary_score := int(primary.get_meta("score"))
    var stale_record: Dictionary = _weapons.call("_target_record", primary, 5)
    var before: Dictionary = _weapons.call("get_stats")
    _expect(bool(_weapons.call("fire", 2, Vector3(0.0, 0.0, 4.0), 3)), "four missiles launch toward one lowHP primary")
    var missiles: Array = _weapons.call("get_active_missiles")
    _expect(missiles.size() == 4, "same-frame death fixture begins with four simultaneous missiles")
    for missile in missiles:
        _expect(int(missile["target_id"]) == primary_id and int(missile["target_activation_id"]) == primary_token, "every initial missile lock names the same primary activation")
    # Add this only after launch so all four initial locks target the primary.
    # First impact kills primary and splashes2; the remaining three retarget for5 each.
    var secondary := _enemy(Vector3(1.2, 0.0, 1.2), 0.05)
    _weapons.call("advance", 0.8)
    _expect(not primary.is_in_group("enemy") and _hp(primary) == 0, "first missile kills primary once; remaining cached targets cannot damage it again")
    _expect(int(_main_scene.kills) == 1 and int(_main_scene.arcade_kills) == 1, "simultaneous missiles credit exactly one primary kill")
    _expect(int(_main_scene.score) == primary_score and int(_main_scene.combo) == 1, "primary death score and combo reward are awarded once")
    _expect(_hp(secondary) == 83, "secondary receives exactly2 splash plus three valid5-damage retargeted impacts")
    _expect_active(0, 0, "all four same-frame missile impacts recycle cleanly")
    var after: Dictionary = _weapons.call("get_stats")
    _expect(int(after["last_hits"]) == 5 and int(after["total_hits"]) - int(before["total_hits"]) == 5, "only five valid primary/splash/retarget damage records are counted")
    _expect(int(after["hits_by_mode"][2]) - int(before["hits_by_mode"][2]) == 5, "missile hit telemetry excludes stale dead-primary records")
    var recycled := _enemy(Vector3(0.0, 0.0, -5.0))
    _expect(recycled.get_instance_id() == primary_id and int(recycled.get_meta("activation_id")) > primary_token, "the dead primary node is reused with a fresh activation token")
    _weapons.call("_damage_record", stale_record, 2)
    var rejected: Dictionary = _weapons.call("get_stats")
    _expect(_hp(recycled) == 100 and int(rejected["total_hits"]) == int(after["total_hits"]), "stored stale damage record cannot hurt or count a hit on the recycled actor")
    var fresh_record: Dictionary = _weapons.call("_target_record", recycled, 2)
    _weapons.call("_damage_record", fresh_record, 2)
    _expect(_hp(recycled) == 98, "positive control: a current activation record still applies damage")
    _weapons.call("advance", 0.8)
    _expect(_hp(secondary) == 83 and _hp(recycled) == 98 and int(_main_scene.kills) == 1, "released missile slots cannot damage surviving or recycled targets on later advances")


func _test_laser_capsules() -> void:
    await _fresh()
    var near_target := _enemy(Vector3(-0.65, 0.0, -3.0), 0.1)
    var far_target := _enemy(Vector3(0.65, 0.0, -24.0), 0.1)
    var overlap := _enemy(Vector3(0.0, 0.0, -8.0), 0.78)
    var endpoint := _enemy(Vector3(0.65, 0.0, -27.1), 0.1)
    var behind := _enemy(Vector3(-0.65, 0.0, 1.0), 0.1)
    var outside_width := _enemy(Vector3(2.0, 0.0, -6.0), 0.1)
    var beyond := _enemy(Vector3(-0.65, 0.0, -28.0), 0.1)
    var before_muzzle := _enemy(Vector3(-0.65, 0.0, -0.1), 0.1)
    _expect(bool(_weapons.call("fire", 4, Vector3.ZERO, 3)), "dual piercing laser is accepted")
    for enemy in [near_target, far_target, overlap, endpoint]:
        _expect(_hp(enemy) == 98, "laser pierces full26-length muzzle capsule, damaging each enemy once")
    for enemy in [behind, outside_width, beyond, before_muzzle]:
        _expect(_hp(enemy) == 100, "laser rejects targets outside its finite beam capsules")
    _expect_active(0, 4, "two beams each use one outer segment and one core")
    _weapons.call("advance", 0.05)
    _expect(_hp(overlap) == 98, "dual overlap and visible beam lifetime cannot double-hit one target")


func _test_degenerate_lightning_segments() -> void:
    await _fresh()
    # First target coincides with the muzzle; later links are zero-length/vertical.
    var first := _enemy(Vector3(0.0, 0.0, -1.0))
    var coincident := _enemy(Vector3(0.0, 0.0, -1.0))
    var vertical := _enemy(Vector3(0.0, 0.2, -1.0))
    _expect(bool(_weapons.call("fire", 3, Vector3.ZERO, 3)), "coincident/vertical lightning targets can fire safely")
    for target in [first, coincident, vertical]:
        _expect(_hp(target) == 97, "coincident enemy identities remain distinct chain targets")
    var visible_segments := 0
    for child in _weapons.get_children():
        if child is MeshInstance3D and child.visible:
            visible_segments += 1
            _expect(child.transform.is_finite(), "zero-length/vertical lightning segments retain finite transforms")
    _expect(visible_segments == 12, "three degenerate-safe lightning links retain12 reusable segments")


func _test_deaths_once() -> void:
    await _fresh()
    var target := _enemy(Vector3(0.0, 0.0, -4.0), 0.9, 2)
    var target_score := int(target.get_meta("score"))
    _weapons.call("fire", 4, Vector3.ZERO, 3)
    _expect(not target.is_in_group("enemy") and int(_main_scene.kills) == 1, "a target hit by both beam capsules dies once")
    _expect(int(_main_scene.score) == target_score and int(_main_scene.combo) == 1, "dual-beam kill rewards are credited once")
    await _fresh()
    _main_scene.call("_spawn_boss")
    var boss := _main_scene.get("_active_boss") as Node3D
    boss.position = Vector3(0.0, 0.0, -5.0)
    boss.set_meta("hp", 2)
    var boss_score := int(boss.get_meta("score"))
    _weapons.call("fire", 4, Vector3.ZERO, 3)
    _expect(int(_main_scene.bosses_defeated) == 1 and int(_main_scene.kills) == 5, "piercing Boss overlap triggers exactly one defeat")
    _expect(int(_main_scene.score) == boss_score and int(_main_scene.combo) == 1, "Boss reward is not duplicated across beams")


func _test_atomic_capacity() -> void:
    await _fresh()
    for burst in range(16):
        _expect(bool(_weapons.call("fire", 2, Vector3.ZERO, 3)), "missile prewarm capacity accepts burst%d" % burst)
    _expect_active(64, 0, "sixteen complete bursts exactly fill missile pool")
    var missiles_before: Array = _weapons.call("get_active_missiles")
    _main_scene.weapon_mode = 2
    _main_scene.weapon_rank = 3
    _expect(int(_main_scene.call("_fire_player")) == 0, "full missile pool rejects complete main+wing attack")
    _expect(_weapons.call("get_active_missiles") == missiles_before and get_nodes_in_group("player_bullet").is_empty(), "missile rejection allocates neither partial missiles nor wing bullets")
    _expect(int(_main_scene.volley_count) == 0, "rejected special burst does not increment firing telemetry")
    await _fresh()
    for burst in range(20):
        _weapons.call("fire", 4, Vector3.ZERO, 3)
    _expect_active(0, 80, "segment backpressure fixture leaves16 of96 slots free")
    var targets: Array[Node3D] = []
    for index in range(5):
        targets.append(_enemy(Vector3(0.0, 0.0, 2.0 - float(index) * 3.0)))
    _main_scene.weapon_mode = 3
    _main_scene.weapon_rank = 3
    _expect(int(_main_scene.call("_fire_player")) == 0, "five-link chain needing20 slots rejects when only16 remain")
    _expect_active(0, 80, "chain rejection cannot reserve a partial path")
    for target in targets:
        _expect(_hp(target) == 100, "chain preflight happens before instant target damage")
    _expect(get_nodes_in_group("player_bullet").is_empty() and int(_main_scene.volley_count) == 0, "chain rejection also preserves wing pool and volley count")
    _weapons.call("clear")
    _expect(int(_main_scene.call("_fire_player")) == 12, "clearing capacity permits the complete chain plus12 wing bullets")
    for target in targets:
        _expect(_hp(target) == 97, "successful retry applies one chain hit to each target")
    await _fresh()
    for burst in range(24):
        _expect(bool(_weapons.call("fire", 4, Vector3.ZERO, 3)), "segment pool admits complete laser burst%d" % burst)
    _expect_active(0, 96, "24 complete laser bursts fill96 segments")
    var laser_target := _enemy(Vector3(-0.65, 0.0, -4.0))
    _expect(not bool(_weapons.call("fire", 4, Vector3.ZERO, 3)) and _hp(laser_target) == 100, "saturated laser cannot apply invisible damage")


func _test_wingguns_and_overdrive() -> void:
    for mode in [2, 3, 4]:
        for rank in [1, 3]:
            await _fresh()
            _main_scene.weapon_mode = mode
            _main_scene.weapon_rank = rank
            var wing_count := 6 if rank == 1 else 12
            var profile: Dictionary = _weapons.call("get_profile", mode, rank)
            _expect(int(_main_scene.call("_fire_player")) == wing_count + int(profile["projectiles"]), "special mode%d rank%d preserves its wingguns" % [mode, rank])
            _expect(get_nodes_in_group("player_bullet").size() == wing_count, "special main weapon does not duplicate ordinary main bullets")
            for bullet in get_nodes_in_group("player_bullet"):
                _expect(int(bullet.get_meta("emitter", -1)) >= 0, "normal special-mode ballistics originate only from actual wing emitters")
        await _fresh()
        _main_scene.weapon_mode = mode
        _main_scene.weapon_rank = 3
        var target := _enemy(Vector3(0.0, 0.0, -4.0))
        while _main_scene.idle_player_bullets.size() > 11:
            _main_scene.call("_spawn_bullet", Vector3(20.0, 0.0, -30.0), true, 0.0)
        var count_before := get_nodes_in_group("player_bullet").size()
        _expect(int(_main_scene.call("_fire_player")) == 0, "11 free wing slots reject rank3 mode%d atomically" % mode)
        _expect_active(0, 0, "wing capacity is checked before any special resource allocation")
        _expect(_hp(target) == 100 and int(_main_scene.volley_count) == 0, "wing-capacity rejection prevents special damage and telemetry")
        _expect(get_nodes_in_group("player_bullet").size() == count_before, "wing-capacity rejection preserves existing bullets")
        _main_scene.call("_release_bullet", get_nodes_in_group("player_bullet")[0])
        _expect(int(_main_scene.call("_fire_player")) > 0, "exact12 free wing slots admit complete special attack")
        _expect(_main_scene.idle_player_bullets.is_empty(), "successful exact-capacity attack fills wing pool without partial remainder")
        await _fresh()
        _main_scene.weapon_mode = mode
        _main_scene.weapon_rank = 5
        _expect(bool(_main_scene.call("_start_overdrive")), "E overdrive is available from mode%d" % mode)
        _expect(int(_main_scene.call("_fire_player")) == 100 and get_nodes_in_group("player_bullet").size() == 100, "E retains the real100-ballistic attack in mode%d" % mode)
        _expect_active(0, 0, "E does not stack hidden special damage on the100-shot volley")
        _main_scene.call("_update_arcade", 6.0)
        _expect(int(_main_scene.weapon_mode) == mode and float(_main_scene.overdrive_timer) == 0.0, "overdrive expiration returns to the user's selected mode")


func _test_pause_death_restart() -> void:
    await _fresh()
    _weapons.call("fire", 2, Vector3.ZERO, 3)
    _weapons.call("fire", 4, Vector3.ZERO, 3)
    var missiles: Array = _weapons.call("get_active_missiles")
    _main_scene.is_paused = true
    _weapons.call("advance", 0.5)
    _main_scene.call("_physics_process", 0.5)
    _expect(_weapons.call("get_active_missiles") == missiles, "pause freezes missile positions, age and target locks")
    _expect_active(4, 4, "pause freezes existing beam lifetimes")
    _expect(not bool(_weapons.call("fire", 2, Vector3.ZERO, 3)) and int(_main_scene.call("_fire_player")) == 0, "pause rejects direct and integrated firing")
    _main_scene.is_paused = false
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.call("_damage_player", 1)
    _expect(bool(_main_scene.is_game_over), "lethal damage enters game over")
    _expect_active(0, 0, "death immediately clears missiles and energy segments")
    _expect(not bool(_weapons.call("fire", 4, Vector3.ZERO, 3)), "game over rejects direct special firing")
    _main_scene.weapon_mode = 4
    _key(KEY_R)
    _expect(not bool(_main_scene.is_game_over) and int(_main_scene.weapon_mode) == 1, "R restart restores original bullet mode")
    _expect_active(0, 0, "restart has no stale weapon visuals or collision state")
    _weapons.call("fire", 2, Vector3.ZERO, 1)
    _weapons.call("advance", 3.0)
    _expect_active(0, 0, "unhit missiles expire at bounded lifetime")


func _test_resources() -> void:
    await _fresh()
    var signature := _resource_signature()
    var pools: Dictionary = _main_scene.call("get_pool_stats")
    for cycle in range(60):
        for mode in [2, 3, 4]:
            _expect(bool(_weapons.call("fire", mode, Vector3.ZERO, 5)), "resource cycle admits each mode after clear")
            _weapons.call("advance", 0.05)
            _weapons.call("clear")
        _expect(_resource_signature() == signature, "weapon node/mesh/material identities remain fixed through cycle%d" % cycle)
        _expect_active(0, 0, "clear leaves no live weapon slot")
    await _fresh()
    _expect(_resource_signature() == signature, "restart reuses prewarmed weapon nodes and resources")
    var final_pools: Dictionary = _main_scene.call("get_pool_stats")
    for kind in pools:
        _expect(int(final_pools[kind]["created"]) == int(pools[kind]["created"]), "weapon tests never grow shared pool %s" % kind)


func _fresh() -> void:
    _main_scene.call("_restart_game")
    _main_scene.set_process(false)
    _main_scene.set_physics_process(false)
    _main_scene.is_paused = true
    await process_frame
    await process_frame
    _main_scene.is_paused = false
    _main_scene.rng.seed = 20261004
    _main_scene.spawn_timer = 1000.0
    _main_scene.swarm_timer = 1000.0
    _main_scene.next_boss_kill_target = 2_000_000_000


func _enemy(at: Vector3, radius: float = 0.5, health: int = 100) -> Node3D:
    var enemy: Node3D = _main_scene.call("_activate_enemy", "scout", at, "standard")
    enemy.set_meta("hp", health)
    enemy.set_meta("radius", radius)
    return enemy


func _hp(enemy: Node3D) -> int:
    return int(enemy.get_meta("hp"))


func _key(code: int, pressed: bool = true, echo: bool = false) -> void:
    var event := InputEventKey.new()
    event.keycode = code
    event.pressed = pressed
    event.echo = echo
    _main_scene.call("_unhandled_key_input", event)


func _expect_active(missiles: int, segments: int, message: String) -> void:
    var stats: Dictionary = _weapons.call("get_stats")
    _expect(int(stats["missiles_active"]) == missiles and int(stats["segments_active"]) == segments, message)
    _expect(int(stats["missile_capacity"]) == 64 and int(stats["segment_capacity"]) == 96, "special pools retain fixed64/96 capacities")


func _resource_signature() -> Array:
    var identities: Dictionary = {}
    _collect_node_resources(_weapons, identities)
    for property in _weapons.get_property_list():
        var value: Variant = _weapons.get(str(property["name"]))
        if value is Resource:
            identities[value.get_instance_id()] = true
    var result: Array = identities.keys()
    result.sort()
    return result


func _collect_node_resources(node: Node, identities: Dictionary) -> void:
    identities[node.get_instance_id()] = true
    if node is MeshInstance3D:
        if node.mesh != null:
            identities[node.mesh.get_instance_id()] = true
        if node.material_override != null:
            identities[node.material_override.get_instance_id()] = true
    for child in node.get_children():
        _collect_node_resources(child, identities)


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

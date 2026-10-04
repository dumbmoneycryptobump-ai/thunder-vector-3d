extends SceneTree

const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const NEW_ENEMY_ASSETS := ["enemy_interceptor_imagegen_v1.png", "enemy_bomber_imagegen_v1.png"]
const CAPACITIES := {"player_bullet": 1024, "enemy_bullet": 128, "scout": 64, "heavy": 16}

var _main_scene: Node
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Content expansion test requires --headless")
        quit(1)
        return
    _test_new_assets()
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("CONTENT_EXPANSION_TEST_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    # Apply defaults in memory only; no settings UI or persistence API is invoked.
    _main_scene.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")
    _main_scene.is_paused = true

    await _test_variant_reuse()
    await _test_interceptor_movement()
    await _test_all_formations()
    await _test_atomic_capacity_backpressure()
    await _test_active_budget_backpressure()
    await _test_pause_death_and_boss_gate()
    await _test_boss_progression_and_restart()
    await _test_partial_fan_protection()

    await _reset_scenario()
    _expect_pools_consistent()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("CONTENT_EXPANSION_TEST_PASS assertions=%d variants=2 formations=4 sectors=3 reuse=clean backpressure=atomic fan=atomic settings_writes=0" % _assertions)
    else:
        for failure in _failures:
            push_error("CONTENT_EXPANSION_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_new_assets() -> void:
    for asset_name in NEW_ENEMY_ASSETS:
        var image := _load_asset_image(asset_name)
        if image == null:
            continue
        _expect(image.detect_alpha() != Image.ALPHA_NONE, "%s must contain real transparency" % asset_name)
        for corner in [Vector2i.ZERO, Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), image.get_size() - Vector2i.ONE]:
            _expect(image.get_pixelv(corner).a <= 0.01, "%s corners must be transparent" % asset_name)
        var transparent_samples := 0
        var sample_count := 0
        for x in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
            for y in [0, image.get_height() - 1]:
                transparent_samples += 1 if image.get_pixel(x, y).a <= 0.01 else 0
                sample_count += 1
        for y in range(0, image.get_height(), maxi(1, image.get_height() / 32)):
            for x in [0, image.get_width() - 1]:
                transparent_samples += 1 if image.get_pixel(x, y).a <= 0.01 else 0
                sample_count += 1
        _expect(float(transparent_samples) / float(sample_count) >= 0.95, "%s border must be clear for a clean cutout" % asset_name)
    _load_asset_image("sector_nebula_imagegen_v1.png")


func _load_asset_image(asset_name: String) -> Image:
    var texture := load("res://assets/generated/" + asset_name) as Texture2D
    _expect(texture != null, "%s must load as an imported texture" % asset_name)
    if texture == null:
        return null
    var image := texture.get_image()
    _expect(image != null and not image.is_empty(), "%s must decode to pixels" % asset_name)
    if image == null or image.is_empty():
        return null
    _expect(image.get_width() >= 512 and image.get_height() >= 512, "%s must have usable resolution without requiring a fixed aspect ratio" % asset_name)
    _expect(image.get_used_rect().size.x > 0 and image.get_used_rect().size.y > 0, "%s must not be an empty transparent image" % asset_name)
    return image


func _test_variant_reuse() -> void:
    for descriptor in [{"pool": "scout", "variant": "interceptor"}, {"pool": "heavy", "variant": "bomber"}]:
        await _reset_scenario()
        var pool_kind: String = descriptor["pool"]
        var archetype: String = descriptor["variant"]
        var standard := _main_scene.call("_activate_enemy", pool_kind, Vector3(1.0, 0.0, -8.0), "standard") as Node3D
        _expect(standard != null, "ordinary %s activation must succeed" % pool_kind)
        if standard == null:
            continue
        var sprite := standard.get_node("ArtSprite") as Sprite3D
        var expected_texture := sprite.texture
        var expected_pixel_size := sprite.pixel_size
        var expected_stats := _enemy_stats(standard)
        var enemy_id := standard.get_instance_id()
        var sprite_id := sprite.get_instance_id()
        var node_count := _count_nodes(_main_scene)
        var art_count := get_nodes_in_group("art_sprite").size()
        _main_scene.call("_release_enemy", standard)

        var variant := _main_scene.call("_activate_enemy", pool_kind, Vector3(5.0, 0.0, -8.0), archetype) as Node3D
        _expect(variant != null and variant.get_instance_id() == enemy_id, "%s must reuse its existing pooled node" % archetype)
        if variant == null:
            continue
        sprite = variant.get_node("ArtSprite") as Sprite3D
        _expect(sprite.get_instance_id() == sprite_id, "%s must reuse the existing art sprite" % archetype)
        _expect(str(variant.get_meta("type")) == pool_kind and str(variant.get_meta("pool_kind")) == pool_kind, "variant must preserve accounting identity")
        _expect(str(variant.get_meta("archetype")) == archetype, "variant behavior must use separate metadata")
        _expect(str(sprite.get_meta("art_role")) == pool_kind, "variant must preserve the prewarmed art role count")
        _expect(sprite.texture.resource_path.ends_with("enemy_%s_imagegen_v1.png" % archetype), "variant must display its own generated texture")
        _expect(sprite.flip_h and sprite.flip_v and is_zero_approx(sprite.rotation_degrees.z), "variant sprite must face the player with no stale roll")
        _expect(int(variant.get_meta("hp")) > int(expected_stats["hp"]) and int(variant.get_meta("score")) > int(expected_stats["score"]), "new archetype must have distinct combat stats")
        _expect(float(variant.get_meta("speed")) > float(expected_stats["speed"]) if archetype == "interceptor" else float(variant.get_meta("speed")) < float(expected_stats["speed"]), "variant speed must match its fast/slow role")
        _expect(_count_nodes(_main_scene) == node_count and get_nodes_in_group("art_sprite").size() == art_count, "variant acquisition must not allocate nodes or art sprites")
        variant.set_meta("age", 99.0)
        variant.set_meta("anchor_x", 99.0)
        variant.set_meta("hp", 999)
        variant.set_meta("speed", 999.0)
        variant.set_meta("score", 999)
        sprite.rotation_degrees.z = 17.0
        _main_scene.call("_release_enemy", variant)
        _expect(not variant.visible and not variant.is_in_group("enemy"), "released variant must leave live gameplay")
        _expect(str(variant.get_meta("archetype")) == "standard" and is_zero_approx(float(variant.get_meta("age"))) and is_zero_approx(float(variant.get_meta("anchor_x"))), "release must clear variant movement state")
        _expect(sprite.texture == expected_texture and is_equal_approx(sprite.pixel_size, expected_pixel_size), "release must restore ordinary texture and scale")
        _expect(is_zero_approx(sprite.rotation_degrees.z), "release must clear sprite banking")
        standard = _main_scene.call("_activate_enemy", pool_kind, Vector3(-2.0, 0.0, -7.0), "standard") as Node3D
        _expect(standard.get_instance_id() == enemy_id and _enemy_stats(standard) == expected_stats, "ordinary reuse must restore all combat stats")
        _expect(is_zero_approx(float(standard.get_meta("age"))) and is_equal_approx(float(standard.get_meta("anchor_x")), -2.0), "ordinary activation must initialize movement state from the new spawn")
        _expect_pools_consistent()


func _test_interceptor_movement() -> void:
    await _reset_scenario()
    var interceptor := _main_scene.call("_activate_enemy", "scout", Vector3(6.4, 0.0, -7.0), "interceptor") as Node3D
    _expect(interceptor != null, "movement fixture interceptor must activate")
    if interceptor == null:
        return
    interceptor.set_meta("speed", 0.0)
    interceptor.set_meta("shoot_timer", 999.0)
    var start_x := interceptor.position.x
    var moved := false
    for index in range(200):
        _main_scene.call("_update_enemies", 0.025)
        _expect(absf(interceptor.position.x) <= 7.10001, "interceptor sweep must stay inside the combat corridor")
        moved = moved or not is_equal_approx(interceptor.position.x, start_x)
    _expect(moved and float(interceptor.get_meta("age")) > 0.0, "interceptor must advance its independent sweep")
    _expect(is_equal_approx(interceptor.position.z, -7.0), "movement fixture must not escape while checking the sweep")


func _test_all_formations() -> void:
    await _reset_scenario()
    _main_scene.is_paused = false
    var node_count := _count_nodes(_main_scene)
    var art_count := get_nodes_in_group("art_sprite").size()
    var expected_counts := [1, 2, 3, 3]
    var names: Dictionary = {}
    for index in range(4):
        var spawned: int = _main_scene.call("_spawn_encounter")
        _expect(spawned == expected_counts[index] and _live_count("enemy") == spawned, "scheduled formation must activate the complete planned wave")
        _expect(_main_scene.wave_number == index + 1 and _main_scene.pending_encounter.is_empty(), "successful formation must commit exactly one wave")
        _expect(float(_main_scene._last_encounter_interval_scale) >= float(spawned), "formation interval must compensate for enemy count")
        _expect(not String(_main_scene.wave_name).is_empty(), "formation must expose its HUD name")
        _expect(String(_main_scene.ui_sector.text).contains(String(_main_scene.wave_name)), "sector HUD must reflect the latest formation")
        names[_main_scene.wave_name] = true
        _expect(_count_nodes(_main_scene) == node_count and get_nodes_in_group("art_sprite").size() == art_count, "formation activation must not allocate nodes")
        _release_ordinary_enemies()
    _expect(names.size() == 4, "all four formation names must be distinct")
    _expect_pools_consistent()


func _test_atomic_capacity_backpressure() -> void:
    await _reset_scenario()
    _main_scene.is_paused = false
    var occupied: Array[Node3D] = []
    for index in range(16):
        occupied.append(_main_scene.call("_activate_enemy", "heavy", Vector3(0.0, 0.0, -8.0), "standard") as Node3D)
    for index in range(4):
        _main_scene.pending_encounter = _main_scene.encounter_director.next_wave(0)
    var pending: Dictionary = _main_scene.pending_encounter.duplicate(true)
    var stats_before: Dictionary = _main_scene.call("get_pool_stats")
    for index in range(3):
        _expect(int(_main_scene.call("_spawn_encounter")) == 0, "exhausted heavy pool must reject the entire escort wave")
        _expect(_main_scene.pending_encounter == pending and _main_scene.encounter_director.wave_number == 4 and _main_scene.wave_number == 0, "backpressure must retain exactly the same pending wave")
        _expect(_live_count("enemy") == 16 and _main_scene.idle_scouts.size() == 64, "failed mixed-family wave must not partially consume scouts")
    for index in range(12):
        _main_scene.call("_release_enemy", occupied[index])
    _expect(int(_main_scene.call("_spawn_encounter")) == 3, "escort must resume atomically once capacity and active budget permit")
    _expect(_main_scene.wave_number == 4 and _main_scene.pending_encounter.is_empty(), "resumed escort must not skip its queued wave")
    var stats_after: Dictionary = _main_scene.call("get_pool_stats")
    _expect(int(stats_after["heavy"]["active"]) == 5 and int(stats_after["scout"]["active"]) == 2, "escort must respect both family budgets after resuming")
    _expect(stats_before["heavy"]["exhausted"] == stats_after["heavy"]["exhausted"] and stats_before["scout"]["exhausted"] == stats_after["scout"]["exhausted"], "preflight backpressure must not count as an actual pool exhaustion")
    _expect_pools_consistent()


func _test_active_budget_backpressure() -> void:
    await _reset_scenario()
    _main_scene.is_paused = false
    var occupied: Array[Node3D] = []
    for index in range(12):
        occupied.append(_main_scene.call("_activate_enemy", "scout", Vector3(0.0, 0.0, -8.0), "standard") as Node3D)
    _main_scene.encounter_director.next_wave(0)
    _main_scene.pending_encounter = _main_scene.encounter_director.next_wave(0)
    var pending: Dictionary = _main_scene.pending_encounter.duplicate(true)
    _expect(int(_main_scene.call("_spawn_encounter")) == 0, "active scout budget must stop a pair despite idle pool capacity")
    _main_scene.call("_release_enemy", occupied[0])
    _expect(int(_main_scene.call("_spawn_encounter")) == 0, "one freed slot must not allow half a pair")
    _expect(_main_scene.pending_encounter == pending and _live_count("enemy") == 11, "budget retry must keep the same whole plan")
    _main_scene.call("_release_enemy", occupied[1])
    _expect(int(_main_scene.call("_spawn_encounter")) == 2 and _live_count("enemy") == 12, "two freed slots must allow the pair without exceeding budget")
    _expect(_main_scene.wave_number == 2 and _main_scene.encounter_director.wave_number == 2, "retry must not consume an extra director wave")
    _expect_pools_consistent()


func _test_pause_death_and_boss_gate() -> void:
    await _reset_scenario()
    for gate in ["is_paused", "is_game_over", "boss_active"]:
        _main_scene.is_paused = false
        _main_scene.is_game_over = false
        _main_scene.boss_active = false
        _main_scene.set(gate, true)
        _expect(int(_main_scene.call("_spawn_encounter")) == 0, "%s must block scheduled encounters" % gate)
        _expect(_main_scene.wave_number == 0 and _main_scene.encounter_director.wave_number == 0 and _main_scene.pending_encounter.is_empty(), "%s must not consume or queue a wave" % gate)
        if gate != "boss_active":
            var previous_elapsed: float = _main_scene.elapsed
            var previous_timer: float = _main_scene.spawn_timer
            _main_scene.call("_physics_process", 1.0)
            _expect(_main_scene.elapsed == previous_elapsed and _main_scene.spawn_timer == previous_timer, "%s must freeze gameplay timing" % gate)
    _main_scene.boss_active = false


func _test_boss_progression_and_restart() -> void:
    await _reset_scenario()
    _main_scene.call("_set_sector", -50)
    _expect(_main_scene.sector_index == 0, "negative sector selections must clamp")
    _main_scene.call("_set_sector", 50)
    _expect(_main_scene.sector_index == 2, "large sector selections must clamp")
    _main_scene.call("_set_sector", 0)
    _main_scene.level = 99
    _main_scene.call("_update_ui")
    _expect(_main_scene.sector_index == 0, "weapon level must not advance sector progression")
    for index in range(3):
        _main_scene.pending_encounter = _main_scene.encounter_director.next_wave(0)
        _main_scene.call("_spawn_boss")
        var boss := _first_boss()
        _expect(boss != null, "boss progression fixture must spawn a boss")
        if boss == null:
            continue
        _main_scene.call("_damage_enemy", boss, int(boss.get_meta("hp")))
        _expect(_main_scene.bosses_defeated == index + 1 and _main_scene.sector_index == mini(index + 1, 2), "actual boss defeat must advance and clamp sector progression")
        _expect(_main_scene.pending_encounter.is_empty(), "boss defeat must invalidate the previous sector's pending encounter")
        var descriptor: Dictionary = _main_scene.encounter_director.get_sector(_main_scene.sector_index)
        _expect(String(_main_scene.ui_sector.text).contains(String(descriptor["name"])), "sector HUD must show the new sector name")
        _expect(_main_scene.sector_environment != null, "sector progression must retain a live environment")
        _main_scene.call("_damage_enemy", boss, 99999)
        _expect(_main_scene.bosses_defeated == index + 1, "queued boss must not advance the sector twice")
        await process_frame
        await process_frame
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    await process_frame
    await process_frame
    _expect(_main_scene.bosses_defeated == 0 and _main_scene.sector_index == 0 and _main_scene.wave_number == 0, "restart must reset all content progression")
    _expect(_main_scene.encounter_director.wave_number == 0 and _main_scene.pending_encounter.is_empty(), "restart must clear director and pending state")
    _expect(_live_count("enemy") == 0 and _live_count("pickup") == 0, "restart must clean boss encounter actors")
    _expect_pools_consistent()


func _test_partial_fan_protection() -> void:
    await _reset_scenario()
    var bomber := _main_scene.call("_activate_enemy", "heavy", Vector3(0.0, 0.0, -5.0), "bomber") as Node3D
    _expect(bomber != null, "fan fixture bomber must activate")
    if bomber == null:
        return
    for index in range(127):
        _main_scene.call("_spawn_bullet", Vector3(0.0, 0.0, -10.0), false, 0.0)
    var before_stats: Dictionary = _main_scene.call("get_pool_stats")
    _expect(not bool(_main_scene.call("_fire_enemy", bomber)), "bomber must defer when fewer than three voices in the bullet pool are free")
    _expect(_live_count("enemy_bullet") == 127, "failed bomber fan must emit no partial bullets")
    var bullets := get_nodes_in_group("enemy_bullet")
    _main_scene.call("_release_bullet", bullets[0])
    _main_scene.call("_release_bullet", bullets[1])
    var previous_ids: Dictionary = {}
    for bullet in get_nodes_in_group("enemy_bullet"):
        previous_ids[bullet.get_instance_id()] = true
    _expect(bool(_main_scene.call("_fire_enemy", bomber)), "bomber must emit a complete fan with three available slots")
    _expect(_live_count("enemy_bullet") == 128, "successful bomber fan must consume exactly three slots")
    var lateral_speeds: Array[float] = []
    for bullet in get_nodes_in_group("enemy_bullet"):
        if not previous_ids.has(bullet.get_instance_id()):
            lateral_speeds.append(float(bullet.get_meta("velocity_x")))
    lateral_speeds.sort()
    _expect(lateral_speeds.size() == 3, "complete bomber volley must contain three distinct pooled bullets")
    if lateral_speeds.size() == 3:
        _expect(lateral_speeds[0] < 0.0 and is_zero_approx(lateral_speeds[1]) and lateral_speeds[2] > 0.0 and is_equal_approx(-lateral_speeds[0], lateral_speeds[2]), "bomber volley must be a readable symmetric three-way fan")
    bomber.set_meta("shoot_timer", 0.0)
    _main_scene.call("_update_enemies", 0.05)
    _expect(is_equal_approx(float(bomber.get_meta("shoot_timer")), 0.15), "capacity-blocked enemy must use the short retry interval")
    _expect(_live_count("enemy_bullet") == 128, "automatic retry must not overrun the bullet pool")
    var after_stats: Dictionary = _main_scene.call("get_pool_stats")
    _expect(before_stats["enemy_bullet"]["exhausted"] == after_stats["enemy_bullet"]["exhausted"], "fan preflight must avoid underlying pool exhaustion")
    _expect_pools_consistent()


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = 20260913
    await process_frame
    await process_frame


func _enemy_stats(enemy: Node3D) -> Dictionary:
    return {"hp": enemy.get_meta("hp"), "speed": enemy.get_meta("speed"), "score": enemy.get_meta("score"), "radius": enemy.get_meta("radius")}


func _release_ordinary_enemies() -> void:
    for enemy in get_nodes_in_group("enemy"):
        if is_instance_valid(enemy) and not bool(enemy.get_meta("is_boss", false)):
            _main_scene.call("_release_enemy", enemy)


func _first_boss() -> Node3D:
    for enemy in get_nodes_in_group("enemy"):
        if is_instance_valid(enemy) and not enemy.is_queued_for_deletion() and bool(enemy.get_meta("is_boss", false)):
            return enemy as Node3D
    return null


func _live_count(group_name: String) -> int:
    var count := 0
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            count += 1
    return count


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _expect_pools_consistent() -> void:
    var stats: Dictionary = _main_scene.call("get_pool_stats")
    for pool_kind in CAPACITIES:
        _expect(int(stats[pool_kind]["created"]) == CAPACITIES[pool_kind], "%s fixed capacity must not change" % pool_kind)
        _expect(int(stats[pool_kind]["active"]) + int(stats[pool_kind]["idle"]) == int(stats[pool_kind]["created"]), "%s active and idle counts must account for every pooled node" % pool_kind)


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition and _failures.size() < 30:
        _failures.append(message)

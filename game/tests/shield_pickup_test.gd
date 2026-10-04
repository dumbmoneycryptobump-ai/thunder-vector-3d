extends SceneTree

const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const SHIELD_TEXTURE_PATH := "res://assets/generated/pickup_shield_imagegen_v1.png"

var _main_scene: Node
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Shield pickup test requires --headless")
        quit(1)
        return
    _test_alpha_asset()
    var packed_scene := load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("SHIELD_PICKUP_TEST_FAIL: main scene could not load")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    _main_scene.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    _main_scene.call("_apply_settings")
    _main_scene.is_paused = true

    await _test_collect_refresh_and_art()
    await _test_contact_absorption_and_invulnerability()
    await _test_bullet_absorption_and_guards()
    await _test_expiry_and_paused_timing()
    await _test_first_interceptor_drop()
    await _test_ring_reuse_and_restart()
    await _test_game_over_and_lethal_order()

    await _reset_scenario()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("SHIELD_PICKUP_TEST_PASS assertions=%d alpha=clear collection=collision refresh=nonstacking absorption=single_hit expiry=12s intro=once ring=reused lethal_order=preserved settings_writes=0" % _assertions)
    else:
        for failure in _failures:
            push_error("SHIELD_PICKUP_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_alpha_asset() -> void:
    var texture := load(SHIELD_TEXTURE_PATH) as Texture2D
    _expect(texture != null, "shield image must import as a texture")
    if texture == null:
        return
    var image := texture.get_image()
    _expect(image != null and not image.is_empty(), "shield image must decode")
    if image == null or image.is_empty():
        return
    _expect(image.get_width() >= 512 and image.get_height() >= 512, "shield image must have usable resolution")
    _expect(image.detect_alpha() != Image.ALPHA_NONE, "shield image must have real alpha rather than a painted background")
    _expect(image.get_used_rect().size.x > 0 and image.get_used_rect().size.y > 0, "shield image must contain visible content")
    for corner in [Vector2i.ZERO, Vector2i(image.get_width() - 1, 0), Vector2i(0, image.get_height() - 1), image.get_size() - Vector2i.ONE]:
        _expect(image.get_pixelv(corner).a <= 0.01, "shield image corners must be clear")
    var transparent := 0
    var samples := 0
    for x in range(0, image.get_width(), maxi(1, image.get_width() / 32)):
        for y in [0, image.get_height() - 1]:
            transparent += 1 if image.get_pixel(x, y).a <= 0.01 else 0
            samples += 1
    for y in range(0, image.get_height(), maxi(1, image.get_height() / 32)):
        for x in [0, image.get_width() - 1]:
            transparent += 1 if image.get_pixel(x, y).a <= 0.01 else 0
            samples += 1
    _expect(float(transparent) / float(samples) >= 0.95, "shield image border must be transparent")


func _test_collect_refresh_and_art() -> void:
    await _reset_scenario()
    _main_scene.hp = 3
    _main_scene.call("_spawn_pickup", _main_scene.player.position, "shield")
    var pickup := _first_pickup("shield")
    _expect(pickup != null, "shield pickup must spawn")
    if pickup == null:
        return
    var sprite := pickup.get_node("ArtSprite") as Sprite3D
    _expect(sprite.texture.resource_path == SHIELD_TEXTURE_PATH, "shield pickup must display its dedicated generated texture")
    _expect(str(sprite.get_meta("art_role")) == "pickup_shield" and str(sprite.get_meta("source")) == SHIELD_TEXTURE_PATH, "shield sprite must record its exact art role and source")
    for sibling in pickup.get_children():
        if sibling is MeshInstance3D and bool(sibling.get_meta("procedural_fallback", false)):
            _expect(not sibling.visible, "procedural pickup geometry must not obscure shield art")
    _main_scene.call("_resolve_collisions")
    _main_scene.call("_update_ui")
    _expect(is_equal_approx(float(_main_scene.shield_timer), 12.0), "collecting shield by collision must grant twelve seconds")
    _expect(_main_scene.score == 200 and _main_scene.hp == 3 and _main_scene.level == 1, "shield must award 200 without changing health or weapon level")
    _expect(_main_scene.shield_ring.visible, "active shield must show its protection ring")
    _expect(String(_main_scene.ui_shield.text).contains("12"), "shield HUD must display the initial remaining seconds")
    await process_frame
    await process_frame
    _expect(_pickup_count("shield") == 0, "collected shield must leave the scene")
    _main_scene.call("_update_shield", 4.0)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 8.0), "active shield duration must count down")
    _collect_shield()
    _expect(is_equal_approx(float(_main_scene.shield_timer), 12.0) and _main_scene.score == 400, "another shield must refresh to twelve seconds rather than stack duration")


func _test_contact_absorption_and_invulnerability() -> void:
    await _reset_scenario()
    _collect_shield()
    _main_scene.call("_spawn_boss")
    var boss := _first_boss()
    _expect(boss != null, "contact fixture must spawn a boss")
    if boss == null:
        return
    boss.position = _main_scene.player.position
    boss.set_meta("shoot_timer", 999.0)
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.hp == 5 and is_zero_approx(float(_main_scene.shield_timer)), "shield must absorb an entire two-damage boss contact exactly once")
    _expect(is_equal_approx(float(_main_scene.invulnerability_timer), 0.45), "shield break must grant 0.45 seconds of invulnerability")
    _expect(not _main_scene.shield_ring.visible, "consumed shield must hide its ring")
    _main_scene.call("_resolve_collisions")
    _main_scene.call("_damage_player", 2)
    _expect(_main_scene.hp == 5, "same-frame contact and damage must respect shield-break invulnerability")
    boss.position = Vector3(7.0, 0.0, -12.0)
    _main_scene.spawn_timer = 100.0
    _main_scene.call("_physics_process", 0.46)
    _expect(is_zero_approx(float(_main_scene.invulnerability_timer)), "normal gameplay timing must expire shield-break invulnerability")
    _main_scene.call("_damage_player", 2)
    _expect(_main_scene.hp == 3, "damage after shield-break invulnerability must affect HP normally")


func _test_bullet_absorption_and_guards() -> void:
    await _reset_scenario()
    _collect_shield()
    _main_scene.call("_spawn_bullet", _main_scene.player.position, false, 0.0)
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.hp == 5 and is_zero_approx(float(_main_scene.shield_timer)), "shield must absorb one enemy-bullet hit")
    _expect(_live_count("enemy_bullet") == 0, "shielded collision must still recycle its bullet")
    _collect_shield()
    _main_scene.call("_damage_player", 1)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 12.0), "existing invulnerability must be checked before consuming a refreshed shield")
    _main_scene.invulnerability_timer = 0.0
    _main_scene.set("_pool_stress_mode", true)
    _main_scene.call("_damage_player", 1)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 12.0) and _main_scene.hp == 5, "stress-mode immunity must not consume shields")
    _main_scene.set("_pool_stress_mode", false)
    _main_scene.is_game_over = true
    _main_scene.call("_damage_player", 1)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 12.0), "game-over damage guard must run before shield consumption")
    _main_scene.is_game_over = false
    _main_scene.call("_damage_player", 1)
    _expect(is_zero_approx(float(_main_scene.shield_timer)) and _main_scene.hp == 5, "next eligible hit must consume the refreshed shield without HP loss")


func _test_expiry_and_paused_timing() -> void:
    await _reset_scenario()
    var inactive_label := String(_main_scene.ui_shield.text)
    _collect_shield()
    _main_scene.call("_update_shield", 3.25)
    _main_scene.call("_update_ui")
    _expect(is_equal_approx(float(_main_scene.shield_timer), 8.75), "shield clock must preserve fractional remaining duration")
    _expect(String(_main_scene.ui_shield.text).contains("9"), "shield HUD must round remaining seconds upward")
    _main_scene.is_paused = true
    _main_scene.call("_update_shield", 99.0)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 8.75), "pause must freeze the shield clock")
    _main_scene.is_paused = false
    _main_scene.is_game_over = true
    _main_scene.call("_update_shield", 99.0)
    _expect(is_equal_approx(float(_main_scene.shield_timer), 8.75), "non-playing update must not advance the shield clock")
    _main_scene.is_game_over = false
    _main_scene.call("_update_shield", 8.75)
    _main_scene.call("_update_ui")
    _expect(is_zero_approx(float(_main_scene.shield_timer)) and not _main_scene.shield_ring.visible, "twelve seconds of active gameplay must expire and hide the shield")
    _expect(String(_main_scene.ui_shield.text) == inactive_label, "expired shield must restore the inactive HUD state")
    _main_scene.call("_update_shield", 100.0)
    _expect(_main_scene.shield_timer == 0.0, "expired shield duration must clamp to zero")
    _main_scene.call("_damage_player", 1)
    _expect(_main_scene.hp == 4, "expired shield must no longer prevent damage")


func _test_first_interceptor_drop() -> void:
    await _reset_scenario()
    var interceptor := _main_scene.call("_activate_enemy", "scout", Vector3(0.0, 0.0, -5.0), "interceptor") as Node3D
    _expect(interceptor != null, "intro fixture interceptor must activate")
    if interceptor == null:
        return
    _main_scene.rng.seed = _seed_without_random_drop()
    _main_scene.call("_damage_enemy", interceptor, int(interceptor.get_meta("hp")))
    _expect(_main_scene.shield_intro_dropped and _pickup_count("shield") == 1, "first actual interceptor defeat must guarantee one shield despite a no-drop random roll")
    _main_scene.call("_damage_enemy", interceptor, 999)
    _expect(_pickup_count("shield") == 1, "repeated damage on a released enemy must not duplicate its guaranteed drop")
    for pickup in get_nodes_in_group("pickup"):
        pickup.queue_free()
    await process_frame
    await process_frame
    interceptor = _main_scene.call("_activate_enemy", "scout", Vector3(0.0, 0.0, -5.0), "interceptor") as Node3D
    _main_scene.rng.seed = _seed_without_random_drop()
    _main_scene.call("_damage_enemy", interceptor, int(interceptor.get_meta("hp")))
    _expect(_pickup_count("shield") == 0 and _main_scene.shield_intro_dropped, "later interceptor defeats must use the ordinary random drop path, not repeat the introduction")


func _test_ring_reuse_and_restart() -> void:
    await _reset_scenario()
    var ring := _main_scene.shield_ring as MeshInstance3D
    _expect(ring != null and ring.mesh != null, "shield ring must be precreated with a reusable mesh")
    if ring == null or ring.mesh == null:
        return
    var node_id := ring.get_instance_id()
    var mesh_id := ring.mesh.get_instance_id()
    var initial_nodes := _count_nodes(_main_scene)
    for index in range(4):
        _collect_shield()
        _main_scene.call("_update_shield", 0.1)
        _expect(_main_scene.shield_ring.get_instance_id() == node_id and _main_scene.shield_ring.mesh.get_instance_id() == mesh_id, "shield refresh must not recreate ring nodes or mesh resources")
        _main_scene.shield_intro_dropped = true
        await _reset_scenario()
        _expect(_main_scene.shield_timer == 0.0 and not _main_scene.shield_intro_dropped and not _main_scene.shield_ring.visible, "restart must reset shield duration, introduction and ring visibility")
        _expect(_main_scene.shield_ring.get_instance_id() == node_id and _main_scene.shield_ring.mesh.get_instance_id() == mesh_id, "restart must retain the original shield ring resource")
        _expect(_count_nodes(_main_scene) == initial_nodes, "shield pickup/restart cycles must restore the exact node baseline")


func _test_game_over_and_lethal_order() -> void:
    await _reset_scenario()
    _collect_shield()
    _main_scene.call("_game_over")
    _expect(_main_scene.shield_timer == 0.0 and not _main_scene.shield_ring.visible, "actual game over must clear shield state")
    await _reset_scenario()
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.call("_spawn_bullet", _main_scene.player.position, false, 0.0)
    _main_scene.call("_spawn_pickup", _main_scene.player.position, "shield")
    _main_scene.call("_resolve_collisions")
    _expect(_main_scene.is_game_over and _main_scene.hp == 0, "lethal bullet must still win over a same-frame uncollected shield")
    _expect(_main_scene.shield_timer == 0.0 and _main_scene.score == 0 and not _main_scene.shield_ring.visible, "same-frame shield must not revive or reward a dead player")
    _expect(_pickup_count("shield") == 1 and _live_count("enemy_bullet") == 0, "lethal order must leave pickup uncollected and recycle the damaging bullet")


func _collect_shield() -> void:
    _main_scene.call("_spawn_pickup", _main_scene.player.position, "shield")
    _main_scene.call("_resolve_collisions")
    _main_scene.call("_update_ui")


func _seed_without_random_drop() -> int:
    var probe := RandomNumberGenerator.new()
    for seed_value in range(1, 100):
        probe.seed = seed_value
        if probe.randf() >= 0.17:
            return seed_value
    _expect(false, "test fixture must find a reproducible non-drop RNG seed")
    return 1


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.set("_pool_stress_mode", false)
    _main_scene.rng.seed = 20260913
    await process_frame
    await process_frame
    _main_scene.is_paused = false


func _first_pickup(kind: String) -> Node3D:
    for pickup in get_nodes_in_group("pickup"):
        if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and str(pickup.get_meta("kind", "")) == kind:
            return pickup as Node3D
    return null


func _pickup_count(kind: String) -> int:
    var count := 0
    for pickup in get_nodes_in_group("pickup"):
        if is_instance_valid(pickup) and not pickup.is_queued_for_deletion() and str(pickup.get_meta("kind", "")) == kind:
            count += 1
    return count


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


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition and _failures.size() < 30:
        _failures.append(message)

extends SceneTree

# Targeted CPU-side evidence, not a rendered frame rate or GPU occlusion test.
const SETTINGS := preload("res://scripts/settings_store.gd")
const VIEWPORT := Vector2i(1280, 720)
const SEED := 20261004
const HUD_RECTS := {
    "score": Rect2(18.0, 16.0, 420.0, 152.0),
    "arsenal": Rect2(22.0, 194.0, 253.0, 147.0),
    "route": Rect2(22.0, 359.0, 237.0, 229.0),
    "weapon": Rect2(995.0, 335.0, 252.0, 176.0),
}

var _game: Node
var _camera: Camera3D
var _failures: Array[String] = []
var _assertions := 0
var _formation_rows: Array[Dictionary] = []
var _hud_overlap_rows: Array[Dictionary] = []
var _cpu_summary: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("EXPANDED_EDGE_TEST_FAIL: requires --headless")
        quit(1)
        return
    var scene := load("res://main.tscn") as PackedScene
    _game = scene.instantiate()
    root.add_child(_game)
    _game.set_process(false)
    _game.set_physics_process(false)
    _game.set_process_unhandled_key_input(false)
    _game.settings_values = SETTINGS.DEFAULTS.duplicate(true)
    _game.call("_apply_settings")
    root.size = VIEWPORT
    root.content_scale_size = VIEWPORT
    _camera = _game.camera as Camera3D
    await _reset()
    _expect(root.get_visible_rect().size.is_equal_approx(Vector2(VIEWPORT)), "projection fixture must use its actual1280x720 viewport")
    _test_edge_formations()
    _sample_opaque_player_hud_overlap()
    await _test_independent_enemy_bullet_lifetime()
    await _test_full_missile_cpu_fixture()
    print("EXPANDED_EDGE_JSON " + JSON.stringify({
        "viewport": str(root.get_visible_rect().size),
        "edge_formations": _formation_rows,
        "player_hud_overlap": _hud_overlap_rows,
        "hud_projection_method": "unbanked full billboard plus real texture alpha>=0.5 sampled every8px,33depths at each horizontal extreme; not GPU occlusion",
        "missile_cpu": _cpu_summary,
        "settings_writes": 0,
        "failures": _failures,
    }))
    _game.call("prepare_for_shutdown")
    _game.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("EXPANDED_EDGE_TEST_PASS assertions=%d wing_edges=inside_view enemy_bullets=independent_bounded_reset missile_fixture=64x80 rendering_measured=false" % _assertions)
    else:
        for failure in _failures:
            push_error("EXPANDED_EDGE_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_edge_formations() -> void:
    _game.weapon_rank = 5
    for x in [-10.2, 10.2]:
        for z in [0.5, 10.2]:
            _game.player.position = Vector3(x, 0.0, z)
            _game.call("_update_wingmen", 0.0)
            var members: Array[Node3D] = [_game.player as Node3D]
            for wing in _game.wingmen:
                members.append(wing as Node3D)
            var projections: Array[Dictionary] = []
            for member in members:
                var sprite := member.get_node("ArtSprite") as Sprite3D
                var bounds := _billboard_screen_rect(sprite)
                var center := _camera.unproject_position(member.global_position)
                _expect(member.visible and _camera.is_position_in_frustum(member.global_position), "each expanded-edge formation origin must remain visible in the camera frustum")
                _expect(absf(member.global_position.x) <= 12.0001, "wing origins must stay within the expanded twelve-unit lateral formation limit")
                _expect(bounds.position.x >= 0.0 and bounds.position.y >= 0.0 and bounds.end.x <= VIEWPORT.x and bounds.end.y <= VIEWPORT.y, "the entire unbanked sprite quad must remain on screen at all four movement corners: %s %s" % [str(member.name), str(bounds)])
                projections.append({"name": str(member.name), "world": str(member.global_position), "screen_center": str(center), "full_quad": str(bounds)})
            _formation_rows.append({"player": str(_game.player.position), "members": projections})
    var decoration_nodes: Array[Node] = []
    _collect(_game.map_scenery, decoration_nodes)
    for node in decoration_nodes:
        _expect(not (node is CollisionObject3D) and not (node is CollisionShape3D), "map decoration must not obstruct the expanded formation with collision geometry")


func _billboard_screen_rect(sprite: Sprite3D) -> Rect2:
    _expect(sprite.billboard == BaseMaterial3D.BILLBOARD_ENABLED and sprite.centered, "projection assumes the actual centered billboard art contract")
    var half_size := Vector2(sprite.texture.get_size()) * sprite.pixel_size * 0.5
    var right := _camera.global_basis.x.normalized()
    var up := _camera.global_basis.y.normalized()
    var top_left := _camera.unproject_position(sprite.global_position - right * half_size.x + up * half_size.y)
    var bottom_right := _camera.unproject_position(sprite.global_position + right * half_size.x - up * half_size.y)
    return Rect2(top_left, bottom_right - top_left)


func _sample_opaque_player_hud_overlap() -> void:
    var sprite := _game.player_art as Sprite3D
    var pixels := sprite.texture.get_image()
    var opaque_uv: Array[Vector2] = []
    for x in range(4, pixels.get_width(), 8):
        for y in range(4, pixels.get_height(), 8):
            if pixels.get_pixel(x, y).a >= 0.5:
                opaque_uv.append(Vector2(float(x) / pixels.get_width(), float(y) / pixels.get_height()))
    _expect(not opaque_uv.is_empty(), "HUD overlap sampling must use actual opaque player pixels")
    for x in [-10.2, 10.2]:
        for index in range(33):
            var z := lerpf(0.5, 10.2, float(index) / 32.0)
            _game.player.position = Vector3(x, 0.0, z)
            var bounds := _billboard_screen_rect(sprite)
            var covered := 0
            var by_panel: Dictionary = {}
            for uv in opaque_uv:
                var screen := bounds.position + uv * bounds.size
                for panel in HUD_RECTS:
                    if (HUD_RECTS[panel] as Rect2).has_point(screen):
                        covered += 1
                        by_panel[panel] = int(by_panel.get(panel, 0)) + 1
                        break
            if covered > 0:
                _hud_overlap_rows.append({
                    "world": str(_game.player.position),
                    "sprite_center": str(_camera.unproject_position(sprite.global_position)),
                    "covered_opaque_percent": 100.0 * float(covered) / float(opaque_uv.size()),
                    "covered_samples": covered,
                    "opaque_samples": opaque_uv.size(),
                    "panels": by_panel,
                })
    _expect(_hud_overlap_rows.is_empty(), "sampled opaque player pixels must remain clear of the four HUD panels across the expanded horizontal extremes")


func _test_independent_enemy_bullet_lifetime() -> void:
    await _reset()
    _game.is_paused = false
    var enemy := _game.call("_activate_enemy", "scout", Vector3(0.0, 0.0, 12.49), "standard") as Node3D
    _expect(bool(_game.call("_fire_enemy", enemy)), "edge owner must fire a real enemy bullet")
    enemy.set_meta("shoot_timer", 999.0)
    var bullet := get_nodes_in_group("enemy_bullet")[0] as Node3D
    var launch: Vector3 = bullet.position
    _game.call("_update_enemies", 0.01)
    _expect(not enemy.is_in_group("enemy"), "enemy crossing12.5 must return to its pool")
    _expect(bullet.is_in_group("enemy_bullet") and bullet.position == launch, "owner release must not silently delete or reposition its independent projectile")
    bullet.set_meta("velocity_x", 0.0)
    bullet.position = Vector3(0.0, 0.0, 14.5)
    _game.call("_update_bullets", 0.0)
    _expect(bullet.is_in_group("enemy_bullet"), "enemy projectile must remain live at the exact14.5 boundary")
    _game.call("_update_bullets", 0.001)
    _expect(not bullet.is_in_group("enemy_bullet") and not bullet.visible, "projectile crossing14.5 must return to its independent pool")
    _game.call("_spawn_bullet", Vector3(0.0, 0.0, 13.0), false, 0.0)
    _game.call("_spawn_bullet", Vector3.ZERO, true, 0.0)
    await _reset()
    _expect(get_nodes_in_group("enemy_bullet").is_empty() and get_nodes_in_group("player_bullet").is_empty(), "restart must clear all independent projectiles")
    var pools: Dictionary = _game.call("get_pool_stats")
    _expect(int(pools["enemy_bullet"]["idle"]) == 128 and int(pools["player_bullet"]["idle"]) == 1024, "edge cleanup must restore both full fixed bullet pools")


func _test_full_missile_cpu_fixture() -> void:
    await _reset()
    _game.is_paused = false
    _game.player.position = Vector3(0.0, 0.0, 8.0)
    for family in ["scout", "heavy"]:
        for index in range(64 if family == "scout" else 16):
            var at := Vector3(-9.0 + float(index % 10) * 2.0, 0.0, -10.0 - float(index / 10) * 0.5)
            var enemy := _game.call("_activate_enemy", family, at, "standard") as Node3D
            _expect(enemy != null and enemy.position.z < _game.player.position.z - 1.3, "every analytic target must be live and strictly ahead of all missiles")
    var weapons: Node = _game.special_weapons
    var nodes_before := _count_nodes(_game)
    for volley in range(16):
        _expect(bool(weapons.call("fire", 2, _game.player.position, 5)), "sixteen test-only immediate launches must fill all64 missile slots")
    var before: Dictionary = weapons.call("get_stats")
    _expect(int(before["missiles_active"]) == 64 and get_nodes_in_group("enemy").size() == 80, "CPU fixture must contain the complete64x80 analytical workload")
    const TINY_STEP := 0.0001
    const WARMUP := 32
    const SAMPLES := 160
    for warmup in range(WARMUP):
        weapons.call("advance", TINY_STEP)
    var usec: Array[int] = []
    for sample in range(SAMPLES):
        var started := Time.get_ticks_usec()
        weapons.call("advance", TINY_STEP)
        usec.append(Time.get_ticks_usec() - started)
    usec.sort()
    var after: Dictionary = weapons.call("get_stats")
    _expect(int(after["missiles_active"]) == 64 and get_nodes_in_group("enemy").size() == 80, "all measured calls must preserve the full missile/target workload")
    _expect(int(after["total_hits"]) == int(before["total_hits"]), "separated fixture geometry must avoid hit/kill work contaminating analytic collision timing")
    _expect(int(after["missile_capacity"]) == 64 and int(after["segment_capacity"]) == 96 and int(after["overflow"]) == 0, "full synthetic workload must preserve capacities without overflow")
    _expect(_count_nodes(_game) == nodes_before, "analytical collision passes must not allocate scene nodes")
    _cpu_summary = {
        "description": "synthetic full-capacity64missiles x80stationary pooled enemies; targets ahead, no hits; not natural play or FPS/GPU",
        "engine": Engine.get_version_info()["string"],
        "renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method"),
        "display_driver": DisplayServer.get_name(),
        "seed": SEED,
        "warmup": WARMUP,
        "samples": SAMPLES,
        "advance_delta": TINY_STEP,
        "median_us": usec[SAMPLES / 2],
        "p95_us": usec[ceili(SAMPLES * 0.95) - 1],
        "max_us": usec.back(),
        "nodes_before": nodes_before,
        "nodes_after": _count_nodes(_game),
        "missiles_active": int(after["missiles_active"]),
        "enemies_active": get_nodes_in_group("enemy").size(),
    }
    await _reset()
    _expect(int((weapons.call("get_stats") as Dictionary)["missiles_active"]) == 0, "synthetic stress cleanup must empty all missiles")


func _reset() -> void:
    _game.call("_restart_game")
    _game.is_paused = true
    _game.rng.seed = SEED
    await process_frame
    await process_frame


func _collect(node: Node, result: Array[Node]) -> void:
    result.append(node)
    for child in node.get_children():
        _collect(child, result)


func _count_nodes(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _count_nodes(child)
    return total


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

extends SceneTree

const ASSETS := [
    "player_ship_imagegen_v1.png",
    "enemy_scout_imagegen_v1.png",
    "enemy_heavy_imagegen_v1.png",
    "boss_core_imagegen_v1.png",
    "pickup_power_imagegen_v1.png",
    "pickup_health_imagegen_v1.png",
    "pickup_bomb_imagegen_v1.png",
]
const EXPECTED_ROLES := {
    "player": 1,
    "scout": 32,
    "heavy": 16,
    "boss": 1,
    "pickup_power": 1,
    "pickup_health": 1,
    "pickup_bomb": 1,
}

var failures: Array[String] = []
var _main_scene: Node


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    for asset_name in ASSETS:
        _check_alpha_asset(asset_name)

    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        failures.append("could not load res://main.tscn")
    else:
        _main_scene = packed_scene.instantiate()
        root.add_child(_main_scene)
        _main_scene.call("_spawn_boss")
        _main_scene.call("_spawn_pickup", Vector3(-2.0, 0.0, 0.0), "power")
        _main_scene.call("_spawn_pickup", Vector3(0.0, 0.0, 0.0), "health")
        _main_scene.call("_spawn_pickup", Vector3(2.0, 0.0, 0.0), "bomb")
        await process_frame
        _check_scene_integration()

    if _main_scene != null:
        if _main_scene.has_method("prepare_for_shutdown"):
            _main_scene.call("prepare_for_shutdown")
        _main_scene.queue_free()
        await process_frame
        await process_frame

    if failures.is_empty():
        print("ART_INTEGRATION_TEST_PASS assets=7 alpha=genuine roles=%s renderer=gl_compatibility" % EXPECTED_ROLES)
        quit(0)
    else:
        for failure in failures:
            push_error("ART_INTEGRATION_TEST_FAIL: %s" % failure)
        quit(1)


func _check_alpha_asset(asset_name: String) -> void:
    var resource_path := "res://assets/generated/%s" % asset_name
    var texture := load(resource_path) as Texture2D
    if texture == null:
        failures.append("%s could not be imported as Texture2D" % asset_name)
        return
    var image := texture.get_image()
    if image == null or image.is_empty():
        failures.append("%s could not be decoded" % asset_name)
        return
    if image.get_width() != 1254 or image.get_height() != 1254:
        failures.append("%s has unexpected dimensions %dx%d" % [asset_name, image.get_width(), image.get_height()])
    if image.detect_alpha() == Image.ALPHA_NONE:
        failures.append("%s has no alpha channel" % asset_name)
    var corners := [
        image.get_pixel(0, 0).a,
        image.get_pixel(image.get_width() - 1, 0).a,
        image.get_pixel(0, image.get_height() - 1).a,
        image.get_pixel(image.get_width() - 1, image.get_height() - 1).a,
    ]
    for alpha in corners:
        if float(alpha) > 0.01:
            failures.append("%s has a non-transparent corner" % asset_name)
            break
    var used_rect := image.get_used_rect()
    if used_rect.size.x <= 0 or used_rect.size.y <= 0:
        failures.append("%s has no visible pixels" % asset_name)
    var border_transparency := _border_transparency_ratio(image)
    if border_transparency < 0.95:
        failures.append("%s border is only %.1f%% transparent" % [asset_name, border_transparency * 100.0])
    print("ART_ALPHA asset=%s rect=%s mode=%d border_transparent=%.3f" % [asset_name, used_rect, image.detect_alpha(), border_transparency])


func _border_transparency_ratio(image: Image) -> float:
    var transparent_samples := 0
    var total_samples := 0
    var step := 16
    for x in range(0, image.get_width(), step):
        for y in [0, image.get_height() - 1]:
            total_samples += 1
            if image.get_pixel(x, y).a <= 0.01:
                transparent_samples += 1
    for y in range(0, image.get_height(), step):
        for x in [0, image.get_width() - 1]:
            total_samples += 1
            if image.get_pixel(x, y).a <= 0.01:
                transparent_samples += 1
    return float(transparent_samples) / float(total_samples)


func _check_scene_integration() -> void:
    var counts := {}
    for role in EXPECTED_ROLES:
        counts[role] = 0
    for sprite in get_nodes_in_group("art_sprite"):
        if not (sprite is Sprite3D):
            failures.append("art_sprite group contains a non-Sprite3D node")
            continue
        var art_sprite := sprite as Sprite3D
        var role := str(art_sprite.get_meta("art_role", ""))
        if role not in counts:
            failures.append("unknown art role %s" % role)
            continue
        counts[role] = int(counts[role]) + 1
        if art_sprite.texture == null:
            failures.append("%s art sprite has no texture" % role)
        if not (art_sprite.get_parent() is Node3D):
            failures.append("%s art sprite is not attached to a Node3D" % role)
        for sibling in art_sprite.get_parent().get_children():
            if sibling is MeshInstance3D and bool(sibling.get_meta("procedural_fallback", false)) and sibling.visible:
                failures.append("%s procedural fallback mesh is obscuring generated art" % role)
        if role in ["scout", "heavy", "boss"] and (not art_sprite.flip_h or not art_sprite.flip_v):
            failures.append("%s art is not oriented toward the player" % role)
    for role in EXPECTED_ROLES:
        if int(counts[role]) != int(EXPECTED_ROLES[role]):
            failures.append("role %s count %d, expected %d" % [role, counts[role], EXPECTED_ROLES[role]])
    if ProjectSettings.get_setting("rendering/renderer/rendering_method") != "gl_compatibility":
        failures.append("renderer is not gl_compatibility")

extends RefCounted

const PLAYER_TEXTURE: Texture2D = preload("res://assets/generated/player_ship_imagegen_v1.png")
const SCOUT_TEXTURE: Texture2D = preload("res://assets/generated/enemy_scout_imagegen_v1.png")
const HEAVY_TEXTURE: Texture2D = preload("res://assets/generated/enemy_heavy_imagegen_v1.png")
const BOSS_TEXTURE: Texture2D = preload("res://assets/generated/boss_core_imagegen_v1.png")
const POWER_TEXTURE: Texture2D = preload("res://assets/generated/pickup_power_imagegen_v1.png")
const HEALTH_TEXTURE: Texture2D = preload("res://assets/generated/pickup_health_imagegen_v1.png")
const BOMB_TEXTURE: Texture2D = preload("res://assets/generated/pickup_bomb_imagegen_v1.png")


func attach_player(parent: Node3D) -> Sprite3D:
    return _attach(parent, PLAYER_TEXTURE, 3.6, 0.52, "player", 0.0)


func attach_scout(parent: Node3D) -> Sprite3D:
    return _attach(parent, SCOUT_TEXTURE, 2.6, 0.46, "scout", 180.0)


func attach_heavy(parent: Node3D) -> Sprite3D:
    return _attach(parent, HEAVY_TEXTURE, 4.0, 0.66, "heavy", 180.0)


func attach_boss(parent: Node3D) -> Sprite3D:
    return _attach(parent, BOSS_TEXTURE, 6.4, 0.92, "boss", 180.0)


func attach_pickup(parent: Node3D, kind: String) -> Sprite3D:
    match kind:
        "health":
            return _attach(parent, HEALTH_TEXTURE, 1.35, 0.48, "pickup_health", 0.0)
        "bomb":
            return _attach(parent, BOMB_TEXTURE, 1.35, 0.48, "pickup_bomb", 0.0)
        _:
            return _attach(parent, POWER_TEXTURE, 1.35, 0.48, "pickup_power", 0.0)


func _attach(
    parent: Node3D,
    texture: Texture2D,
    world_width: float,
    y_offset: float,
    role: String,
    image_rotation: float
) -> Sprite3D:
    _hide_procedural_hull(parent)
    var sprite := Sprite3D.new()
    sprite.name = "ArtSprite"
    sprite.texture = texture
    sprite.pixel_size = world_width / float(texture.get_width())
    sprite.position = Vector3(0.0, y_offset, 0.0)
    var flip_image := is_equal_approx(absf(image_rotation), 180.0)
    sprite.flip_h = flip_image
    sprite.flip_v = flip_image
    sprite.rotation_degrees.z = 0.0
    sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
    sprite.no_depth_test = false
    sprite.shaded = false
    sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    sprite.set_meta("art_role", role)
    sprite.set_meta("source", texture.resource_path)
    parent.add_child(sprite)
    sprite.add_to_group("art_sprite")
    return sprite


func _hide_procedural_hull(parent: Node3D) -> void:
    for child in parent.get_children():
        if child is MeshInstance3D:
            child.visible = false
            child.set_meta("procedural_fallback", true)

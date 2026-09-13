extends Node3D

# Thunder Vector 3D
# A self-contained 3D vertical shooter for Godot 4.7.2.
# Original transparent art is layered over local primitive-mesh fallbacks.

const PLAYER_SPEED := 10.0
const PLAYER_MAX_HP := 5
const PLAYER_MIN_X := -7.8
const PLAYER_MAX_X := 7.8
const PLAYER_MIN_Z := 1.5
const PLAYER_MAX_Z := 8.2
const PLAYER_SHOT_INTERVAL := 0.13
const BASE_ENEMY_INTERVAL := 1.05
const BOSS_EVERY_KILLS := 20
const PLAYER_BULLET_POOL_SIZE := 96
const ENEMY_BULLET_POOL_SIZE := 128
const SCOUT_POOL_SIZE := 32
const HEAVY_POOL_SIZE := 16
const SETTINGS_STORE_SCRIPT := preload("res://scripts/settings_store.gd")
const VISUAL_FACTORY_SCRIPT := preload("res://scripts/visual_factory.gd")

var rng := RandomNumberGenerator.new()
var player: CharacterBody3D
var player_art: Sprite3D
var camera: Camera3D
var stars: Array = []
var moving_grid_lines: Array = []

var score := 0
var level := 1
var hp := PLAYER_MAX_HP
var bombs := 2
var kills := 0
var next_boss_kill_target := BOSS_EVERY_KILLS
var boss_active := false
var is_paused := false
var is_game_over := false
var elapsed := 0.0
var spawn_timer := 0.2
var shot_timer := 0.0
var invulnerability_timer := 0.0

var ui_score: Label
var ui_hp: Label
var ui_level: Label
var ui_bombs: Label
var ui_status: Label
var ui_center: Label
var ui_controls: Label
var ui_pool: Label
var settings_overlay: ColorRect
var ui_settings: Label

var sfx_laser: AudioStream
var sfx_explosion: AudioStream
var sfx_pickup: AudioStream
var sfx_hit: AudioStream
var active_sfx_players: Array[AudioStreamPlayer] = []
var _is_shutting_down := false

var mat_player: StandardMaterial3D
var mat_player_accent: StandardMaterial3D
var mat_enemy: StandardMaterial3D
var mat_enemy_accent: StandardMaterial3D
var mat_heavy: StandardMaterial3D
var mat_boss: StandardMaterial3D
var mat_boss_accent: StandardMaterial3D
var mat_player_bullet: StandardMaterial3D
var mat_enemy_bullet: StandardMaterial3D
var mat_grid: StandardMaterial3D
var mat_star_a: StandardMaterial3D
var mat_star_b: StandardMaterial3D

var idle_player_bullets: Array[Node3D] = []
var idle_enemy_bullets: Array[Node3D] = []
var idle_scouts: Array[Node3D] = []
var idle_heavies: Array[Node3D] = []
var pool_created_counts := {
    "player_bullet": 0,
    "enemy_bullet": 0,
    "scout": 0,
    "heavy": 0,
}
var pool_reuse_counts := {
    "player_bullet": 0,
    "enemy_bullet": 0,
    "scout": 0,
    "heavy": 0,
}
var pool_exhaustion_counts := {
    "player_bullet": 0,
    "enemy_bullet": 0,
    "scout": 0,
    "heavy": 0,
}
var _pool_stress_mode := false
var _pool_ui_timer := 0.0
var settings_store: RefCounted
var visual_factory: RefCounted
var settings_values: Dictionary = {}
var difficulty_profile: Dictionary = {}
var settings_open := false
var settings_index := 0


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    rng.randomize()
    _load_audio()
    _load_settings()
    _create_materials()
    visual_factory = VISUAL_FACTORY_SCRIPT.new()
    _prewarm_pools()
    _create_environment()
    _create_arena()
    _create_player()
    _create_ui()
    _restart_game()


func _exit_tree() -> void:
    prepare_for_shutdown()


func prepare_for_shutdown() -> void:
    if _is_shutting_down:
        return
    _is_shutting_down = true
    for audio in active_sfx_players:
        if is_instance_valid(audio):
            audio.stop()
            audio.stream = null
            audio.queue_free()
    active_sfx_players.clear()
    sfx_laser = null
    sfx_explosion = null
    sfx_pickup = null
    sfx_hit = null


func _physics_process(delta: float) -> void:
    if is_paused or is_game_over:
        return

    elapsed += delta
    shot_timer -= delta
    spawn_timer -= delta
    invulnerability_timer = max(0.0, invulnerability_timer - delta)
    _pool_ui_timer -= delta

    _update_player(delta)
    if _pool_stress_mode and shot_timer <= 0.0:
        _fire_player()
        shot_timer = maxf(0.055, PLAYER_SHOT_INTERVAL - float(level - 1) * 0.003)
    _update_stars(delta)
    _update_grid(delta)
    _update_enemies(delta)
    _update_bullets(delta)
    _update_pickups(delta)
    _resolve_collisions()

    if not boss_active and kills >= next_boss_kill_target:
        _spawn_boss()
        next_boss_kill_target += BOSS_EVERY_KILLS
    elif not boss_active and spawn_timer <= 0.0:
        _spawn_enemy()
        var interval: float = maxf(0.38, BASE_ENEMY_INTERVAL - float(level - 1) * 0.065) * float(difficulty_profile["spawn_interval_scale"])
        spawn_timer = rng.randf_range(interval * 0.72, interval * 1.22)

    _update_ui()


func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey):
        return
    if not event.pressed or event.echo:
        return

    if settings_open:
        _handle_settings_key(event.keycode)
        return
    if event.keycode == KEY_O:
        _open_settings()
        return
    if event.keycode == KEY_F3:
        ui_pool.visible = not ui_pool.visible
        _pool_ui_timer = 0.0
        return

    match event.keycode:
        KEY_P, KEY_ESCAPE:
            if not is_game_over:
                is_paused = not is_paused
                ui_center.visible = is_paused
                ui_center.text = "暫停\nP / Esc 繼續"
        KEY_B:
            if not is_paused and not is_game_over:
                _use_bomb()
        KEY_R:
            if is_game_over:
                _restart_game()
        KEY_ENTER:
            if is_game_over:
                _restart_game()


func _handle_settings_key(keycode: int) -> void:
    match keycode:
        KEY_UP, KEY_W:
            settings_index = posmod(settings_index - 1, 5)
            _render_settings_ui()
        KEY_DOWN, KEY_S:
            settings_index = posmod(settings_index + 1, 5)
            _render_settings_ui()
        KEY_LEFT, KEY_A:
            _adjust_setting(-1)
        KEY_RIGHT, KEY_D:
            _adjust_setting(1)
        KEY_ENTER, KEY_ESCAPE, KEY_O:
            _close_settings()


func _open_settings() -> void:
    settings_open = true
    settings_index = 0
    is_paused = true
    settings_overlay.visible = true
    _render_settings_ui()


func _close_settings() -> void:
    var error: Error = settings_store.save_settings(settings_values)
    if error != OK:
        ui_settings.text += "\n\n儲存失敗（錯誤 %d），請重試。" % error
        return
    settings_values = settings_store.values.duplicate(true)
    _apply_settings()
    settings_open = false
    settings_overlay.visible = false
    if not is_game_over:
        is_paused = true
        ui_center.visible = true
        ui_center.text = "暫停\nP / Esc 繼續"


func _adjust_setting(direction: int) -> void:
    match settings_index:
        0:
            settings_values["master_volume"] = clampf(float(settings_values["master_volume"]) + float(direction) * 0.1, 0.0, 1.0)
        1:
            settings_values["sfx_volume"] = clampf(float(settings_values["sfx_volume"]) + float(direction) * 0.1, 0.0, 1.0)
        2:
            settings_values["display_mode"] = _cycle_setting(SETTINGS_STORE_SCRIPT.DISPLAY_MODES, str(settings_values["display_mode"]), direction)
        3:
            settings_values["resolution"] = _cycle_setting(SETTINGS_STORE_SCRIPT.RESOLUTIONS, str(settings_values["resolution"]), direction)
        4:
            settings_values["difficulty"] = _cycle_setting(SETTINGS_STORE_SCRIPT.DIFFICULTIES, str(settings_values["difficulty"]), direction)
    _apply_settings()
    _render_settings_ui()


func _cycle_setting(options: Array, current: String, direction: int) -> String:
    var index := options.find(current)
    if index < 0:
        index = 0
    return str(options[posmod(index + direction, options.size())])


func _render_settings_ui() -> void:
    var display_text := "全螢幕" if settings_values["display_mode"] == "fullscreen" else "視窗"
    var difficulty_text: String = str({
        "easy": "簡單",
        "normal": "標準",
        "hard": "困難",
    }.get(str(settings_values["difficulty"]), "標準"))
    var rows: Array[String] = [
        "主音量        %3d%%" % roundi(float(settings_values["master_volume"]) * 100.0),
        "音效音量      %3d%%" % roundi(float(settings_values["sfx_volume"]) * 100.0),
        "顯示模式      %s" % display_text,
        "解析度        %s" % settings_values["resolution"],
        "難度          %s" % difficulty_text,
    ]
    for index in range(rows.size()):
        rows[index] = ("> " if index == settings_index else "  ") + rows[index]
    ui_settings.text = "系統設定\n\n%s\n\n↑↓ / WS 選擇    ←→ / AD 調整\nEnter / Esc / O 儲存並返回" % "\n".join(rows)


func _load_settings() -> void:
    settings_store = SETTINGS_STORE_SCRIPT.new()
    settings_values = settings_store.load_settings()
    _apply_settings()


func _apply_settings() -> void:
    difficulty_profile = settings_store.get_difficulty_profile(str(settings_values["difficulty"]))
    var master_index := AudioServer.get_bus_index(&"Master")
    if master_index >= 0:
        var master_volume := float(settings_values["master_volume"])
        AudioServer.set_bus_mute(master_index, is_zero_approx(master_volume))
        AudioServer.set_bus_volume_db(master_index, linear_to_db(maxf(master_volume, 0.0001)))
    var sfx_index := AudioServer.get_bus_index(&"SFX")
    if sfx_index >= 0:
        var sfx_volume := float(settings_values["sfx_volume"])
        AudioServer.set_bus_mute(sfx_index, is_zero_approx(sfx_volume))
        AudioServer.set_bus_volume_db(sfx_index, linear_to_db(maxf(sfx_volume, 0.0001)))

    if DisplayServer.get_name() == "headless":
        return
    var window_size: Vector2i = settings_store.get_resolution_size(str(settings_values["resolution"]))
    if settings_values["display_mode"] == "fullscreen":
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
    else:
        DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
        DisplayServer.window_set_size(window_size)


func _load_audio() -> void:
    sfx_laser = load("res://assets/audio/laser.wav")
    sfx_explosion = load("res://assets/audio/explosion.wav")
    sfx_pickup = load("res://assets/audio/pickup.wav")
    sfx_hit = load("res://assets/audio/hit.wav")


func _create_materials() -> void:
    mat_player = _material(Color("1d7bc7"), Color("22d9ff"), 1.8)
    mat_player_accent = _material(Color("f3f8ff"), Color("26eaff"), 3.2)
    mat_enemy = _material(Color("8e163e"), Color("ff315f"), 1.5)
    mat_enemy_accent = _material(Color("ff8b1f"), Color("ff4b1a"), 2.5)
    mat_heavy = _material(Color("9f410d"), Color("ff9a22"), 2.0)
    mat_boss = _material(Color("561fa2"), Color("ec32ff"), 2.4)
    mat_boss_accent = _material(Color("202a8f"), Color("42bfff"), 4.0)
    mat_player_bullet = _material(Color("e9ffff"), Color("13dfff"), 5.0)
    mat_enemy_bullet = _material(Color("fff0f5"), Color("ff245e"), 5.0)
    mat_grid = _material(Color("03162b"), Color("075f82"), 0.7)
    mat_star_a = _material(Color("b9ebff"), Color("6bdcff"), 2.5)
    mat_star_b = _material(Color("ffaadf"), Color("ff4fc8"), 1.8)


func _material(albedo: Color, emission: Color = Color.BLACK, energy: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = albedo
    material.metallic = 0.62
    material.roughness = 0.24
    if energy > 0.0:
        material.emission_enabled = true
        material.emission = emission
        material.emission_energy_multiplier = energy
    return material


func _create_environment() -> void:
    var world_environment := WorldEnvironment.new()
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("010515")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("385d92")
    environment.ambient_light_energy = 0.65
    world_environment.environment = environment
    add_child(world_environment)

    camera = Camera3D.new()
    add_child(camera)
    camera.position = Vector3(0.0, 17.5, 13.0)
    camera.fov = 55.0
    camera.look_at(Vector3(0.0, 0.0, 0.5), Vector3.UP)

    var key_light := DirectionalLight3D.new()
    add_child(key_light)
    key_light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
    key_light.light_color = Color("b9ddff")
    key_light.light_energy = 1.45
    key_light.shadow_enabled = true

    var rim_light := DirectionalLight3D.new()
    add_child(rim_light)
    rim_light.rotation_degrees = Vector3(45.0, 155.0, 0.0)
    rim_light.light_color = Color("ff4acb")
    rim_light.light_energy = 0.55


func _create_arena() -> void:
    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(22.0, 26.0)
    floor_mesh.mesh = plane
    floor_mesh.position = Vector3(0.0, -1.25, -0.5)
    floor_mesh.material_override = _material(Color("010916"), Color("021b31"), 0.35)
    add_child(floor_mesh)

    for x in range(-10, 11, 2):
        var line_x := _box(Vector3(0.025, 0.018, 26.0), mat_grid)
        line_x.position = Vector3(float(x), -1.20, -0.5)
        add_child(line_x)

    for z in range(-12, 13, 2):
        var line_z := _box(Vector3(22.0, 0.018, 0.025), mat_grid)
        line_z.position = Vector3(0.0, -1.19, float(z))
        line_z.set_meta("speed", rng.randf_range(2.7, 4.2))
        moving_grid_lines.append(line_z)
        add_child(line_z)

    var star_mesh := SphereMesh.new()
    star_mesh.radius = 0.035
    star_mesh.height = 0.07
    star_mesh.radial_segments = 8
    star_mesh.rings = 4
    for i in range(110):
        var star := MeshInstance3D.new()
        star.mesh = star_mesh
        star.material_override = mat_star_a if i % 5 else mat_star_b
        star.position = Vector3(
            rng.randf_range(-11.0, 11.0),
            rng.randf_range(-0.7, 3.6),
            rng.randf_range(-13.0, 11.0)
        )
        star.scale = Vector3.ONE * rng.randf_range(0.45, 1.65)
        star.set_meta("speed", rng.randf_range(2.0, 8.0))
        stars.append(star)
        add_child(star)


func _create_player() -> void:
    player = CharacterBody3D.new()
    player.name = "Player"
    player.add_to_group("player")
    add_child(player)

    var body := _box(Vector3(0.78, 0.38, 1.85), mat_player)
    body.position = Vector3(0.0, 0.0, 0.0)
    player.add_child(body)

    var nose := _cylinder(0.0, 0.41, 1.15, mat_player_accent)
    nose.rotation_degrees.x = 90.0
    nose.position = Vector3(0.0, 0.0, -1.40)
    player.add_child(nose)

    var wing := _box(Vector3(2.55, 0.14, 0.82), mat_player)
    wing.position = Vector3(0.0, -0.04, 0.25)
    player.add_child(wing)

    var tail := _box(Vector3(0.18, 0.72, 0.75), mat_player_accent)
    tail.position = Vector3(0.0, 0.31, 0.68)
    player.add_child(tail)

    for x in [-0.52, 0.52]:
        var engine := _cylinder(0.14, 0.14, 0.72, mat_player_accent)
        engine.rotation_degrees.x = 90.0
        engine.position = Vector3(x, -0.05, 0.78)
        player.add_child(engine)

    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(2.3, 0.7, 2.7)
    collision.shape = shape
    player.add_child(collision)
    player_art = visual_factory.attach_player(player)


func _create_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 20
    add_child(canvas)

    var top_panel := ColorRect.new()
    top_panel.position = Vector2(18.0, 16.0)
    top_panel.size = Vector2(420.0, 152.0)
    top_panel.color = Color(0.01, 0.035, 0.09, 0.82)
    canvas.add_child(top_panel)

    ui_score = _label(Vector2(36.0, 25.0), 30, Color("e7fcff"))
    ui_hp = _label(Vector2(36.0, 67.0), 26, Color("ff6f8d"))
    ui_level = _label(Vector2(36.0, 105.0), 24, Color("ffd46d"))
    ui_bombs = _label(Vector2(242.0, 105.0), 24, Color("ff85d5"))
    canvas.add_child(ui_score)
    canvas.add_child(ui_hp)
    canvas.add_child(ui_level)
    canvas.add_child(ui_bombs)

    ui_status = _label(Vector2(1025.0, 24.0), 22, Color("81f5ff"))
    ui_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    ui_status.size = Vector2(220.0, 80.0)
    canvas.add_child(ui_status)

    ui_pool = _label(Vector2(930.0, 104.0), 15, Color("6daec1"))
    ui_pool.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    ui_pool.size = Vector2(315.0, 52.0)
    ui_pool.visible = false
    canvas.add_child(ui_pool)

    ui_center = _label(Vector2.ZERO, 50, Color("ecfbff"))
    ui_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ui_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ui_center.anchor_left = 0.5
    ui_center.anchor_right = 0.5
    ui_center.anchor_top = 0.5
    ui_center.anchor_bottom = 0.5
    ui_center.offset_left = -330.0
    ui_center.offset_right = 330.0
    ui_center.offset_top = -125.0
    ui_center.offset_bottom = 125.0
    ui_center.add_theme_constant_override("outline_size", 14)
    ui_center.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.08, 0.94))
    ui_center.visible = false
    canvas.add_child(ui_center)

    ui_controls = _label(Vector2.ZERO, 19, Color("bdefff"))
    ui_controls.text = "WASD / 方向鍵：移動    SPACE / 左鍵：射擊    B：全畫面炸彈    P / Esc：暫停    O：設定"
    ui_controls.anchor_left = 0.5
    ui_controls.anchor_right = 0.5
    ui_controls.anchor_top = 1.0
    ui_controls.anchor_bottom = 1.0
    ui_controls.offset_left = -440.0
    ui_controls.offset_right = 440.0
    ui_controls.offset_top = -52.0
    ui_controls.offset_bottom = -14.0
    ui_controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(ui_controls)

    settings_overlay = ColorRect.new()
    settings_overlay.anchor_right = 1.0
    settings_overlay.anchor_bottom = 1.0
    settings_overlay.color = Color(0.005, 0.018, 0.055, 0.96)
    settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
    settings_overlay.visible = false
    canvas.add_child(settings_overlay)

    ui_settings = _label(Vector2.ZERO, 26, Color("dffaff"))
    ui_settings.anchor_left = 0.5
    ui_settings.anchor_right = 0.5
    ui_settings.anchor_top = 0.5
    ui_settings.anchor_bottom = 0.5
    ui_settings.offset_left = -360.0
    ui_settings.offset_right = 360.0
    ui_settings.offset_top = -260.0
    ui_settings.offset_bottom = 260.0
    ui_settings.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    ui_settings.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    ui_settings.add_theme_constant_override("outline_size", 10)
    settings_overlay.add_child(ui_settings)


func _label(position_value: Vector2, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = position_value
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    label.add_theme_constant_override("outline_size", 6)
    label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.82))
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return label


func _update_player(delta: float) -> void:
    var move := Vector2.ZERO
    if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
        move.x -= 1.0
    if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
        move.x += 1.0
    if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
        move.y -= 1.0
    if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
        move.y += 1.0
    if move.length_squared() > 1.0:
        move = move.normalized()

    player.velocity = Vector3(move.x, 0.0, move.y) * PLAYER_SPEED
    player.move_and_slide()
    player.position.x = clamp(player.position.x, PLAYER_MIN_X, PLAYER_MAX_X)
    player.position.z = clamp(player.position.z, PLAYER_MIN_Z, PLAYER_MAX_Z)
    player.rotation_degrees.z = lerp(player.rotation_degrees.z, -move.x * 13.0, delta * 8.0)
    player_art.rotation_degrees.z = lerp(player_art.rotation_degrees.z, -move.x * 13.0, delta * 8.0)

    if invulnerability_timer > 0.0:
        player.visible = int(invulnerability_timer * 14.0) % 2 == 0
    else:
        player.visible = true

    var wants_fire := Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
    if wants_fire and shot_timer <= 0.0:
        _fire_player()
        shot_timer = max(0.055, PLAYER_SHOT_INTERVAL - float(level - 1) * 0.003)


func _update_stars(delta: float) -> void:
    for star in stars:
        star.position.z += float(star.get_meta("speed", 4.0)) * delta
        if star.position.z > 11.5:
            star.position.z = -13.0
            star.position.x = rng.randf_range(-11.0, 11.0)
            star.position.y = rng.randf_range(-0.7, 3.6)


func _update_grid(delta: float) -> void:
    for line in moving_grid_lines:
        line.position.z += float(line.get_meta("speed", 3.0)) * delta
        if line.position.z > 12.0:
            line.position.z = -12.0


func _prewarm_pools() -> void:
    for index in range(PLAYER_BULLET_POOL_SIZE):
        idle_player_bullets.append(_create_bullet_node(true))
    for index in range(ENEMY_BULLET_POOL_SIZE):
        idle_enemy_bullets.append(_create_bullet_node(false))
    for index in range(SCOUT_POOL_SIZE):
        idle_scouts.append(_create_enemy_node("scout"))
    for index in range(HEAVY_POOL_SIZE):
        idle_heavies.append(_create_enemy_node("heavy"))


func _create_bullet_node(friendly: bool) -> Node3D:
    var pool_kind := "player_bullet" if friendly else "enemy_bullet"
    var bullet := Node3D.new()
    bullet.name = "PooledPlayerBullet" if friendly else "PooledEnemyBullet"
    bullet.set_meta("pool_kind", pool_kind)
    bullet.set_meta("pooled_active", false)
    bullet.visible = false
    bullet.position = Vector3(0.0, -100.0, -100.0)
    add_child(bullet)

    var mesh := _box(
        Vector3(0.13 if friendly else 0.18, 0.13, 0.92 if friendly else 0.62),
        mat_player_bullet if friendly else mat_enemy_bullet
    )
    bullet.add_child(mesh)

    var light := OmniLight3D.new()
    light.light_color = Color("27ddff") if friendly else Color("ff285f")
    light.light_energy = 1.8
    light.omni_range = 2.5
    bullet.add_child(light)
    pool_created_counts[pool_kind] = int(pool_created_counts[pool_kind]) + 1
    return bullet


func _create_enemy_node(enemy_type: String) -> Node3D:
    var enemy := Node3D.new()
    enemy.name = "PooledEnemy_%s" % enemy_type
    enemy.set_meta("pool_kind", enemy_type)
    enemy.set_meta("pooled_active", false)
    enemy.visible = false
    enemy.position = Vector3(0.0, -100.0, -100.0)
    if enemy_type == "heavy":
        _build_heavy(enemy)
    else:
        _build_scout(enemy)
    add_child(enemy)
    pool_created_counts[enemy_type] = int(pool_created_counts[enemy_type]) + 1
    return enemy


func _fire_player() -> void:
    var spread := 0.0 if level < 3 else 0.42
    _spawn_bullet(player.position + Vector3(-0.36, 0.08, -1.45), true, -0.12)
    _spawn_bullet(player.position + Vector3(0.36, 0.08, -1.45), true, 0.12)
    if spread > 0.0:
        _spawn_bullet(player.position + Vector3(0.0, 0.12, -1.55), true, 0.0)
    if level >= 6:
        _spawn_bullet(player.position + Vector3(-0.78, 0.02, -0.75), true, -1.1)
        _spawn_bullet(player.position + Vector3(0.78, 0.02, -0.75), true, 1.1)
    _play_sfx(sfx_laser, -10.0)


func _spawn_bullet(position_value: Vector3, friendly: bool, velocity_x: float = 0.0) -> void:
    var bullet: Node3D
    var pool_kind := "player_bullet" if friendly else "enemy_bullet"
    if friendly:
        if idle_player_bullets.is_empty():
            pool_exhaustion_counts[pool_kind] = int(pool_exhaustion_counts[pool_kind]) + 1
            return
        else:
            bullet = idle_player_bullets.pop_back()
            pool_reuse_counts[pool_kind] = int(pool_reuse_counts[pool_kind]) + 1
    else:
        if idle_enemy_bullets.is_empty():
            pool_exhaustion_counts[pool_kind] = int(pool_exhaustion_counts[pool_kind]) + 1
            return
        else:
            bullet = idle_enemy_bullets.pop_back()
            pool_reuse_counts[pool_kind] = int(pool_reuse_counts[pool_kind]) + 1

    bullet.visible = true
    bullet.position = position_value
    bullet.rotation = Vector3.ZERO
    bullet.scale = Vector3.ONE
    bullet.set_meta("pooled_active", true)
    bullet.add_to_group("player_bullet" if friendly else "enemy_bullet")
    var bullet_speed := 18.5 if friendly else (6.2 + level * 0.25) * float(difficulty_profile["enemy_bullet_speed_scale"])
    bullet.set_meta("speed", bullet_speed)
    bullet.set_meta("velocity_x", velocity_x)
    bullet.set_meta("damage", 1)
    bullet.set_meta("radius", 0.48 if friendly else 0.42)


func _release_bullet(bullet: Node3D) -> void:
    if not is_instance_valid(bullet) or not bool(bullet.get_meta("pooled_active", false)):
        return
    var pool_kind := str(bullet.get_meta("pool_kind", ""))
    bullet.set_meta("pooled_active", false)
    bullet.remove_from_group("player_bullet")
    bullet.remove_from_group("enemy_bullet")
    bullet.visible = false
    bullet.position = Vector3(0.0, -100.0, -100.0)
    bullet.rotation = Vector3.ZERO
    bullet.scale = Vector3.ONE
    if pool_kind == "player_bullet":
        idle_player_bullets.append(bullet)
    else:
        idle_enemy_bullets.append(bullet)


func _update_bullets(delta: float) -> void:
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        if not is_instance_valid(bullet):
            continue
        bullet.position.x += float(bullet.get_meta("velocity_x", 0.0)) * delta
        bullet.position.z -= float(bullet.get_meta("speed", 18.0)) * delta
        if bullet.position.z < -13.5 or abs(bullet.position.x) > 13.0:
            _release_bullet(bullet)

    for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
        if not is_instance_valid(bullet):
            continue
        bullet.position.x += float(bullet.get_meta("velocity_x", 0.0)) * delta
        bullet.position.z += float(bullet.get_meta("speed", 6.0)) * delta
        if bullet.position.z > 11.5 or abs(bullet.position.x) > 13.0:
            _release_bullet(bullet)


func _spawn_enemy() -> void:
    var roll := rng.randf()
    var enemy_type := "scout"
    if level >= 3 and roll > 0.72:
        enemy_type = "heavy"

    var enemy: Node3D
    if enemy_type == "heavy":
        if idle_heavies.is_empty():
            pool_exhaustion_counts[enemy_type] = int(pool_exhaustion_counts[enemy_type]) + 1
            return
        else:
            enemy = idle_heavies.pop_back()
            pool_reuse_counts[enemy_type] = int(pool_reuse_counts[enemy_type]) + 1
    else:
        if idle_scouts.is_empty():
            pool_exhaustion_counts[enemy_type] = int(pool_exhaustion_counts[enemy_type]) + 1
            return
        else:
            enemy = idle_scouts.pop_back()
            pool_reuse_counts[enemy_type] = int(pool_reuse_counts[enemy_type]) + 1

    enemy.name = "Enemy_%s" % enemy_type
    enemy.visible = true
    enemy.rotation_degrees = Vector3(0.0, 180.0, 0.0)
    var art_sprite := enemy.get_node_or_null("ArtSprite") as Sprite3D
    if art_sprite:
        art_sprite.rotation_degrees.z = 0.0
    enemy.scale = Vector3.ONE
    enemy.set_meta("pooled_active", true)
    enemy.add_to_group("enemy")
    enemy.position = Vector3(rng.randf_range(-7.1, 7.1), 0.0, -11.2)
    enemy.set_meta("type", enemy_type)
    enemy.set_meta("phase", rng.randf_range(0.0, TAU))
    enemy.set_meta("wave", rng.randf_range(0.15, 0.65))
    enemy.set_meta("shoot_timer", rng.randf_range(0.7, 2.0))
    enemy.set_meta("is_boss", false)

    if enemy_type == "heavy":
        enemy.set_meta("hp", 4 + level / 2)
        enemy.set_meta("speed", 2.1 + level * 0.08)
        enemy.set_meta("score", 260)
        enemy.set_meta("radius", 1.15)
    else:
        enemy.set_meta("hp", 1 + level / 4)
        enemy.set_meta("speed", 3.4 + level * 0.12)
        enemy.set_meta("score", 100)
        enemy.set_meta("radius", 0.78)


func _release_enemy(enemy: Node3D) -> void:
    if not is_instance_valid(enemy) or not bool(enemy.get_meta("pooled_active", false)):
        return
    var pool_kind := str(enemy.get_meta("pool_kind", "scout"))
    enemy.set_meta("pooled_active", false)
    enemy.remove_from_group("enemy")
    enemy.visible = false
    enemy.position = Vector3(0.0, -100.0, -100.0)
    enemy.rotation_degrees = Vector3(0.0, 180.0, 0.0)
    var art_sprite := enemy.get_node_or_null("ArtSprite") as Sprite3D
    if art_sprite:
        art_sprite.rotation_degrees.z = 0.0
    enemy.scale = Vector3.ONE
    if pool_kind == "heavy":
        idle_heavies.append(enemy)
    else:
        idle_scouts.append(enemy)


func _build_scout(enemy: Node3D) -> void:
    var body := _box(Vector3(0.72, 0.34, 1.5), mat_enemy)
    enemy.add_child(body)
    var nose := _cylinder(0.0, 0.38, 0.85, mat_enemy_accent)
    nose.rotation_degrees.x = 90.0
    nose.position.z = 1.05
    enemy.add_child(nose)
    var wings := _box(Vector3(1.9, 0.12, 0.55), mat_enemy)
    wings.position.z = -0.05
    enemy.add_child(wings)
    enemy.rotation_degrees.y = 180.0
    visual_factory.attach_scout(enemy)


func _build_heavy(enemy: Node3D) -> void:
    var body := _box(Vector3(1.35, 0.62, 2.05), mat_heavy)
    enemy.add_child(body)
    var wings := _box(Vector3(3.1, 0.22, 0.86), mat_heavy)
    wings.position.z = -0.1
    enemy.add_child(wings)
    for x in [-1.08, 1.08]:
        var pod := _cylinder(0.23, 0.23, 1.25, mat_enemy_accent)
        pod.rotation_degrees.x = 90.0
        pod.position = Vector3(x, -0.04, 0.15)
        enemy.add_child(pod)
    enemy.rotation_degrees.y = 180.0
    visual_factory.attach_heavy(enemy)


func _spawn_boss() -> void:
    boss_active = true
    var boss := Node3D.new()
    boss.name = "BossCore"
    boss.add_to_group("enemy")
    boss.position = Vector3(0.0, 0.2, -12.0)
    boss.set_meta("type", "boss")
    boss.set_meta("hp", 52 + level * 7)
    boss.set_meta("max_hp", 52 + level * 7)
    boss.set_meta("speed", 1.25)
    boss.set_meta("score", 2500)
    boss.set_meta("radius", 2.25)
    boss.set_meta("phase", 0.0)
    boss.set_meta("wave", 0.0)
    boss.set_meta("shoot_timer", 0.7)
    boss.set_meta("is_boss", true)

    var core := _sphere(1.15, mat_boss_accent)
    boss.add_child(core)
    var shell := _box(Vector3(3.9, 0.7, 2.3), mat_boss)
    boss.add_child(shell)
    for x in [-2.25, 2.25]:
        var pod := _sphere(0.55, mat_enemy_accent)
        pod.position.x = x
        boss.add_child(pod)
        var arm := _box(Vector3(1.55, 0.26, 0.42), mat_boss)
        arm.position.x = x * 0.53
        boss.add_child(arm)
    boss.rotation_degrees.y = 180.0
    visual_factory.attach_boss(boss)
    add_child(boss)
    ui_status.text = "WARNING\nBOSS INBOUND"


func _update_enemies(delta: float) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy):
            continue
        var is_boss := bool(enemy.get_meta("is_boss", false))
        if is_boss:
            if enemy.position.z < -5.5:
                enemy.position.z += float(enemy.get_meta("speed", 1.2)) * delta
            else:
                enemy.position.x = sin(elapsed * 0.8) * 5.2
                enemy.rotation_degrees.z = sin(elapsed * 1.1) * 8.0
        else:
            enemy.position.z += float(enemy.get_meta("speed", 3.0)) * delta
            enemy.position.x += sin(elapsed * 2.0 + float(enemy.get_meta("phase", 0.0))) * float(enemy.get_meta("wave", 0.3)) * delta
            enemy.rotation_degrees.z = sin(elapsed * 2.0 + float(enemy.get_meta("phase", 0.0))) * 12.0

        var art_sprite := enemy.get_node_or_null("ArtSprite") as Sprite3D
        if art_sprite:
            art_sprite.rotation_degrees.z = enemy.rotation_degrees.z

        var enemy_shot_timer := float(enemy.get_meta("shoot_timer", 1.0)) - delta
        if enemy_shot_timer <= 0.0 and enemy.position.z > -9.5:
            _fire_enemy(enemy)
            var base_fire_interval := rng.randf_range(0.55, 1.05) if is_boss else rng.randf_range(1.25, 2.8)
            enemy_shot_timer = base_fire_interval * float(difficulty_profile["enemy_fire_interval_scale"])
        enemy.set_meta("shoot_timer", enemy_shot_timer)

        if enemy.position.z > 9.5:
            if is_boss:
                enemy.position.z = -5.5
            else:
                _damage_player(1)
                _release_enemy(enemy)


func _fire_enemy(enemy: Node3D) -> void:
    var is_boss := bool(enemy.get_meta("is_boss", false))
    if is_boss:
        for vx in [-3.4, -1.7, 0.0, 1.7, 3.4]:
            _spawn_bullet(enemy.position + Vector3(0.0, -0.05, 1.8), false, vx)
    elif str(enemy.get_meta("type", "scout")) == "heavy":
        _spawn_bullet(enemy.position + Vector3(-0.55, 0.0, 1.15), false, -0.35)
        _spawn_bullet(enemy.position + Vector3(0.55, 0.0, 1.15), false, 0.35)
    else:
        var direction_x: float = clampf((player.position.x - enemy.position.x) * 0.34, -1.4, 1.4)
        _spawn_bullet(enemy.position + Vector3(0.0, 0.0, 1.0), false, direction_x)


func _update_pickups(delta: float) -> void:
    for pickup in get_tree().get_nodes_in_group("pickup"):
        if not is_instance_valid(pickup):
            continue
        pickup.position.z += 3.0 * delta
        pickup.rotation_degrees.y += 120.0 * delta
        pickup.position.y = 0.25 + sin(elapsed * 4.0 + float(pickup.get_meta("phase", 0.0))) * 0.22
        if pickup.position.z > 11.0:
            pickup.queue_free()


func _resolve_collisions() -> void:
    var enemies := get_tree().get_nodes_in_group("enemy")
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
            continue
        for enemy in enemies:
            if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemy"):
                continue
            var hit_radius := float(bullet.get_meta("radius", 0.45)) + float(enemy.get_meta("radius", 0.8))
            if bullet.position.distance_squared_to(enemy.position) <= hit_radius * hit_radius:
                _damage_enemy(enemy, int(bullet.get_meta("damage", 1)))
                _release_bullet(bullet)
                break

    if invulnerability_timer <= 0.0:
        for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
            if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
                continue
            if bullet.position.distance_squared_to(player.position) <= 0.82 * 0.82:
                _release_bullet(bullet)
                _damage_player(1)
                break

        if is_game_over:
            return

        for enemy in enemies:
            if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemy"):
                continue
            var contact_radius := 0.7 + float(enemy.get_meta("radius", 0.8))
            if enemy.position.distance_squared_to(player.position) <= contact_radius * contact_radius:
                _damage_player(2 if bool(enemy.get_meta("is_boss", false)) else 1)
                if not bool(enemy.get_meta("is_boss", false)):
                    _release_enemy(enemy)
                break

        if is_game_over:
            return

    for pickup in get_tree().get_nodes_in_group("pickup"):
        if not is_instance_valid(pickup) or pickup.is_queued_for_deletion():
            continue
        if pickup.position.distance_squared_to(player.position) <= 1.05 * 1.05:
            _collect_pickup(pickup)
            pickup.queue_free()


func _damage_enemy(enemy: Node3D, amount: int) -> void:
    if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemy"):
        return
    var remaining_hp := int(enemy.get_meta("hp", 1)) - amount
    enemy.set_meta("hp", remaining_hp)
    if remaining_hp > 0:
        return

    var is_boss := bool(enemy.get_meta("is_boss", false))
    score += int(enemy.get_meta("score", 100))
    kills += 1 if not is_boss else 5
    level = 1 + score / 1300
    _spawn_explosion(enemy.position, Color("ff5a19") if not is_boss else Color("f23dff"), 2.3 if is_boss else 1.0)
    _play_sfx(sfx_explosion, -4.0 if is_boss else -8.0)

    if is_boss:
        boss_active = false
        bombs = min(5, bombs + 1)
        ui_status.text = "BOSS DOWN\nBONUS +2500"
        _spawn_pickup(enemy.position + Vector3(-1.0, 0.0, 0.0), "power")
        _spawn_pickup(enemy.position + Vector3(1.0, 0.0, 0.0), "health")
    elif rng.randf() < 0.17:
        var kinds := ["power", "health", "bomb"]
        _spawn_pickup(enemy.position, kinds[rng.randi_range(0, kinds.size() - 1)])
    if is_boss:
        enemy.queue_free()
    else:
        _release_enemy(enemy)


func _damage_player(amount: int) -> void:
    if _pool_stress_mode or invulnerability_timer > 0.0 or is_game_over:
        return
    hp -= amount
    invulnerability_timer = 1.15
    _spawn_explosion(player.position, Color("25dcff"), 0.7)
    _play_sfx(sfx_hit, -5.0)
    if hp <= 0:
        hp = 0
        _game_over()


func _spawn_pickup(position_value: Vector3, kind: String) -> void:
    var pickup := Node3D.new()
    pickup.name = "Pickup_%s" % kind
    pickup.add_to_group("pickup")
    pickup.position = position_value
    pickup.set_meta("kind", kind)
    pickup.set_meta("phase", rng.randf_range(0.0, TAU))
    add_child(pickup)

    var color := Color("39ddff")
    if kind == "health":
        color = Color("5dff8f")
    elif kind == "bomb":
        color = Color("ff55c8")
    var pickup_material := _material(color.darkened(0.55), color, 4.0)
    var orb := _sphere(0.42, pickup_material)
    pickup.add_child(orb)
    var cross_a := _box(Vector3(0.82, 0.12, 0.18), pickup_material)
    pickup.add_child(cross_a)
    if kind == "health":
        var cross_b := _box(Vector3(0.18, 0.12, 0.82), pickup_material)
        pickup.add_child(cross_b)
    visual_factory.attach_pickup(pickup, kind)


func _collect_pickup(pickup: Node3D) -> void:
    var kind := str(pickup.get_meta("kind", "power"))
    match kind:
        "health":
            hp = min(PLAYER_MAX_HP, hp + 2)
            score += 150
        "bomb":
            bombs = min(5, bombs + 1)
            score += 200
        _:
            score += 450
            level += 1
    _play_sfx(sfx_pickup, -4.0)
    _spawn_explosion(pickup.position, Color("57efff"), 0.55)


func _use_bomb() -> void:
    if bombs <= 0:
        return
    bombs -= 1
    for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
        if is_instance_valid(bullet):
            _release_bullet(bullet)
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
            continue
        _damage_enemy(enemy, 12 if bool(enemy.get_meta("is_boss", false)) else 999)
    _spawn_explosion(player.position + Vector3(0.0, 0.0, -1.0), Color("8ff7ff"), 4.0)


func _spawn_explosion(position_value: Vector3, color: Color, scale_factor: float = 1.0) -> void:
    var effect := Node3D.new()
    effect.name = "Explosion"
    effect.add_to_group("fx")
    effect.position = position_value
    add_child(effect)

    var effect_material := _material(color.darkened(0.25), color, 6.0)
    effect_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    var sphere := _sphere(0.22 * scale_factor, effect_material)
    effect.add_child(sphere)

    var light := OmniLight3D.new()
    light.light_color = color
    light.light_energy = 4.5 * scale_factor
    light.omni_range = 4.0 * scale_factor
    effect.add_child(light)

    var tween := create_tween()
    tween.set_parallel(true)
    tween.tween_property(sphere, "scale", Vector3.ONE * (3.4 * scale_factor), 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(effect_material, "albedo_color", Color(color.r, color.g, color.b, 0.0), 0.38)
    tween.tween_property(light, "light_energy", 0.0, 0.36)
    get_tree().create_timer(0.42).timeout.connect(effect.queue_free)


func _game_over() -> void:
    is_game_over = true
    player.visible = false
    ui_center.visible = true
    ui_center.text = "GAME OVER\n分數 %08d\nR / Enter 重新開始" % score
    ui_status.text = "MISSION FAILED"


func _restart_game() -> void:
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        _release_bullet(bullet)
    for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
        _release_bullet(bullet)
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy):
            continue
        if bool(enemy.get_meta("is_boss", false)):
            enemy.queue_free()
        else:
            _release_enemy(enemy)
    for group_name in ["pickup", "fx"]:
        for node in get_tree().get_nodes_in_group(group_name):
            if is_instance_valid(node):
                node.queue_free()

    score = 0
    level = 1
    hp = PLAYER_MAX_HP
    bombs = 2
    kills = 0
    next_boss_kill_target = BOSS_EVERY_KILLS
    boss_active = false
    is_paused = false
    is_game_over = false
    elapsed = 0.0
    spawn_timer = 0.35
    shot_timer = 0.0
    invulnerability_timer = 0.0
    _pool_ui_timer = 0.0
    player.position = Vector3(0.0, 0.0, 6.2)
    player.rotation = Vector3.ZERO
    player.visible = true
    ui_center.visible = false
    ui_status.text = "LOCAL 3D\nMISSION START"
    _update_ui()


func _update_ui() -> void:
    ui_score.text = "SCORE  %08d" % score
    ui_hp.text = "HP  " + "♥".repeat(hp) + "♡".repeat(PLAYER_MAX_HP - hp)
    ui_level.text = "LEVEL  %02d" % level
    ui_bombs.text = "BOMB × %d" % bombs
    if ui_pool.visible and _pool_ui_timer <= 0.0:
        var pool_stats := get_pool_stats()
        ui_pool.text = "POOL  PB %d/%d  EB %d/%d\nFOE  %d/%d" % [
            int(pool_stats["player_bullet"]["active"]),
            int(pool_stats["player_bullet"]["created"]),
            int(pool_stats["enemy_bullet"]["active"]),
            int(pool_stats["enemy_bullet"]["created"]),
            int(pool_stats["scout"]["active"]) + int(pool_stats["heavy"]["active"]),
            int(pool_stats["scout"]["created"]) + int(pool_stats["heavy"]["created"]),
        ]
        _pool_ui_timer = 0.5
    if boss_active:
        var bosses := get_tree().get_nodes_in_group("enemy")
        for enemy in bosses:
            if bool(enemy.get_meta("is_boss", false)):
                var current := int(enemy.get_meta("hp", 1))
                var maximum := int(enemy.get_meta("max_hp", 1))
                ui_status.text = "BOSS HP\n%d / %d" % [current, maximum]
                break
    elif not is_game_over:
        ui_status.text = "LOCAL 3D\nENEMIES %02d" % get_tree().get_nodes_in_group("enemy").size()


func enable_pool_stress_mode(seed_value: int = 1337) -> void:
    _pool_stress_mode = true
    rng.seed = seed_value
    level = 6
    hp = PLAYER_MAX_HP
    bombs = 5
    spawn_timer = 0.0
    shot_timer = 0.0


func disable_pool_stress_mode() -> void:
    _pool_stress_mode = false


func get_pool_stats() -> Dictionary:
    return {
        "player_bullet": {
            "active": get_tree().get_nodes_in_group("player_bullet").size(),
            "idle": idle_player_bullets.size(),
            "created": int(pool_created_counts["player_bullet"]),
            "reused": int(pool_reuse_counts["player_bullet"]),
            "exhausted": int(pool_exhaustion_counts["player_bullet"]),
        },
        "enemy_bullet": {
            "active": get_tree().get_nodes_in_group("enemy_bullet").size(),
            "idle": idle_enemy_bullets.size(),
            "created": int(pool_created_counts["enemy_bullet"]),
            "reused": int(pool_reuse_counts["enemy_bullet"]),
            "exhausted": int(pool_exhaustion_counts["enemy_bullet"]),
        },
        "scout": {
            "active": _count_active_enemy_kind("scout"),
            "idle": idle_scouts.size(),
            "created": int(pool_created_counts["scout"]),
            "reused": int(pool_reuse_counts["scout"]),
            "exhausted": int(pool_exhaustion_counts["scout"]),
        },
        "heavy": {
            "active": _count_active_enemy_kind("heavy"),
            "idle": idle_heavies.size(),
            "created": int(pool_created_counts["heavy"]),
            "reused": int(pool_reuse_counts["heavy"]),
            "exhausted": int(pool_exhaustion_counts["heavy"]),
        },
    }


func _count_active_enemy_kind(enemy_type: String) -> int:
    var count := 0
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not bool(enemy.get_meta("is_boss", false)) and str(enemy.get_meta("type", "")) == enemy_type:
            count += 1
    return count


func _play_sfx(stream: AudioStream, volume_db: float = -6.0) -> void:
    if stream == null or _is_shutting_down or DisplayServer.get_name() == "headless":
        return
    var audio := AudioStreamPlayer.new()
    audio.stream = stream
    audio.volume_db = volume_db
    if AudioServer.get_bus_index(&"SFX") >= 0:
        audio.bus = &"SFX"
    add_child(audio)
    active_sfx_players.append(audio)
    audio.finished.connect(_on_sfx_finished.bind(audio))
    audio.play()


func _on_sfx_finished(audio: AudioStreamPlayer) -> void:
    active_sfx_players.erase(audio)
    if is_instance_valid(audio):
        audio.queue_free()


func _box(size: Vector3, material: Material) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    instance.mesh = mesh
    instance.material_override = material
    return instance


func _sphere(radius: float, material: Material) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.radial_segments = 20
    mesh.rings = 10
    instance.mesh = mesh
    instance.material_override = material
    return instance


func _cylinder(top_radius: float, bottom_radius: float, height: float, material: Material) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    var mesh := CylinderMesh.new()
    mesh.top_radius = top_radius
    mesh.bottom_radius = bottom_radius
    mesh.height = height
    mesh.radial_segments = 20
    instance.mesh = mesh
    instance.material_override = material
    return instance

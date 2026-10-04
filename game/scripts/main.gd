extends Node3D

# Thunder Vector 3D
# A self-contained 3D vertical shooter for Godot 4.7.2.
# Original transparent art is layered over local primitive-mesh fallbacks.

const PLAYER_SPEED := 10.0
const PLAYER_MAX_HP := 5
const PLAYER_MIN_X := -10.2
const PLAYER_MAX_X := 10.2
const PLAYER_MIN_Z := 0.5
const PLAYER_MAX_Z := 10.2
const ENEMY_EXIT_Z := 12.5
const PLAYER_SHOT_INTERVAL := 0.13
const BASE_ENEMY_INTERVAL := 1.05
const BOSS_EVERY_KILLS := 20
const PLAYER_BULLET_POOL_SIZE := 1024
const ENEMY_BULLET_POOL_SIZE := 128
const SCOUT_POOL_SIZE := 64
const HEAVY_POOL_SIZE := 16
const SHIELD_DURATION := 12.0
const OVERDRIVE_DURATION := 6.0
const ARSENAL_SCRIPT := preload("res://scripts/arsenal.gd")
const ARCADE_FEEDBACK_SCRIPT := preload("res://scripts/arcade_feedback.gd")
const SECTOR_SCENERY_SCRIPT := preload("res://scripts/sector_scenery.gd")
const SECTOR_ROUTE_SCRIPT := preload("res://scripts/sector_route.gd")
const SPECIAL_WEAPONS_SCRIPT := preload("res://scripts/weapon_system.gd")
const DEVICE_CONTROLS_SCRIPT := preload("res://scripts/device_controls.gd")
const MISSION_DIRECTOR_SCRIPT := preload("res://scripts/mission_director.gd")
const WORLD_EVENTS_SCRIPT := preload("res://scripts/world_events.gd")
const MISSION_PRESENTATION_SCRIPT := preload("res://scripts/mission_presentation.gd")
const PLANET_TEXTURE: Texture2D = preload("res://assets/generated/orbital_planet_imagegen_v1.png")
const SETTINGS_STORE_SCRIPT := preload("res://scripts/settings_store.gd")
const VISUAL_FACTORY_SCRIPT := preload("res://scripts/visual_factory.gd")
const TRANSIENT_EFFECTS_SCRIPT := preload("res://scripts/transient_effects.gd")
const ENCOUNTER_DIRECTOR_SCRIPT := preload("res://scripts/encounter_director.gd")
const NEBULA_TEXTURE: Texture2D = preload("res://assets/generated/sector_nebula_imagegen_v1.png")

var rng := RandomNumberGenerator.new()
var player: CharacterBody3D
var player_art: Sprite3D
var camera: Camera3D
var stars: Array = []
var moving_grid_lines: Array = []
var map_scenery: Node3D
var map_planet: Sprite3D
var map_route: Control
var ui_route: Label
var special_weapons: Node3D
var weapon_mode := 1
var ui_weapon: Label
var _enemy_activation_serial := 0
var device_controls: CanvasLayer
var _web_window: Variant
var _web_action_callback: Variant
var _web_move_callback: Variant
var _web_move := Vector2.ZERO
var _web_fire := false
var _web_state_timer := 0.0
var _device_hud_panels: Array[Control] = []
var mission_director: RefCounted
var world_events: Node3D
var mission_presentation: Control
var ui_mission: Label
var _mission_ui_key := ""
var _event_warning := ""
var _mission_last_reward_serial := -1
var _beacon_timer := 12.0
var _compact_mission := false
var _mission_damage_pending := false

var score := 0
var level := 1
var hp := PLAYER_MAX_HP
var bombs := 2
var kills := 0
var next_boss_kill_target := BOSS_EVERY_KILLS
var boss_active := false
var bosses_defeated := 0
var sector_index := 0
var encounter_director: RefCounted
var pending_encounter: Dictionary = {}
var wave_number := 0
var wave_name := "準備出擊"
var _last_encounter_interval_scale := 1.0
var sector_environment: Environment
var is_paused := false
var is_game_over := false
var elapsed := 0.0
var spawn_timer := 0.2
var shot_timer := 0.0
var invulnerability_timer := 0.0
var shield_timer := 0.0
var shield_intro_dropped := false
var shield_ring: MeshInstance3D
var arsenal: RefCounted
var weapon_rank := 1
var wingmen: Array[Node3D] = []
var overdrive_charge := 100.0
var overdrive_timer := 0.0
var last_volley_size := 0
var volley_count := 0
var combo := 0
var combo_timer := 0.0
var best_combo := 0
var arcade_kills := 0
var swarm_timer := 1.2
var _hit_feedback_timer := 0.0
var ui_arsenal: Label
var ui_overdrive: Label
var ui_combo: Label
var overdrive_bar: ProgressBar
var _hud_arcade_key := ""
var arcade_feedback: Node3D
var motion_enabled := true
var player_bullet_batch: MultiMeshInstance3D
var _bullet_batch_dirty := true

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
var ui_sector: Label
var ui_shield: Label
var _hud_shield_seconds := -1
var _hud_score := -1
var _hud_hp := -1
var _hud_level := -1
var _hud_bombs := -1
var _hud_status_mode := ""
var _hud_enemy_count := -1
var _hud_boss_hp := -1
var _hud_boss_max_hp := -1
var _active_boss: Node3D

var sfx_laser: AudioStream
var sfx_explosion: AudioStream
var sfx_pickup: AudioStream
var sfx_hit: AudioStream
var transient_effects: Node
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
var player_bullet_mesh: BoxMesh
var enemy_bullet_mesh: BoxMesh
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
    # Web has no operating-system CJK fallback. Apply our offline OFL font only
    # at runtime, after importing assets (project-level font breaks a fresh import).
    var ui_font := FontVariation.new()
    ui_font.base_font = load("res://assets/fonts/NotoSansTC-Variable.ttf")
    ui_font.variation_opentype = {"wght": 600.0}
    ThemeDB.get_default_theme().set_font("font", "Label", ui_font)
    rng.randomize()
    _load_audio()
    _load_settings()
    _create_materials()
    transient_effects = TRANSIENT_EFFECTS_SCRIPT.new()
    add_child(transient_effects)
    visual_factory = VISUAL_FACTORY_SCRIPT.new()
    encounter_director = ENCOUNTER_DIRECTOR_SCRIPT.new()
    arsenal = ARSENAL_SCRIPT.new()
    mission_director = MISSION_DIRECTOR_SCRIPT.new()
    _prewarm_pools()
    _create_environment()
    arcade_feedback = ARCADE_FEEDBACK_SCRIPT.new()
    add_child(arcade_feedback)
    arcade_feedback.setup(camera)
    _create_arena()
    world_events = WORLD_EVENTS_SCRIPT.new()
    world_events.name = "TacticalWorldEvents"
    add_child(world_events)
    world_events.setup()
    _create_player()
    _create_wingmen()
    special_weapons = SPECIAL_WEAPONS_SCRIPT.new()
    special_weapons.name = "SpecialWeapons"
    add_child(special_weapons)
    special_weapons.setup(self)
    _create_ui()
    _setup_device_controls()
    _restart_game()


func _exit_tree() -> void:
    prepare_for_shutdown()


func prepare_for_shutdown() -> void:
    if _is_shutting_down:
        return
    _is_shutting_down = true
    _release_device_inputs()
    if _web_window != null:
        _web_window.thunderDeviceAction = null
        _web_window.thunderDeviceMove = null
        _web_window = null
    if is_instance_valid(transient_effects):
        transient_effects.shutdown()
    if is_instance_valid(arcade_feedback):
        arcade_feedback.clear()
    if is_instance_valid(special_weapons):
        special_weapons.clear()
    if is_instance_valid(world_events):
        world_events.clear()
    if is_instance_valid(mission_presentation):
        mission_presentation.clear()
    sfx_laser = null
    sfx_explosion = null
    sfx_pickup = null
    sfx_hit = null


func _process(delta: float) -> void:
    # Like the original idle Tweens/Timers, cosmetics finish while gameplay is paused.
    if not _is_shutting_down:
        transient_effects.advance(delta)
        arcade_feedback.advance(delta)
        _sync_player_bullet_batch()
        if _web_window != null:
            _web_state_timer -= delta
            if _web_state_timer <= 0.0:
                _web_state_timer = 0.25
                _publish_web_state()


func _setup_device_controls() -> void:
    device_controls = DEVICE_CONTROLS_SCRIPT.new()
    add_child(device_controls)
    device_controls.setup(self)
    if OS.has_feature("web"):
        _web_window = JavaScriptBridge.get_interface("window")
        _web_action_callback = JavaScriptBridge.create_callback(_on_web_action)
        _web_move_callback = JavaScriptBridge.create_callback(_on_web_move)
        _web_window.thunderDeviceAction = _web_action_callback
        _web_window.thunderDeviceMove = _web_move_callback
        if bool(_web_window.thunderDeviceControls):
            device_controls.set_enabled(false)
        get_viewport().scaling_3d_scale = 0.75
    var compact: bool = device_controls.is_enabled() or (_web_window != null and bool(_web_window.thunderDeviceTouch))
    if compact:
        _compact_mission = true
        ui_mission.position = Vector2(455.0, 24.0)
        ui_mission.size = Vector2(485.0, 115.0)
        ui_mission.add_theme_font_size_override("font_size", 25)
        ui_mission.visible = _web_window == null
        for panel in _device_hud_panels:
            panel.visible = false
        for label in [ui_level, ui_arsenal, ui_overdrive, ui_combo, ui_weapon, ui_shield, ui_sector]:
            label.visible = false
        map_route.visible = false
        overdrive_bar.visible = false
        ui_controls.visible = false
        ui_score.position = Vector2(22.0, 12.0)
        ui_score.add_theme_font_size_override("font_size", 40)
        ui_hp.position = Vector2(22.0, 64.0)
        ui_hp.add_theme_font_size_override("font_size", 36)
        ui_bombs.position = Vector2(22.0, 109.0)
        ui_bombs.add_theme_font_size_override("font_size", 30)
    _publish_web_state()


func _on_web_action(args: Array) -> void:
    if args.is_empty() or typeof(args[0]) != TYPE_STRING:
        return
    var pressed := true
    if args.size() > 1:
        if typeof(args[1]) != TYPE_BOOL:
            return
        pressed = args[1]
    _device_action(str(args[0]), pressed)
    # Immediate snapshots also cover action helpers that return early. On slow
    # Web frames, the DOM must not wait for the next 0.25-second idle update.
    _publish_web_state()


func _on_web_move(args: Array) -> void:
    if args.size() < 2 or typeof(args[0]) not in [TYPE_FLOAT, TYPE_INT] or typeof(args[1]) not in [TYPE_FLOAT, TYPE_INT]:
        return
    var value := Vector2(float(args[0]), float(args[1]))
    if not value.is_finite():
        return
    _web_move = value.limit_length(1.0) if not is_paused and not is_game_over and not settings_open else Vector2.ZERO


func _release_device_inputs() -> void:
    _web_move = Vector2.ZERO
    _web_fire = false
    if is_instance_valid(device_controls):
        device_controls.release_inputs()


func _publish_web_state() -> void:
    if _web_window != null:
        var mission: Dictionary = mission_director.get_state()
        _web_window.thunderStateJson = JSON.stringify({"hp": hp, "score": score, "weapon_mode": weapon_mode, "overdrive_charge": overdrive_charge, "overdrive_seconds": overdrive_timer, "paused": is_paused, "dead": is_game_over, "settings": settings_open, "sector": sector_index, "mission_title": mission["title"], "mission_progress": mission["progress"], "mission_target": mission["target"], "mission_seconds": ceili(float(mission["remaining"])), "mission_phase": mission["phase"], "event_warning": _event_warning})


func _device_action(action: String, pressed: bool = true) -> bool:
    if _is_shutting_down:
        return false
    if action == "fire":
        _web_fire = pressed and not is_paused and not is_game_over and not settings_open
        return true
    if not pressed:
        return false
    if action == "focus_lost":
        _release_device_inputs()
        if not is_game_over and not settings_open:
            _set_device_pause(true)
        return true
    if settings_open:
        var settings_keys := {"settings_prev": KEY_UP, "up": KEY_UP, "settings_next": KEY_DOWN, "down": KEY_DOWN, "settings_decrease": KEY_LEFT, "left": KEY_LEFT, "settings_increase": KEY_RIGHT, "right": KEY_RIGHT, "settings_close": KEY_ENTER, "confirm": KEY_ENTER, "settings": KEY_O}
        if action not in settings_keys:
            return false
        _handle_settings_key(int(settings_keys[action]))
        return true
    match action:
        "settings":
            _release_device_inputs()
            _open_settings()
        "pause":
            if is_game_over:
                return false
            _set_device_pause(not is_paused)
        "restart":
            if not is_game_over:
                return false
            _restart_game()
        "bomb":
            if is_paused or is_game_over:
                return false
            _use_bomb()
        "overdrive":
            return _start_overdrive()
        "weapon_next", "weapon_cycle":
            return _set_weapon_mode(weapon_mode % 4 + 1)
        _:
            return false
    _publish_web_state()
    return true


func _set_device_pause(paused: bool) -> void:
    _release_device_inputs()
    is_paused = paused
    ui_center.visible = paused
    ui_center.text = "暫停\nP / Esc / 暫停鈕 繼續"
    _publish_web_state()


func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(ui_center) and not _is_shutting_down:
        _device_action("focus_lost")


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventJoypadButton or not event.pressed:
        return
    if settings_open:
        var navigation := {JOY_BUTTON_DPAD_UP: "up", JOY_BUTTON_DPAD_DOWN: "down", JOY_BUTTON_DPAD_LEFT: "left", JOY_BUTTON_DPAD_RIGHT: "right", JOY_BUTTON_A: "confirm", JOY_BUTTON_BACK: "settings"}
        if event.button_index in navigation:
            _device_action(navigation[event.button_index])
        return
    var actions := {JOY_BUTTON_B: "bomb", JOY_BUTTON_X: "weapon_cycle", JOY_BUTTON_Y: "overdrive", JOY_BUTTON_START: "pause", JOY_BUTTON_BACK: "settings"}
    if is_game_over and event.button_index == JOY_BUTTON_A:
        _device_action("restart")
    elif event.button_index in actions:
        _device_action(actions[event.button_index])


func _physics_process(delta: float) -> void:
    if is_paused or is_game_over:
        return

    elapsed += delta
    shot_timer -= delta
    spawn_timer -= delta
    invulnerability_timer = max(0.0, invulnerability_timer - delta)
    _update_shield(delta)
    _update_arcade(delta)
    _pool_ui_timer -= delta

    _update_player(delta)
    _update_wingmen(delta)
    if _pool_stress_mode and shot_timer <= 0.0:
        var fired := _fire_player()
        shot_timer = _shot_interval() if fired > 0 else 0.05
    map_scenery.advance(delta)
    _update_enemies(delta)
    if is_game_over:
        return
    _update_bullets(delta)
    special_weapons.advance(delta)
    _update_pickups(delta)
    _resolve_collisions()
    if is_game_over:
        return
    _update_missions(delta)
    if is_game_over:
        return

    if not boss_active and swarm_timer <= 0.0:
        swarm_timer = (1.5 if overdrive_timer > 0.0 else 3.0) if _spawn_fodder_squad() > 0 else 0.25
    if not boss_active and kills >= next_boss_kill_target:
        _spawn_boss()
        next_boss_kill_target += BOSS_EVERY_KILLS
    elif not boss_active and spawn_timer <= 0.0:
        var spawned := _spawn_encounter()
        if spawned > 0:
            var interval: float = maxf(0.38, BASE_ENEMY_INTERVAL - float(level - 1) * 0.065) * float(difficulty_profile["spawn_interval_scale"])
            spawn_timer = rng.randf_range(interval * 0.72, interval * 1.22) * _last_encounter_interval_scale
        else:
            spawn_timer = 0.25

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
                _set_device_pause(not is_paused)
        KEY_B:
            if not is_paused and not is_game_over:
                _use_bomb()
        KEY_E:
            _start_overdrive()
        KEY_1, KEY_2, KEY_3, KEY_4:
            _set_weapon_mode(int(event.keycode - KEY_1) + 1)
        KEY_M:
            motion_enabled = not motion_enabled
            arcade_feedback.set_motion_enabled(motion_enabled)
            _refresh_controls()
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
    _release_device_inputs()
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
    if (OS.has_feature("web") or OS.has_feature("mobile")) and settings_index in [2, 3]:
        return
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
    if OS.has_feature("web") or OS.has_feature("mobile"):
        rows[2] = "顯示模式      裝置全螢幕按鈕"
        rows[3] = "解析度        自動適配畫面"
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

    if DisplayServer.get_name() == "headless" or OS.has_feature("web") or OS.has_feature("mobile"):
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
    sector_environment = environment
    var sky_material := PanoramaSkyMaterial.new()
    sky_material.panorama = NEBULA_TEXTURE
    var sky := Sky.new()
    sky.radiance_size = Sky.RADIANCE_SIZE_64
    sky.sky_material = sky_material
    environment.sky = sky
    environment.background_mode = Environment.BG_SKY
    environment.background_energy_multiplier = 0.45
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("385d92")
    environment.ambient_light_energy = 0.65
    world_environment.environment = environment
    add_child(world_environment)

    camera = Camera3D.new()
    add_child(camera)
    camera.position = Vector3(0.0, 21.5, 16.0)
    camera.fov = 55.0
    camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)

    var key_light := DirectionalLight3D.new()
    add_child(key_light)
    key_light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
    key_light.light_color = Color("b9ddff")
    key_light.light_energy = 1.45
    key_light.shadow_enabled = not OS.has_feature("web") and not OS.has_feature("mobile")

    var rim_light := DirectionalLight3D.new()
    add_child(rim_light)
    rim_light.rotation_degrees = Vector3(45.0, 155.0, 0.0)
    rim_light.light_color = Color("ff4acb")
    rim_light.light_energy = 0.55


func _create_arena() -> void:
    map_scenery = SECTOR_SCENERY_SCRIPT.new()
    map_scenery.name = "SectorScenery"
    add_child(map_scenery)
    # A distant, non-colliding landmark, behind the flight corridor.
    map_planet = Sprite3D.new()
    map_planet.name = "OrbitalPlanet"
    map_planet.texture = PLANET_TEXTURE
    map_planet.pixel_size = 0.017
    map_planet.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    map_planet.no_depth_test = false
    map_planet.shaded = false
    map_planet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    map_planet.position = Vector3(23.0, -11.0, -26.0)
    map_planet.modulate = Color(0.34, 0.39, 0.45, 1.0)
    add_child(map_planet)


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

    shield_ring = MeshInstance3D.new()
    shield_ring.name = "ShieldRing"
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 1.65
    ring_mesh.outer_radius = 1.74
    ring_mesh.rings = 48
    ring_mesh.ring_segments = 6
    shield_ring.mesh = ring_mesh
    var ring_material := _material(Color(0.2, 0.9, 1.0, 0.65), Color("58edff"), 2.0)
    ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    shield_ring.material_override = ring_material
    shield_ring.position.y = 0.3
    shield_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    shield_ring.visible = false
    player.add_child(shield_ring)


func _create_ui() -> void:
    var canvas := CanvasLayer.new()
    canvas.layer = 20
    add_child(canvas)

    var top_panel := ColorRect.new()
    top_panel.position = Vector2(18.0, 16.0)
    top_panel.size = Vector2(420.0, 152.0)
    top_panel.color = Color(0.01, 0.035, 0.09, 0.82)
    canvas.add_child(top_panel)
    _device_hud_panels.append(top_panel)

    ui_score = _label(Vector2(36.0, 25.0), 30, Color("e7fcff"))
    ui_hp = _label(Vector2(36.0, 67.0), 26, Color("ff6f8d"))
    ui_level = _label(Vector2(36.0, 105.0), 24, Color("ffd46d"))
    ui_bombs = _label(Vector2(242.0, 105.0), 24, Color("ff85d5"))
    canvas.add_child(ui_score)
    canvas.add_child(ui_hp)
    canvas.add_child(ui_level)
    canvas.add_child(ui_bombs)

    ui_sector = _label(Vector2(460.0, 23.0), 18, Color("81f5ff"))
    ui_sector.size = Vector2(370.0, 68.0)
    ui_sector.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    canvas.add_child(ui_sector)
    var mission_panel := ColorRect.new()
    mission_panel.position = Vector2(455.0, 99.0)
    mission_panel.size = Vector2(375.0, 98.0)
    mission_panel.color = Color(0.005, 0.028, 0.06, 0.86)
    mission_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(mission_panel)
    _device_hud_panels.append(mission_panel)
    ui_mission = _label(Vector2(467.0, 106.0), 17, Color("c3f7eb"))
    ui_mission.size = Vector2(351.0, 87.0)
    canvas.add_child(ui_mission)
    mission_presentation = MISSION_PRESENTATION_SCRIPT.new()
    canvas.add_child(mission_presentation)
    map_route = SECTOR_ROUTE_SCRIPT.new()
    map_route.position = Vector2(22.0, 359.0)
    canvas.add_child(map_route)
    ui_route = map_route.status_label

    ui_shield = _label(Vector2(36.0, 143.0), 15, Color("8aefff"))
    canvas.add_child(ui_shield)
    var arsenal_panel := ColorRect.new()
    arsenal_panel.position = Vector2(22.0, 194.0)
    arsenal_panel.size = Vector2(237.0, 144.0)
    arsenal_panel.color = Color(0.015, 0.03, 0.06, 0.88)
    arsenal_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(arsenal_panel)
    _device_hud_panels.append(arsenal_panel)
    ui_arsenal = _label(Vector2(36.0, 204.0), 18, Color("d6f5ff"))
    canvas.add_child(ui_arsenal)
    ui_overdrive = _label(Vector2(36.0, 267.0), 17, Color("ffe3a4"))
    canvas.add_child(ui_overdrive)
    overdrive_bar = ProgressBar.new()
    overdrive_bar.position = Vector2(36.0, 313.0)
    overdrive_bar.size = Vector2(207.0, 8.0)
    overdrive_bar.show_percentage = false
    overdrive_bar.add_theme_font_size_override("font_size", 1)
    overdrive_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var fill := StyleBoxFlat.new()
    fill.bg_color = Color("ffc763")
    fill.corner_radius_top_left = 4
    fill.corner_radius_top_right = 4
    fill.corner_radius_bottom_left = 4
    fill.corner_radius_bottom_right = 4
    fill.content_margin_left = 0.0
    fill.content_margin_right = 0.0
    fill.content_margin_top = 0.0
    fill.content_margin_bottom = 0.0
    overdrive_bar.add_theme_stylebox_override("fill", fill)
    var bar_background := StyleBoxFlat.new()
    bar_background.bg_color = Color("243c52")
    bar_background.content_margin_left = 0.0
    bar_background.content_margin_right = 0.0
    bar_background.content_margin_top = 0.0
    bar_background.content_margin_bottom = 0.0
    overdrive_bar.add_theme_stylebox_override("background", bar_background)
    overdrive_bar.size = Vector2(207.0, 8.0)
    canvas.add_child(overdrive_bar)
    ui_combo = _label(Vector2(995.0, 192.0), 23, Color("ffd789"))
    ui_combo.size = Vector2(250.0, 100.0)
    ui_combo.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    canvas.add_child(ui_combo)
    var weapon_panel := ColorRect.new()
    weapon_panel.position = Vector2(995.0, 335.0)
    weapon_panel.size = Vector2(252.0, 176.0)
    weapon_panel.color = Color(0.008, 0.023, 0.045, 0.88)
    weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    canvas.add_child(weapon_panel)
    _device_hud_panels.append(weapon_panel)
    ui_weapon = _label(Vector2(1009.0, 348.0), 16, Color("a6ebf5"))
    canvas.add_child(ui_weapon)

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

    ui_controls = _label(Vector2.ZERO, 16, Color("bdefff"))
    _refresh_controls()
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


func _refresh_controls() -> void:
    ui_controls.text = "WASD / 方向鍵 移動   SPACE / 左鍵 射擊   E 百發超載   B 炸彈   P / Esc 暫停   O 設定   M 微震%s" % ("開" if motion_enabled else "關")


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
    var joypads := Input.get_connected_joypads()
    if not joypads.is_empty():
        var joy := Vector2(Input.get_joy_axis(joypads[0], JOY_AXIS_LEFT_X), Input.get_joy_axis(joypads[0], JOY_AXIS_LEFT_Y))
        if joy.length() > 0.18:
            move += joy.limit_length(1.0)
        move.x += float(Input.is_joy_button_pressed(joypads[0], JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(joypads[0], JOY_BUTTON_DPAD_LEFT))
        move.y += float(Input.is_joy_button_pressed(joypads[0], JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(joypads[0], JOY_BUTTON_DPAD_UP))
    if is_instance_valid(device_controls):
        move += device_controls.get_move_vector()
    move += _web_move
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

    var joy_fire := not joypads.is_empty() and (Input.is_joy_button_pressed(joypads[0], JOY_BUTTON_A) or Input.get_joy_axis(joypads[0], JOY_AXIS_TRIGGER_RIGHT) > 0.25)
    var wants_fire: bool = Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or joy_fire or _web_fire or (is_instance_valid(device_controls) and device_controls.wants_fire()) or overdrive_timer > 0.0
    if wants_fire and shot_timer <= 0.0:
        var fired := _fire_player()
        shot_timer = _shot_interval() if fired > 0 else 0.05


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
    # Immutable shared geometry; per-instance transforms/materials stay independent.
    player_bullet_mesh = BoxMesh.new()
    player_bullet_mesh.size = Vector3(0.13, 0.13, 0.92)
    enemy_bullet_mesh = BoxMesh.new()
    enemy_bullet_mesh.size = Vector3(0.18, 0.13, 0.62)
    player_bullet_batch = MultiMeshInstance3D.new()
    player_bullet_batch.name = "FriendlyBulletBatch"
    player_bullet_batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var batch := MultiMesh.new()
    batch.transform_format = MultiMesh.TRANSFORM_3D
    batch.use_colors = true
    batch.mesh = player_bullet_mesh
    batch.instance_count = PLAYER_BULLET_POOL_SIZE
    batch.visible_instance_count = 0
    player_bullet_batch.multimesh = batch
    var batch_material := StandardMaterial3D.new()
    batch_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    batch_material.vertex_color_use_as_albedo = true
    player_bullet_batch.material_override = batch_material
    player_bullet_batch.custom_aabb = AABB(Vector3(-20.0, -2.0, -22.0), Vector3(40.0, 8.0, 40.0))
    add_child(player_bullet_batch)
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

    var mesh := MeshInstance3D.new()
    mesh.mesh = player_bullet_mesh if friendly else enemy_bullet_mesh
    mesh.material_override = mat_player_bullet if friendly else mat_enemy_bullet
    mesh.visible = not friendly
    mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    bullet.add_child(mesh)

    if not friendly:
        var light := OmniLight3D.new()
        light.light_color = Color("ff285f")
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


func _fire_player() -> int:
    if is_paused or is_game_over:
        return 0
    if weapon_mode != 1 and overdrive_timer <= 0.0:
        return _fire_special_weapon()
    var shots: Array = arsenal.get_shots(weapon_rank, overdrive_timer > 0.0)
    if idle_player_bullets.size() < shots.size():
        return 0 # Atomic retry; no half-volley or pool-exhaustion counter inflation.
    _update_wingmen(0.0)
    for shot in shots:
        var emitter := int(shot["emitter"])
        var origin: Vector3 = player.position if emitter < 0 else wingmen[emitter].position
        var bullet := _spawn_bullet(origin + shot["offset"], true, float(shot["velocity_x"]), float(shot["speed"]))
        bullet.set_meta("emitter", emitter)
        bullet.set_meta("overdrive", overdrive_timer > 0.0)
    last_volley_size = shots.size()
    volley_count += 1
    _sync_player_bullet_batch()
    _play_sfx(sfx_laser, -15.0 if overdrive_timer > 0.0 else -13.0)
    return last_volley_size


func _shot_interval() -> float:
    if weapon_mode == 1 or overdrive_timer > 0.0:
        return float(arsenal.get_profile(weapon_rank, overdrive_timer > 0.0)["interval"])
    return float(special_weapons.get_profile(weapon_mode, weapon_rank)["interval"])


func _set_weapon_mode(mode: int) -> bool:
    if is_paused or is_game_over or mode < 1 or mode > 4 or weapon_mode == mode:
        return false
    weapon_mode = mode
    # Switching cannot reset the shared cooldown or grant a free attack.
    _hud_arcade_key = ""
    _update_ui()
    return true


func _fire_special_weapon() -> int:
    var attack_profile: Dictionary = special_weapons.get_profile(weapon_mode, weapon_rank)
    var shots: Array = arsenal.get_shots(weapon_rank, false)
    var wing_shots: Array = []
    for shot in shots:
        if int(shot["emitter"]) >= 0:
            wing_shots.append(shot)
    if idle_player_bullets.size() < wing_shots.size():
        return 0
    if not special_weapons.fire(weapon_mode, player.position, weapon_rank):
        return 0
    _update_wingmen(0.0)
    for shot in wing_shots:
        var emitter := int(shot["emitter"])
        var bullet := _spawn_bullet(wingmen[emitter].position + shot["offset"], true, float(shot["velocity_x"]), float(shot["speed"]))
        bullet.set_meta("emitter", emitter)
    last_volley_size = wing_shots.size() + int(attack_profile["projectiles"])
    volley_count += 1
    _sync_player_bullet_batch()
    _play_sfx(sfx_laser, -12.0)
    mission_director.record_weapon(weapon_mode)
    return last_volley_size


func _create_wingmen() -> void:
    for index in range(4):
        var wing := Node3D.new()
        wing.name = "Wingman_%d" % index
        add_child(wing)
        visual_factory.attach_wingman(wing)
        wingmen.append(wing)


func _update_wingmen(_delta: float) -> void:
    var count: int = arsenal.get_wing_count(weapon_rank)
    # Shift the formation center near edges; do not stack escorts against the clamp.
    var center_x := clampf(player.position.x, -8.2, 8.2)
    for index in range(wingmen.size()):
        var wing := wingmen[index]
        var offset: Vector3 = arsenal.get_wing_offset(index)
        wing.position = Vector3(center_x + offset.x, 0.0, minf(11.4, player.position.z + offset.z))
        wing.position.y = 0.08 + sin(elapsed * 3.0 + float(index)) * 0.04
        wing.visible = index < count and not is_game_over
        (wing.get_node("ArtSprite") as Sprite3D).rotation_degrees.z = player_art.rotation_degrees.z * 0.6


func _start_overdrive() -> bool:
    if is_paused or is_game_over or overdrive_timer > 0.0 or overdrive_charge < 100.0:
        return false
    overdrive_charge = 0.0
    overdrive_timer = OVERDRIVE_DURATION
    mission_director.record_overdrive()
    mission_presentation.show_notice("百發超載啟動", "僚機協同齊射 · 持續 6 秒", Color("ffe09b"), 1.6)
    shot_timer = 0.0
    arcade_feedback.pulse(player.position, Color("ffe3a4"), 1.4)
    _play_sfx(sfx_pickup, -7.0)
    _update_ui()
    return true


func _update_arcade(delta: float) -> void:
    if is_paused or is_game_over:
        return
    overdrive_timer = maxf(0.0, overdrive_timer - maxf(0.0, delta))
    swarm_timer -= maxf(0.0, delta)
    _hit_feedback_timer = maxf(0.0, _hit_feedback_timer - maxf(0.0, delta))
    combo_timer = maxf(0.0, combo_timer - maxf(0.0, delta))
    if combo_timer <= 0.0:
        combo = 0


func _sync_player_bullet_batch() -> void:
    if not _bullet_batch_dirty or not is_instance_valid(player_bullet_batch):
        return
    var index := 0
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        var vx := float(bullet.get_meta("velocity_x", 0.0))
        var speed := float(bullet.get_meta("speed", 30.0))
        var basis := Basis(Vector3.UP, -atan2(vx, speed)).scaled(Vector3(0.65, 1.0, 0.72))
        player_bullet_batch.multimesh.set_instance_transform(index, Transform3D(basis, bullet.position))
        var color := Color("79efff") if int(bullet.get_meta("emitter", -1)) < 0 else Color("ffd879")
        if bool(bullet.get_meta("overdrive", false)):
            color = color.lightened(0.22)
        player_bullet_batch.multimesh.set_instance_color(index, color)
        index += 1
    player_bullet_batch.multimesh.visible_instance_count = index
    _bullet_batch_dirty = false


func _spawn_bullet(position_value: Vector3, friendly: bool, velocity_x: float = 0.0, speed_override: float = -1.0) -> Node3D:
    var bullet: Node3D
    var pool_kind := "player_bullet" if friendly else "enemy_bullet"
    if friendly:
        if idle_player_bullets.is_empty():
            pool_exhaustion_counts[pool_kind] = int(pool_exhaustion_counts[pool_kind]) + 1
            return null
        else:
            bullet = idle_player_bullets.pop_back()
            pool_reuse_counts[pool_kind] = int(pool_reuse_counts[pool_kind]) + 1
    else:
        if idle_enemy_bullets.is_empty():
            pool_exhaustion_counts[pool_kind] = int(pool_exhaustion_counts[pool_kind]) + 1
            return null
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
    if friendly and speed_override > 0.0:
        bullet_speed = speed_override
    bullet.set_meta("speed", bullet_speed)
    bullet.set_meta("velocity_x", velocity_x)
    bullet.set_meta("damage", 1)
    bullet.set_meta("radius", 0.48 if friendly else 0.42)
    bullet.set_meta("emitter", -1)
    bullet.set_meta("overdrive", false)
    _bullet_batch_dirty = true
    return bullet


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
        _bullet_batch_dirty = true
        idle_player_bullets.append(bullet)
    else:
        idle_enemy_bullets.append(bullet)


func _update_bullets(delta: float) -> void:
    _bullet_batch_dirty = true
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        if not is_instance_valid(bullet):
            continue
        bullet.position.x += float(bullet.get_meta("velocity_x", 0.0)) * delta
        bullet.position.z -= float(bullet.get_meta("speed", 18.0)) * delta
        if bullet.position.z < -18.5 or abs(bullet.position.x) > 16.0:
            _release_bullet(bullet)

    for bullet in get_tree().get_nodes_in_group("enemy_bullet"):
        if not is_instance_valid(bullet):
            continue
        bullet.position.x += float(bullet.get_meta("velocity_x", 0.0)) * delta
        bullet.position.z += float(bullet.get_meta("speed", 6.0)) * delta
        if bullet.position.z > 14.5 or abs(bullet.position.x) > 16.0:
            _release_bullet(bullet)


func _spawn_enemy() -> void:
    # Keep the single-actor helper for tests, tools and reproducible pool fixtures.
    var roll := rng.randf()
    var pool_kind := "heavy" if level >= 3 and roll > 0.72 else "scout"
    _activate_enemy(pool_kind, Vector3(rng.randf_range(-7.1, 7.1), 0.0, -11.2))


func _activate_enemy(pool_kind: String, at: Vector3, archetype: String = "standard") -> Node3D:
    if pool_kind not in ["scout", "heavy"]:
        return null
    if archetype not in ["standard", "interceptor", "bomber", "fodder"]:
        return null
    if (archetype in ["interceptor", "fodder"] and pool_kind != "scout") or (archetype == "bomber" and pool_kind != "heavy"):
        return null
    var idle_pool: Array[Node3D] = idle_heavies if pool_kind == "heavy" else idle_scouts
    if idle_pool.is_empty():
        pool_exhaustion_counts[pool_kind] = int(pool_exhaustion_counts[pool_kind]) + 1
        return null
    var enemy: Node3D = idle_pool.pop_back()
    pool_reuse_counts[pool_kind] = int(pool_reuse_counts[pool_kind]) + 1
    enemy.name = "Enemy_%s" % (pool_kind if archetype == "standard" else archetype)
    enemy.visible = true
    enemy.rotation_degrees = Vector3(0.0, 180.0, 0.0)
    enemy.scale = Vector3.ONE
    enemy.position = at
    enemy.set_meta("pooled_active", true)
    _enemy_activation_serial += 1
    enemy.set_meta("activation_id", _enemy_activation_serial)
    enemy.add_to_group("enemy")
    # Pool identity stays distinct from behavior, so accounting never changes family.
    enemy.set_meta("type", pool_kind)
    enemy.set_meta("archetype", archetype)
    enemy.set_meta("age", 0.0)
    enemy.set_meta("hit_flash", 0.0)
    enemy.set_meta("anchor_x", at.x)
    enemy.set_meta("phase", rng.randf_range(0.0, TAU))
    enemy.set_meta("wave", rng.randf_range(0.15, 0.65))
    enemy.set_meta("shoot_timer", rng.randf_range(0.7, 2.0))
    enemy.set_meta("is_boss", false)
    visual_factory.set_enemy_archetype(enemy, pool_kind, archetype)

    if pool_kind == "heavy":
        enemy.set_meta("hp", 4 + level / 2)
        enemy.set_meta("speed", 2.1 + level * 0.08)
        enemy.set_meta("score", 260)
        enemy.set_meta("radius", 1.15)
    else:
        enemy.set_meta("hp", 1 + level / 4)
        enemy.set_meta("speed", 3.4 + level * 0.12)
        enemy.set_meta("score", 100)
        enemy.set_meta("radius", 0.78)
    if archetype == "interceptor":
        enemy.set_meta("hp", 2 + level / 4)
        enemy.set_meta("speed", 4.4 + level * 0.10)
        enemy.set_meta("score", 180)
    elif archetype == "bomber":
        enemy.set_meta("hp", 6 + level / 2)
        enemy.set_meta("speed", 1.8 + level * 0.06)
        enemy.set_meta("score", 360)
        enemy.set_meta("shoot_timer", 1.4)
    elif archetype == "fodder":
        enemy.set_meta("hp", 1)
        enemy.set_meta("speed", 4.2)
        enemy.set_meta("score", 40)
        enemy.set_meta("radius", 0.58)
        enemy.set_meta("wave", 0.12)
        enemy.scale = Vector3.ONE * 0.68
    return enemy


func _spawn_fodder_squad() -> int:
    if is_paused or is_game_over or boss_active:
        return 0
    var count := 6 + mini(weapon_rank, 3) * 2
    if idle_scouts.size() < count or SCOUT_POOL_SIZE - idle_scouts.size() + count > 28:
        return 0
    var active_fodder := 0
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if str(enemy.get_meta("archetype", "")) == "fodder":
            active_fodder += 1
    # Reserve twelve scout slots for waves that advance the Boss encounter.
    if active_fodder + count > 16:
        return 0
    for index in range(count):
        var x := lerpf(-8.8, 8.8, float(index % 6) / 5.0)
        var z := -15.0 - float(index / 6) * 1.45
        _activate_enemy("scout", Vector3(x, 0.0, z), "fodder")
    return count


func _spawn_encounter() -> int:
    if boss_active or is_paused or is_game_over:
        return 0
    # One pending wave only: backpressure cannot accumulate an unbounded queue.
    if pending_encounter.is_empty():
        pending_encounter = encounter_director.next_wave(sector_index)
    var scouts_needed := 0
    var heavies_needed := 0
    for entry in pending_encounter["entries"]:
        if entry["pool_kind"] == "scout":
            scouts_needed += 1
        else:
            heavies_needed += 1
    if idle_scouts.size() < scouts_needed or idle_heavies.size() < heavies_needed:
        return 0
    var ordinary_scouts := 0
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if str(enemy.get_meta("pool_kind", "")) == "scout" and str(enemy.get_meta("archetype", "")) != "fodder":
            ordinary_scouts += 1
    if ordinary_scouts + scouts_needed > 12 or SCOUT_POOL_SIZE - idle_scouts.size() + scouts_needed > 28 or HEAVY_POOL_SIZE - idle_heavies.size() + heavies_needed > 5:
        return 0
    for entry in pending_encounter["entries"]:
        var spawn_at: Vector3 = entry["position"]
        spawn_at.x *= 1.2
        spawn_at.z -= 3.0
        _activate_enemy(str(entry["pool_kind"]), spawn_at, str(entry["archetype"]))
    var spawned := scouts_needed + heavies_needed
    _last_encounter_interval_scale = float(pending_encounter["interval_scale"])
    wave_number = int(pending_encounter["number"])
    wave_name = str(pending_encounter["name"])
    pending_encounter = {}
    _update_sector_ui()
    return spawned


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
    enemy.set_meta("archetype", "standard")
    enemy.set_meta("age", 0.0)
    enemy.set_meta("anchor_x", 0.0)
    visual_factory.set_enemy_archetype(enemy, pool_kind, "standard")
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
    mission_presentation.show_notice("警告 · 巨型敵機接近", "擊破核心 · 奪回下一戰區", Color("ff809b"), 3.0)
    var boss := Node3D.new()
    boss.name = "BossCore"
    _enemy_activation_serial += 1
    boss.set_meta("activation_id", _enemy_activation_serial)
    boss.add_to_group("enemy")
    boss.position = Vector3(0.0, 0.2, -12.0)
    boss.set_meta("type", "boss")
    var boss_hp := 320 + bosses_defeated * 140 + weapon_rank * 35
    boss.set_meta("hp", boss_hp)
    boss.set_meta("max_hp", boss_hp)
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
    _active_boss = boss
    _hud_status_mode = ""
    ui_status.text = "WARNING\nBOSS INBOUND"


func _update_enemies(delta: float) -> void:
    for enemy in get_tree().get_nodes_in_group("enemy"):
        if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
            continue
        var is_boss := bool(enemy.get_meta("is_boss", false))
        var archetype := str(enemy.get_meta("archetype", "standard"))
        if is_boss:
            if enemy.position.z < -5.5:
                enemy.position.z += float(enemy.get_meta("speed", 1.2)) * delta
            else:
                enemy.position.x = sin(elapsed * 0.8) * 5.2
                enemy.rotation_degrees.z = sin(elapsed * 1.1) * 8.0
        else:
            enemy.position.z += float(enemy.get_meta("speed", 3.0)) * delta
            if archetype == "interceptor":
                var age := float(enemy.get_meta("age", 0.0)) + delta
                enemy.set_meta("age", age)
                var bank := sin(age * 2.9)
                enemy.position.x = clampf(float(enemy.get_meta("anchor_x", 0.0)) + bank * 1.35, -7.1, 7.1)
                enemy.rotation_degrees.z = bank * 18.0
            else:
                var bank := sin(elapsed * 2.0 + float(enemy.get_meta("phase", 0.0)))
                enemy.position.x += bank * float(enemy.get_meta("wave", 0.3)) * delta
                enemy.rotation_degrees.z = bank * 12.0

        var art_sprite := enemy.get_node_or_null("ArtSprite") as Sprite3D
        if art_sprite:
            art_sprite.rotation_degrees.z = enemy.rotation_degrees.z
            var flash := maxf(0.0, float(enemy.get_meta("hit_flash", 0.0)) - delta)
            enemy.set_meta("hit_flash", flash)
            art_sprite.modulate = Color(1.8, 1.8, 1.8) if flash > 0.0 else Color.WHITE

        var enemy_shot_timer := float(enemy.get_meta("shoot_timer", 1.0)) - delta
        if archetype != "fodder" and enemy_shot_timer <= 0.0 and enemy.position.z > -9.5:
            if _fire_enemy(enemy):
                var base_fire_interval := rng.randf_range(0.55, 1.05) if is_boss else rng.randf_range(1.25, 2.8)
                if archetype == "bomber":
                    base_fire_interval = rng.randf_range(2.4, 3.1)
                enemy_shot_timer = base_fire_interval * float(difficulty_profile["enemy_fire_interval_scale"])
            else:
                enemy_shot_timer = 0.15
        enemy.set_meta("shoot_timer", enemy_shot_timer)

        if enemy.position.z > ENEMY_EXIT_Z:
            if is_boss:
                enemy.position.z = -5.5
            else:
                if archetype != "fodder":
                    _damage_player(1)
                _release_enemy(enemy)
                if is_game_over:
                    return


func _fire_enemy(enemy: Node3D) -> bool:
    var is_boss := bool(enemy.get_meta("is_boss", false))
    var bomber := str(enemy.get_meta("archetype", "standard")) == "bomber"
    var heavy := str(enemy.get_meta("type", "scout")) == "heavy"
    var needed := 5 if is_boss else (3 if bomber else (2 if heavy else 1))
    # A burst is all-or-nothing: saturation never silently changes its pattern.
    if idle_enemy_bullets.size() < needed:
        return false
    if is_boss:
        for vx in [-3.4, -1.7, 0.0, 1.7, 3.4]:
            _spawn_bullet(enemy.position + Vector3(0.0, -0.05, 1.8), false, vx)
    elif bomber:
        for vx in [-1.8, 0.0, 1.8]:
            _spawn_bullet(enemy.position + Vector3(vx * 0.3, 0.0, 1.25), false, vx)
    elif heavy:
        _spawn_bullet(enemy.position + Vector3(-0.55, 0.0, 1.15), false, -0.35)
        _spawn_bullet(enemy.position + Vector3(0.55, 0.0, 1.15), false, 0.35)
    else:
        var direction_x: float = clampf((player.position.x - enemy.position.x) * 0.34, -1.4, 1.4)
        _spawn_bullet(enemy.position + Vector3(0.0, 0.0, 1.0), false, direction_x)
    return true


func _update_pickups(delta: float) -> void:
    for pickup in get_tree().get_nodes_in_group("pickup"):
        if not is_instance_valid(pickup):
            continue
        pickup.position.z += 3.0 * delta
        pickup.rotation_degrees.y += 120.0 * delta
        pickup.position.y = 0.25 + sin(elapsed * 4.0 + float(pickup.get_meta("phase", 0.0))) * 0.22
        if pickup.position.z > ENEMY_EXIT_Z:
            pickup.queue_free()


func _resolve_collisions() -> void:
    var enemies := get_tree().get_nodes_in_group("enemy")
    # Keep insertion order and float precision; only cache spatial data for this pass.
    # A killed pooled enemy moves immediately, so recheck live state before damage.
    # Revisit this cache if damage ever moves a SURVIVING target (e.g. knockback).
    var enemy_positions: Array[Vector3] = []
    var enemy_radii: Array[float] = []
    for enemy in enemies:
        enemy_positions.append(enemy.position)
        enemy_radii.append(float(enemy.get_meta("radius", 0.8)))
    for bullet in get_tree().get_nodes_in_group("player_bullet"):
        if not is_instance_valid(bullet) or bullet.is_queued_for_deletion():
            continue
        var bullet_position: Vector3 = bullet.position
        var bullet_radius := float(bullet.get_meta("radius", 0.45))
        for index in range(enemies.size()):
            var hit_radius := bullet_radius + enemy_radii[index]
            var enemy_position := enemy_positions[index]
            if bullet_position.distance_squared_to(enemy_position) <= hit_radius * hit_radius:
                var enemy: Node3D = enemies[index]
                if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy.is_in_group("enemy"):
                    continue
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
    enemy.set_meta("hit_flash", 0.06)
    if remaining_hp > 0:
        if _hit_feedback_timer <= 0.0:
            arcade_feedback.pulse(enemy.position, Color("d8fbff"), 0.35)
            _hit_feedback_timer = 0.045
        return

    var is_boss := bool(enemy.get_meta("is_boss", false))
    score += int(enemy.get_meta("score", 100))
    var fodder := str(enemy.get_meta("archetype", "standard")) == "fodder"
    kills += 0 if fodder else (1 if not is_boss else 5)
    arcade_kills += 1
    weapon_rank = maxi(weapon_rank, mini(5, 1 + arcade_kills / 8))
    combo += 1
    best_combo = maxi(best_combo, combo)
    combo_timer = 3.0
    var archetype := str(enemy.get_meta("archetype", "standard"))
    mission_director.record_kill(archetype in ["interceptor", "bomber"], is_boss, combo)
    if overdrive_timer <= 0.0:
        overdrive_charge = minf(100.0, overdrive_charge + (2.5 if fodder else 5.0))
    level = 1 + score / 1300
    arcade_feedback.pulse(enemy.position, Color("ffd17a") if not is_boss else Color("ed85ff"), 2.0 if is_boss else 1.0)
    _spawn_explosion(enemy.position, Color("ff5a19") if not is_boss else Color("f23dff"), 0.9 if is_boss else 0.45)
    _play_sfx(sfx_explosion, -4.0 if is_boss else -8.0)

    if is_boss:
        boss_active = false
        _active_boss = null
        bosses_defeated += 1
        pending_encounter = {}
        _set_sector(bosses_defeated)
        bombs = min(5, bombs + 1)
        ui_status.text = "BOSS DOWN\nBONUS +2500"
        _spawn_pickup(enemy.position + Vector3(-1.0, 0.0, 0.0), "power")
        _spawn_pickup(enemy.position + Vector3(1.0, 0.0, 0.0), "health")
    elif str(enemy.get_meta("archetype", "standard")) == "interceptor" and not shield_intro_dropped:
        shield_intro_dropped = true
        _spawn_pickup(enemy.position, "shield")
    elif rng.randf() < (0.07 if fodder else 0.17):
        var kinds := ["power", "health", "bomb", "shield"]
        _spawn_pickup(enemy.position, kinds[rng.randi_range(0, kinds.size() - 1)])
    if is_boss:
        enemy.queue_free()
    else:
        _release_enemy(enemy)


func _damage_player(amount: int) -> void:
    if _pool_stress_mode or invulnerability_timer > 0.0 or is_game_over:
        return
    if shield_timer > 0.0:
        shield_timer = 0.0
        invulnerability_timer = 0.45
        _spawn_explosion(player.position, Color("8af5ff"), 0.9)
        _play_sfx(sfx_hit, -8.0)
        _update_shield(0.0)
        _update_ui()
        return
    hp -= amount
    if amount > 0:
        mission_director.record_damage()
        _mission_damage_pending = true
    arcade_feedback.pulse(player.position, Color("ff4772"), 1.2)
    combo = 0
    combo_timer = 0.0
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
    elif kind == "shield":
        color = Color("8af5ff")
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
    mission_director.record_pickup()
    var kind := str(pickup.get_meta("kind", "power"))
    if overdrive_timer <= 0.0:
        overdrive_charge = minf(100.0, overdrive_charge + 10.0)
    match kind:
        "shield":
            shield_timer = SHIELD_DURATION
            score += 200
            _update_shield(0.0)
        "health":
            hp = min(PLAYER_MAX_HP, hp + 2)
            score += 150
        "bomb":
            bombs = min(5, bombs + 1)
            score += 200
        _:
            score += 450
            level += 1
            weapon_rank = mini(5, weapon_rank + 1)
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
    arcade_feedback.pulse(player.position + Vector3(0.0, 0.0, -1.0), Color("8ff7ff"), 2.0)


func _spawn_explosion(position_value: Vector3, color: Color, scale_factor: float = 1.0) -> void:
    transient_effects.spawn_explosion(position_value, color, scale_factor)


func _game_over() -> void:
    _release_device_inputs()
    is_game_over = true
    world_events.clear()
    mission_presentation.clear()
    _event_warning = ""
    special_weapons.clear()
    overdrive_timer = 0.0
    _update_wingmen(0.0)
    shield_timer = 0.0
    shield_ring.visible = false
    player.visible = false
    ui_center.visible = true
    ui_center.text = "GAME OVER\n分數 %08d\nR / Enter 重新開始" % score
    ui_status.text = "MISSION FAILED"
    _update_ui()


func _restart_game() -> void:
    _release_device_inputs()
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
    transient_effects.clear()
    arcade_feedback.clear()
    special_weapons.clear()
    weapon_mode = 1
    mission_director.reset()
    world_events.reset()
    mission_presentation.clear()
    _event_warning = ""
    _beacon_timer = 12.0
    _mission_last_reward_serial = -1
    _mission_ui_key = ""
    _mission_damage_pending = false
    for node in get_tree().get_nodes_in_group("pickup"):
        if is_instance_valid(node):
            node.queue_free()

    score = 0
    level = 1
    hp = PLAYER_MAX_HP
    bombs = 2
    kills = 0
    next_boss_kill_target = BOSS_EVERY_KILLS
    boss_active = false
    _active_boss = null
    bosses_defeated = 0
    encounter_director.reset()
    pending_encounter = {}
    wave_number = 0
    wave_name = "準備出擊"
    _last_encounter_interval_scale = 1.0
    _set_sector(0)
    map_scenery.reset()
    _hud_status_mode = ""
    is_paused = false
    is_game_over = false
    elapsed = 0.0
    spawn_timer = 0.35
    shot_timer = 0.0
    invulnerability_timer = 0.0
    shield_timer = 0.0
    shield_intro_dropped = false
    weapon_rank = 1
    overdrive_charge = 100.0
    overdrive_timer = 0.0
    last_volley_size = 0
    volley_count = 0
    combo = 0
    combo_timer = 0.0
    best_combo = 0
    arcade_kills = 0
    swarm_timer = 1.2
    _hit_feedback_timer = 0.0
    _hud_arcade_key = ""
    _update_shield(0.0)
    _pool_ui_timer = 0.0
    player.position = Vector3(0.0, 0.0, 6.2)
    player.rotation = Vector3.ZERO
    _update_wingmen(0.0)
    _sync_player_bullet_batch()
    player.visible = true
    ui_center.visible = false
    ui_status.text = "LOCAL 3D\nMISSION START"
    _update_ui()


func _update_missions(delta: float) -> void:
    if is_paused or is_game_over or not is_finite(delta) or delta < 0.0:
        return
    mission_presentation.advance(delta)
    var world: Dictionary = world_events.advance(delta, player.position, not boss_active)
    _event_warning = str(world.get("warning", ""))
    if int(world.get("damage", 0)) > 0:
        _damage_player(1)
        if is_game_over:
            return # A lethal hazard cannot award progress/rewards in this frame.
    for index in range(int(world.get("beacons", 0))):
        mission_director.record_beacon()
        score += 125
        if overdrive_timer <= 0.0:
            overdrive_charge = minf(100.0, overdrive_charge + 12.0)
        arcade_feedback.pulse(player.position, Color("70ffe1"), 0.8)
        _play_sfx(sfx_pickup, -6.0)
    if not boss_active:
        _beacon_timer -= maxf(0.0, delta)
        if _beacon_timer <= 0.0:
            _beacon_timer = 28.0 if world_events.spawn_beacons() else 1.0
    mission_director.record_chain(combo)
    var rescue_held: bool = boss_active and mission_director.get_state()["metric"] == "beacons" and mission_director.get_state()["phase"] == "active"
    if rescue_held:
        _event_warning = "首領交戰：救援任務暫停"
    else:
        mission_director.advance(delta, not _mission_damage_pending)
    _mission_damage_pending = false
    for event: Dictionary in mission_director.drain_events():
        if event["type"] == "completed":
            var serial := int(event["serial"])
            if serial <= _mission_last_reward_serial:
                continue
            _mission_last_reward_serial = serial
            var bonus := int(event["reward_score"])
            score += bonus
            if overdrive_timer <= 0.0:
                overdrive_charge = minf(100.0, overdrive_charge + float(event["reward_charge"]))
            mission_presentation.show_notice("任務完成 · " + str(event["title"]), "獎勵 +%d 分 · 超載補充" % bonus, Color("8effcf"))
            _play_sfx(sfx_pickup, -4.0)
        elif event["type"] == "failed":
            mission_presentation.show_notice("任務時限結束", "新目標即將派發 · 可繼續戰鬥", Color("ffc783"), 2.0)
        elif event["type"] == "started" and event["metric"] == "beacons":
            world_events.spawn_beacons()
    _update_mission_ui()


func _update_mission_ui() -> void:
    var state: Dictionary = mission_director.get_state()
    var marker := "完成" if state["phase"] == "complete" else ("逾時" if state["phase"] == "failed" else "%d/%d · %02d秒" % [int(state["progress"]), int(state["target"]), ceili(float(state["remaining"]))])
    var text := "戰術任務 · %s\n%s" % [str(state["title"]), marker]
    if not _compact_mission:
        text += "\n" + (_event_warning if not _event_warning.is_empty() else str(state["description"]))
    if text != _mission_ui_key:
        _mission_ui_key = text
        ui_mission.text = text


func _set_sector(index: int) -> void:
    sector_index = clampi(index, 0, 2)
    map_scenery.set_sector(sector_index)
    var planet_colors: Array[Color] = [Color(0.34, 0.39, 0.45), Color(0.45, 0.32, 0.23), Color(0.35, 0.27, 0.46)]
    map_planet.modulate = planet_colors[sector_index]
    var sector: Dictionary = encounter_director.get_sector(sector_index)
    sector_environment.ambient_light_color = sector["ambient"]
    sector_environment.sky_rotation = Vector3(0.0, float(sector["sky_rotation"]), 0.0)
    mat_grid.emission = sector["accent"]
    mat_grid.emission_energy_multiplier = 0.3
    mat_star_a.emission = sector["accent"]
    ui_sector.add_theme_color_override("font_color", sector["accent"])
    _update_sector_ui()


func _update_shield(delta: float) -> void:
    if not is_paused and not is_game_over:
        shield_timer = maxf(0.0, shield_timer - maxf(delta, 0.0))
    shield_ring.visible = shield_timer > 0.0 and not is_game_over
    if shield_ring.visible:
        shield_ring.scale = Vector3.ONE * (1.0 + sin(elapsed * 4.0) * 0.025)


func _update_sector_ui() -> void:
    map_route.update_state(sector_index, kills, next_boss_kill_target, boss_active, is_game_over)
    var sector: Dictionary = encounter_director.get_sector(sector_index)
    ui_sector.text = "SECTOR %02d · %s\nWAVE %02d · %s" % [sector_index + 1, str(sector["name"]), wave_number, wave_name]


func _update_ui() -> void:
    _update_mission_ui()
    map_route.update_state(sector_index, kills, next_boss_kill_target, boss_active, is_game_over)
    var profile: Dictionary = arsenal.get_profile(weapon_rank, overdrive_timer > 0.0)
    var arcade_key := "%d/%d/%d/%d/%d/%d/%d" % [weapon_rank, ceili(overdrive_timer), int(overdrive_charge), combo, best_combo, int(is_game_over), weapon_mode]
    if arcade_key != _hud_arcade_key:
        _hud_arcade_key = arcade_key
        ui_arsenal.text = "ARSENAL  %02d / 05\n齊射 %d 發  ·  僚機 %d 架" % [weapon_rank, int(profile["total"]), int(profile["wing_count"])]
        var weapon_name := "散射機砲" if weapon_mode == 1 else str(special_weapons.get_profile(weapon_mode, weapon_rank)["name"])
        var weapon_description := "五階彈幕 · 持續壓制" if weapon_mode == 1 else str(special_weapons.get_profile(weapon_mode, weapon_rank)["description"])
        if weapon_mode != 1 and overdrive_timer <= 0.0:
            ui_arsenal.text = "ARSENAL  %02d / 05\n%s · 僚機 %d 架" % [weapon_rank, weapon_name, int(profile["wing_count"])]
        ui_weapon.text = "武器系統  [ 1 – 4 ]\n1 散射　2 導彈\n3 閃電　4 雷射\n\n▶ %s\n%s" % [weapon_name, "超載中：百發彈幕" if overdrive_timer > 0.0 else weapon_description]
        ui_overdrive.text = "百發超載  %d 秒\n自動齊射 · 火力全開" % ceili(overdrive_timer) if overdrive_timer > 0.0 else ("[ E ] 百發超載就緒\n擊殺／拾取補充能量" if overdrive_charge >= 100.0 else "超載充能  %d%%\n擊殺／拾取補充能量" % int(overdrive_charge))
        ui_combo.text = "%03d  CHAIN\n最高連殺  %d" % [combo, best_combo]
    overdrive_bar.value = overdrive_timer / OVERDRIVE_DURATION * 100.0 if overdrive_timer > 0.0 else overdrive_charge
    var shield_seconds := ceili(shield_timer)
    if _hud_shield_seconds != shield_seconds:
        _hud_shield_seconds = shield_seconds
        ui_shield.text = "護盾 %02d 秒 · 抵擋一次傷害" % shield_seconds if shield_seconds > 0 else "護盾：尚未取得"
    if _hud_score != score:
        _hud_score = score
        ui_score.text = "SCORE  %08d" % score
    if _hud_hp != hp:
        _hud_hp = hp
        ui_hp.text = "HP  " + "♥".repeat(hp) + "♡".repeat(PLAYER_MAX_HP - hp)
    if _hud_level != level:
        _hud_level = level
        ui_level.text = "LEVEL  %02d" % level
    if _hud_bombs != bombs:
        _hud_bombs = bombs
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
    if is_game_over:
        if _hud_status_mode != "failed":
            ui_status.text = "MISSION FAILED"
            _hud_status_mode = "failed"
        return
    if boss_active and is_instance_valid(_active_boss) and not _active_boss.is_queued_for_deletion():
        var current := int(_active_boss.get_meta("hp", 1))
        var maximum := int(_active_boss.get_meta("max_hp", 1))
        if _hud_status_mode != "boss" or _hud_boss_hp != current or _hud_boss_max_hp != maximum:
            ui_status.text = "BOSS HP\n%d / %d" % [current, maximum]
            _hud_status_mode = "boss"
            _hud_boss_hp = current
            _hud_boss_max_hp = maximum
    else:
        var enemy_count := get_tree().get_nodes_in_group("enemy").size()
        if _hud_status_mode != "enemies" or _hud_enemy_count != enemy_count:
            ui_status.text = "LOCAL 3D\nENEMIES %02d" % enemy_count
            _hud_status_mode = "enemies"
            _hud_enemy_count = enemy_count


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
    if _is_shutting_down:
        return
    transient_effects.play_sfx(stream, volume_db)


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

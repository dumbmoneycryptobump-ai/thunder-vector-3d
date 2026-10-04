extends SceneTree

# Exercise the real HUD and terminal-frame flow without saving user settings.
class MemorySettingsStore:
    extends RefCounted

    var values: Dictionary = {}
    var source: RefCounted
    var saves := 0

    func save_settings(new_values: Dictionary) -> Error:
        values = new_values.duplicate(true)
        saves += 1
        return OK

    func get_difficulty_profile(difficulty: String) -> Dictionary:
        return source.call("get_difficulty_profile", difficulty) as Dictionary


var _main_scene: Node
var _failures: Array[String] = []
var _assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("HUD runtime test requires --headless")
        quit(1)
        return
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("HUD runtime test could not load the main scene")
        quit(1)
        return
    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    _main_scene.set_physics_process(false)
    _main_scene.set_process(false)
    _main_scene.is_paused = true

    await _test_scalar_labels()
    await _test_rewards_and_bombs()
    await _test_boss_status()
    await _test_same_count_restart()
    await _test_settings_and_pause()
    await _test_lethal_collision_stops_tick()
    await _test_escape_stops_tick()

    await _reset_scenario()
    _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    if _failures.is_empty():
        print("HUD_RUNTIME_TEST_PASS assertions=%d scalar=correct rewards=correct boss_cache=invalidated terminal=priority lethal_tick=stopped settings_writes=0" % _assertions)
    else:
        for failure in _failures:
            push_error("HUD_RUNTIME_TEST_FAIL: " + failure)
    quit(0 if _failures.is_empty() else 1)


func _test_scalar_labels() -> void:
    await _reset_scenario()
    _main_scene.score = 1234
    _main_scene.hp = 3
    _main_scene.level = 4
    _main_scene.bombs = 1
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_score.text == "SCORE  00001234", "score label must format the current score")
    _expect(_main_scene.ui_hp.text == "HP  ♥♥♥♡♡", "HP label must show current filled and empty hearts")
    _expect(_main_scene.ui_level.text == "LEVEL  04", "level label must update")
    _expect(_main_scene.ui_bombs.text == "BOMB × 1", "bomb label must update")
    var unchanged: Dictionary = _labels()
    for iteration in range(120):
        _main_scene.call("_update_ui")
    _expect(_labels() == unchanged, "unchanged HUD updates must preserve every label")
    _main_scene.hp = 5
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_hp.text == "HP  ♥♥♥♥♥", "a single HP change must refresh the HP label")
    _expect(_main_scene.ui_score.text == unchanged["score"] and _main_scene.ui_level.text == unchanged["level"] and _main_scene.ui_bombs.text == unchanged["bombs"], "changing HP must preserve unrelated scalar labels")


func _test_rewards_and_bombs() -> void:
    await _reset_scenario()
    _main_scene.score = 1200
    _main_scene.hp = 3
    _main_scene.call("_update_ui")
    _main_scene.call("_spawn_enemy")
    var enemy: Node3D = _first_live("enemy") as Node3D
    _expect(enemy != null, "reward fixture must spawn an enemy")
    if enemy == null:
        return
    enemy.position = Vector3.ZERO
    enemy.set_meta("score", 100)
    _main_scene.call("_damage_enemy", enemy, 1000)
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_score.text == "SCORE  00001300", "kill must refresh score after update_ui")
    _expect(_main_scene.ui_level.text == "LEVEL  02", "score milestone must refresh weapon level")

    # Random enemy drops are removed so only this deliberate pickup is collected.
    for pickup in get_nodes_in_group("pickup"):
        pickup.queue_free()
    await process_frame
    await process_frame
    for kind in ["health", "bomb", "power"]:
        _main_scene.call("_spawn_pickup", _main_scene.player.position, kind)
        _main_scene.call("_resolve_collisions")
        _main_scene.call("_update_ui")
        if kind == "health":
            _expect(_main_scene.ui_hp.text == "HP  ♥♥♥♥♥" and _main_scene.ui_score.text == "SCORE  00001450", "health pickup must refresh HP and score")
        elif kind == "bomb":
            _expect(_main_scene.ui_bombs.text == "BOMB × 3" and _main_scene.ui_score.text == "SCORE  00001650", "bomb pickup must refresh bombs and score")
        else:
            _expect(_main_scene.ui_level.text == "LEVEL  03" and _main_scene.ui_score.text == "SCORE  00002100", "power pickup must refresh level and score")
        await process_frame
        await process_frame
    _main_scene.call("_use_bomb")
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_bombs.text == "BOMB × 2", "using a bomb must refresh its count")
    _main_scene.bombs = 0
    _main_scene.call("_use_bomb")
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_bombs.text == "BOMB × 0", "empty bomb inventory must display zero without becoming negative")


func _test_boss_status() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_boss")
    var boss: Node3D = _first_live("enemy") as Node3D
    _expect(boss != null, "boss HUD fixture must spawn a boss")
    if boss == null:
        return
    var maximum: int = int(boss.get_meta("max_hp"))
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "BOSS HP\n%d / %d" % [maximum, maximum], "boss spawn must replace ordinary enemy status")
    _main_scene.call("_damage_enemy", boss, 3)
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "BOSS HP\n%d / %d" % [maximum - 3, maximum], "boss HP changes must invalidate cached status")
    boss.set_meta("max_hp", maximum + 10)
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "BOSS HP\n%d / %d" % [maximum - 3, maximum + 10], "boss maximum HP changes must invalidate cached status")
    _main_scene.call("_damage_enemy", boss, 10000)
    _main_scene.call("_update_ui")
    _expect(not String(_main_scene.ui_status.text).begins_with("BOSS HP"), "boss defeat must stop displaying stale HP before deferred deletion")
    await process_frame
    await process_frame
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "LOCAL 3D\nENEMIES 00", "boss deletion must return to ordinary status")

    # Restart and replace a boss before the old queued node leaves the tree.
    _main_scene.call("_spawn_boss")
    _main_scene.call("_update_ui")
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.call("_spawn_boss")
    var replacement: Node3D = _first_live("enemy") as Node3D
    _expect(replacement != null, "restart must permit a new boss while the old one is queued")
    if replacement == null:
        return
    replacement.set_meta("hp", 17)
    replacement.set_meta("max_hp", 97)
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "BOSS HP\n17 / 97", "restart must invalidate the old boss reference")
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.call("_damage_player", 1)
    _expect(_main_scene.ui_hp.text == "HP  ♡♡♡♡♡", "game_over must immediately refresh lethal HP")
    _expect(_main_scene.ui_status.text == "MISSION FAILED", "game_over must immediately take priority over a live boss")
    _main_scene.call("_update_ui")
    _expect(_main_scene.ui_status.text == "MISSION FAILED", "later HUD refreshes must not overwrite terminal status with boss HP")


func _test_same_count_restart() -> void:
    await _reset_scenario()
    _main_scene.call("_update_ui")
    var initial: Dictionary = _labels()
    _main_scene.call("_game_over")
    _expect(_main_scene.ui_status.text == "MISSION FAILED", "empty-arena game over must display failure")
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _expect(_labels() == initial, "restart must restore status even when cached scalar values and enemy count are unchanged")


func _test_settings_and_pause() -> void:
    await _reset_scenario()
    _main_scene.score = 5678
    _main_scene.hp = 2
    _main_scene.level = 5
    _main_scene.bombs = 4
    _main_scene.call("_update_ui")
    var initial: Dictionary = _labels()
    var original_store: RefCounted = _main_scene.settings_store
    var memory_store := MemorySettingsStore.new()
    memory_store.source = original_store
    memory_store.values = _main_scene.settings_values.duplicate(true)
    _main_scene.settings_store = memory_store
    _main_scene.is_paused = false
    _send_key(KEY_P)
    _main_scene.call("_update_ui")
    _expect(_main_scene.is_paused and _labels() == initial, "pause must preserve the HUD")
    _send_key(KEY_O)
    _send_key(KEY_DOWN)
    _send_key(KEY_UP)
    _main_scene.call("_update_ui")
    _expect(_main_scene.settings_open and _main_scene.settings_overlay.visible and _labels() == initial, "settings navigation must preserve gameplay labels")
    _send_key(KEY_ENTER)
    _expect(memory_store.saves == 1, "settings close must use the in-memory save stub")
    _expect(not _main_scene.settings_open and _main_scene.is_paused and _labels() == initial, "settings close must return to pause with unchanged labels")
    _send_key(KEY_P)
    _expect(not _main_scene.is_paused and _labels() == initial, "resume must preserve gameplay labels")
    _main_scene.is_paused = true
    _main_scene.settings_store = original_store


func _test_lethal_collision_stops_tick() -> void:
    # Both ordinary spawn and boss-threshold spawn must be blocked after death.
    for boss_due in [false, true]:
        await _reset_scenario()
        _main_scene.hp = 1
        _main_scene.invulnerability_timer = 0.0
        _main_scene.spawn_timer = 0.0
        _main_scene.shot_timer = 100.0
        if boss_due:
            _main_scene.kills = _main_scene.next_boss_kill_target
        _main_scene.call("_spawn_bullet", _main_scene.player.position, false, 0.0)
        _main_scene.call("_spawn_pickup", _main_scene.player.position, "health")
        _main_scene.is_paused = false
        _main_scene.call("_physics_process", 1.0 / 60.0)
        _expect(_main_scene.is_game_over and _main_scene.hp == 0, "lethal collision must enter game over (boss_due=%s)" % boss_due)
        _expect(_main_scene.score == 0 and _live_count("pickup") == 1, "same-frame health pickup must not revive or reward a dead player")
        _expect(_live_count("enemy") == 0 and not _main_scene.boss_active, "post-death tick must not spawn ordinary enemies or a boss")
        _expect(_main_scene.next_boss_kill_target == 20, "post-death tick must not advance boss progression")
        _expect(_main_scene.ui_hp.text == "HP  ♡♡♡♡♡" and _main_scene.ui_status.text == "MISSION FAILED", "lethal tick must leave an accurate terminal HUD")
        var elapsed_after: float = _main_scene.elapsed
        _main_scene.call("_physics_process", 1.0)
        _expect(is_equal_approx(float(_main_scene.elapsed), elapsed_after) and _live_count("pickup") == 1, "later terminal ticks must remain stopped")


func _test_escape_stops_tick() -> void:
    await _reset_scenario()
    _main_scene.call("_spawn_enemy")
    _main_scene.call("_spawn_enemy")
    var enemies: Array[Node] = get_nodes_in_group("enemy")
    _expect(enemies.size() == 2, "escape fixture must create two enemies")
    if enemies.size() != 2:
        return
    var escaping: Node3D = enemies[0] as Node3D
    var later: Node3D = enemies[1] as Node3D
    escaping.position = Vector3(7.0, 0.0, _main_scene.ENEMY_EXIT_Z + 0.1)
    escaping.set_meta("shoot_timer", 100.0)
    later.position = Vector3(5.0, 0.0, -2.0)
    later.set_meta("shoot_timer", 0.0)
    var later_position: Vector3 = later.position
    _main_scene.call("_spawn_bullet", Vector3(-5.0, 0.0, -2.0), true, 0.0)
    var bullet: Node3D = _first_live("player_bullet") as Node3D
    var bullet_position: Vector3 = bullet.position
    _main_scene.call("_spawn_pickup", _main_scene.player.position, "health")
    var pickup: Node3D = _first_live("pickup") as Node3D
    var pickup_position: Vector3 = pickup.position
    _main_scene.hp = 1
    _main_scene.invulnerability_timer = 0.0
    _main_scene.spawn_timer = 0.0
    _main_scene.shot_timer = 100.0
    _main_scene.kills = _main_scene.next_boss_kill_target
    _main_scene.is_paused = false
    _main_scene.call("_physics_process", 1.0 / 60.0)
    _expect(_main_scene.is_game_over and _main_scene.hp == 0, "escaped enemy must kill a player with one HP")
    _expect(not escaping.is_in_group("enemy"), "escaping enemy must return to its pool")
    _expect(later.position == later_position and float(later.get_meta("shoot_timer")) == 0.0, "later enemies must not move or fire after lethal escape")
    _expect(_live_count("enemy_bullet") == 0, "later enemy must not emit post-death bullets")
    _expect(bullet.position == bullet_position, "player bullets must not advance after lethal enemy update")
    _expect(pickup.position == pickup_position and _live_count("pickup") == 1 and _main_scene.score == 0, "pickup update and collection must not run after lethal enemy update")
    _expect(_live_count("enemy") == 1 and not _main_scene.boss_active, "lethal escape must not spawn an additional enemy or boss")
    _expect(_main_scene.ui_hp.text == "HP  ♡♡♡♡♡" and _main_scene.ui_status.text == "MISSION FAILED", "lethal escape must refresh terminal HUD immediately")


func _labels() -> Dictionary:
    return {
        "score": String(_main_scene.ui_score.text),
        "hp": String(_main_scene.ui_hp.text),
        "level": String(_main_scene.ui_level.text),
        "bombs": String(_main_scene.ui_bombs.text),
        "status": String(_main_scene.ui_status.text),
    }


func _reset_scenario() -> void:
    _main_scene.call("_restart_game")
    _main_scene.is_paused = true
    _main_scene.rng.seed = 424242
    await process_frame
    await process_frame
    _main_scene.call("_update_ui")


func _send_key(keycode: int) -> void:
    var event := InputEventKey.new()
    event.keycode = keycode
    event.pressed = true
    _main_scene.call("_unhandled_key_input", event)


func _first_live(group_name: String) -> Node:
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            return node
    return null


func _live_count(group_name: String) -> int:
    var count := 0
    for node in get_nodes_in_group(group_name):
        if is_instance_valid(node) and not node.is_queued_for_deletion():
            count += 1
    return count


func _expect(condition: bool, message: String) -> void:
    _assertions += 1
    if not condition:
        _failures.append(message)

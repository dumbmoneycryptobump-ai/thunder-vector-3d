extends SceneTree

var game: Node
var assertions := 0
var failures: Array[String] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    game = (load("res://main.tscn") as PackedScene).instantiate()
    root.add_child(game)
    game.set_process(false)
    game.set_physics_process(false)
    game.set_process_unhandled_key_input(false)
    _reset()
    _test_real_rewards()
    _test_weapon_and_overdrive()
    _test_collection_and_hazards()
    _test_pause_death_restart()
    _test_rescue_boss_and_damage_step()
    # Prior kill fixtures can leave random live pickups. Make that case
    # deterministic, reset it, then drain deferred deletion BEFORE measuring
    # the persistent scene baseline (not only after the 120 reset cycles).
    game.call("_spawn_pickup", Vector3(0.0, 0.0, 6.2), "power")
    _expect(not get_nodes_in_group("pickup").is_empty(), "temporary drop exists before baseline settlement")
    _reset()
    await process_frame
    await process_frame
    _expect(get_nodes_in_group("pickup").is_empty(), "baseline excludes actual freed temporary drops")
    var count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
    var world_id: int = game.world_events.get_instance_id()
    var presentation_id: int = game.mission_presentation.get_instance_id()
    for cycle in range(120):
        _reset()
        game.world_events.spawn_beacons()
        game.world_events.advance(10.5, Vector3(10.0, 0.0, 6.0))
        game.mission_presentation.show_notice("測試", "固定動畫")
        game.mission_presentation.advance(0.5)
    _reset()
    await process_frame
    await process_frame
    _expect(int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == count, "120 resets preserve scene node count")
    _expect(game.world_events.get_instance_id() == world_id and game.mission_presentation.get_instance_id() == presentation_id, "persistent event and animation nodes reused")
    game.call("prepare_for_shutdown")
    _expect(int(game.world_events.get_stats()["active"]) == 0 and not game.mission_presentation.visible, "shutdown clears event/animation")
    game.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("TACTICAL_INTEGRATION_TEST_PASS assertions=%d rewards=once pause=frozen lethal=guarded resets=120 settings_writes=0" % assertions)
    else:
        for failure in failures:
            push_error("TACTICAL_INTEGRATION_TEST_FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)


func _test_real_rewards() -> void:
    _reset()
    game.overdrive_charge = 0.0
    for index in range(12):
        var enemy: Node3D = game.call("_activate_enemy", "scout", Vector3(5.0, 0.0, -6.0), "fodder")
        game.call("_damage_enemy", enemy, 1)
    _expect(game.score == 480 and game.kills == 0, "actual fodder keeps original base rewards and boss quota")
    _expect(game.mission_director.get_state()["phase"] == "complete", "actual kills complete mission")
    game.call("_update_missions", 0.0)
    _expect(game.score == 1080 and is_equal_approx(game.overdrive_charge, 45.0), "real mission gives600 points and15 charge once")
    for index in range(20):
        game.call("_update_missions", 0.0)
    _expect(game.score == 1080, "repeated drains cannot duplicate rewards")
    _expect(game.mission_presentation.visible and game.ui_mission.text.contains("完成"), "actual completion drives animated notice/HUD")


func _test_weapon_and_overdrive() -> void:
    _reset()
    _select_metric("weapons")
    for mode in [2, 3, 4]:
        game.call("_set_weapon_mode", mode)
        _expect(game.mission_director.get_state()["progress"] == mode - 2, "switch alone does not award weapon progress")
        _expect(int(game.call("_fire_player")) > 0, "actual special attack must fire")
        game.special_weapons.clear()
        for bullet in get_nodes_in_group("player_bullet"):
            game.call("_release_bullet", bullet)
    _expect(game.mission_director.get_state()["phase"] == "complete", "three actual weapon modes fulfill objective")
    _reset()
    _select_metric("overdrive")
    game.overdrive_charge = 99.0
    _expect(not game.call("_start_overdrive") and game.mission_director.get_state()["progress"] == 0, "rejected overdrive grants no progress")
    game.overdrive_charge = 100.0
    _expect(game.call("_start_overdrive") and game.mission_director.get_state()["phase"] == "complete", "real overdrive hook completes mission")
    _expect(int(game.call("_fire_player")) == 100, "hundred-shot attack remains intact")


func _test_collection_and_hazards() -> void:
    _reset()
    _select_metric("beacons")
    game.world_events.reset()
    _expect(game.world_events.spawn_beacons(), "fixed rescue pool activates")
    for index in range(3):
        var pod: Node3D = game.world_events.get_node("RescueBeacon_%d" % index)
        game.player.position = pod.position
        game.call("_update_missions", 0.0)
    _expect(game.mission_director.get_state()["phase"] == "complete" and game.score == 1875, "three actual beacons give375+1500 mission points")
    game.call("_update_missions", 0.0)
    _expect(game.score == 1875, "collected beacon rewards cannot recur")
    _reset()
    game.player.position = Vector3(-7.0, 0.0, 6.0)
    game.call("_update_missions", 8.1)
    _expect(game.hp == 5 and game._event_warning.contains("即將"), "warning reports no damage and clear telegraph")
    game.call("_update_missions", 2.2)
    _expect(game.hp == 4, "active lane damages actual player once")
    game.invulnerability_timer = 0.0
    game.call("_update_missions", 0.2)
    _expect(game.hp == 4, "same pulse cannot repeatedly damage after invulnerability")
    _reset()
    game.player.position = Vector3(-7.0, 0.0, 6.0)
    game.hp = 1
    for index in range(12):
        game.mission_director.record_kill(false, false, index + 1)
    game.call("_update_missions", 10.3)
    _expect(game.is_game_over and game.hp == 0 and game.score == 0, "lethal hazard suppresses pending mission reward")
    _expect(not game.mission_presentation.visible and int(game.world_events.get_stats()["active"]) == 0, "terminal clears all new effects")


func _test_pause_death_restart() -> void:
    _reset()
    game.mission_presentation.show_notice("暫停驗證", "不應前進")
    var mission: Dictionary = game.mission_director.get_state()
    var world: Dictionary = game.world_events.get_stats()
    var remaining: float = game.mission_presentation.remaining
    game.is_paused = true
    game.call("_physics_process", 5.0)
    game.call("_process", 5.0)
    _expect(game.mission_director.get_state() == mission and game.world_events.get_stats() == world and game.mission_presentation.remaining == remaining, "pause freezes new logic, visuals and world timers")
    game.is_paused = false
    game.boss_active = true
    game.call("_update_missions", 1.0)
    _expect(float(game.world_events.get_stats()["clock"]) == 0.0, "boss suspends pulse hazards")
    game.call("_game_over")
    var frozen: Dictionary = game.mission_director.get_state()
    game.call("_physics_process", 5.0)
    _expect(game.mission_director.get_state() == frozen, "gameover stops missions")
    _reset()
    _expect(game.mission_director.get_state()["metric"] == "kills" and game.mission_director.get_state()["progress"] == 0, "restart resets all mission progress")
    _expect(float(game.world_events.get_stats()["clock"]) == 0.0 and game._event_warning.is_empty(), "restart resets world and HUD warnings")


func _test_rescue_boss_and_damage_step() -> void:
    _reset()
    _select_metric("beacons")
    game.world_events.spawn_beacons()
    game.call("_spawn_boss")
    game.call("_update_missions", 100.0)
    _expect(game.mission_director.get_state()["phase"] == "active" and float(game.mission_director.get_state()["remaining"]) == 75.0, "actual boss holds rescue deadline; hidden active pool cannot starve objective")
    _expect(game._event_warning.contains("暫停") and int(game.world_events.get_stats()["active"]) == 3, "boss pause is explicit; beacon slots conserved")
    game.call("_damage_enemy", game._active_boss, 99999)
    game.call("_update_missions", 0.0)
    for index in range(3):
        var pod: Node3D = game.world_events.get_node("RescueBeacon_%d" % index)
        game.player.position = pod.position
        game.call("_update_missions", 0.0)
    _expect(game.mission_director.get_state()["phase"] == "complete" and int(game.world_events.get_stats()["active"]) == 0, "actual boss defeat resumes beacons; all3 remain collectible")
    _reset()
    _select_metric("survival")
    game.mission_director.advance(19.9)
    game.call("_damage_player", 1)
    game.call("_update_missions", 20.0)
    _expect(game.mission_director.get_state()["phase"] == "active" and game.mission_director.get_state()["progress"] == 0, "health loss at end of a long frame never credits that whole frame as safe")
    _expect(is_equal_approx(float(game.mission_director.get_state()["remaining"]), 5.1), "unsafe frame still advances mission deadline")
    _reset()
    _select_metric("chain")
    for index in range(11):
        var enemy: Node3D = game.call("_activate_enemy", "scout", Vector3(5.0, 0.0, -6.0), "fodder")
        game.call("_damage_enemy", enemy, 1)
    _expect(game.mission_director.get_state()["progress"] == 11, "actual eleven chain is shown")
    game.combo_timer = 0.01
    game.call("_update_arcade", 0.1)
    game.call("_update_missions", 0.0)
    _expect(game.combo == 0 and game.mission_director.get_state()["progress"] == 0, "expired chain resets objective HUD without a fabricated extra kill")


func _select_metric(metric: String) -> void:
    for index in range(9):
        if game.mission_director.get_state()["metric"] == metric:
            game.mission_director.drain_events()
            return
        game.mission_director.advance(1000.0)
        game.mission_director.drain_events()
        game.mission_director.advance(1000.0)
        game.mission_director.drain_events()
    _expect(false, "catalog must contain metric " + metric)


func _reset() -> void:
    game.call("_restart_game")
    game.spawn_timer = 99999.0
    game.swarm_timer = 99999.0
    game.shot_timer = 99999.0


func _expect(value: bool, message: String) -> void:
    assertions += 1
    if not value:
        failures.append(message)

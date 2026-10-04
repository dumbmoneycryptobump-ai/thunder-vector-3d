extends "res://tests/capture_content_preview.gd"


func _stage_showcase() -> void:
    super._stage_showcase()
    _main_scene.set_process(false)
    _main_scene.weapon_rank = 5
    _main_scene.combo = 32
    _main_scene.best_combo = 48
    _main_scene.combo_timer = 3.0
    _main_scene.is_paused = false
    _main_scene.call("_start_overdrive")
    _main_scene.call("_fire_player")
    _main_scene.call("_update_bullets", 0.14)
    _main_scene.call("_sync_player_bullet_batch")
    for index in range(6):
        _main_scene.call("_activate_enemy", "scout", Vector3(-5.5 + float(index) * 2.2, 0.0, -3.0), "fodder")
    _main_scene.arcade_feedback.pulse(Vector3(-2.0, 0.0, 0.5), Color("ffd17a"), 1.0)
    _main_scene.arcade_feedback.advance(0.14)
    _main_scene.is_paused = true
    _main_scene.call("_update_ui")

extends "res://tests/capture_preview.gd"

# Official content showcase, using the game's real renderer and original assets.
func _stage_showcase() -> void:
    super._stage_showcase()
    for enemy in get_nodes_in_group("enemy"):
        if not bool(enemy.get_meta("is_boss", false)):
            enemy.position = Vector3(5.0 if enemy.get_meta("type") == "heavy" else -5.0, 0.0, -2.4)
    _main_scene.call("_activate_enemy", "scout", Vector3(-5.2, 0.0, 2.0), "interceptor")
    _main_scene.call("_activate_enemy", "heavy", Vector3(5.2, 0.0, 2.0), "bomber")
    var pickup_x := {"power": -3.0, "health": -1.0, "bomb": 1.0}
    for pickup in get_nodes_in_group("pickup"):
        pickup.position.x = pickup_x[str(pickup.get_meta("kind"))]
    _main_scene.call("_spawn_pickup", Vector3(3.0, 0.0, 3.2), "shield")
    _main_scene.shield_timer = _main_scene.SHIELD_DURATION
    _main_scene.call("_update_shield", 0.0)
    var selected_sector := 0
    var args := OS.get_cmdline_user_args()
    for index in range(args.size() - 1):
        if args[index] == "--sector":
            selected_sector = clampi(int(args[index + 1]), 0, 2)
        elif args[index] == "--height" and int(args[index + 1]) == 1080:
            DisplayServer.window_set_size(Vector2i(1920, 1080))
    _main_scene.wave_number = 8
    _main_scene.wave_name = "重裝護航"
    _main_scene.call("_set_sector", selected_sector)
    _main_scene.call("_update_ui")

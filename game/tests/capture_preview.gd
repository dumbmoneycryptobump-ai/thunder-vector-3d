extends SceneTree

var _main_scene: Node


func _initialize() -> void:
    call_deferred("_capture_preview")


func _capture_preview() -> void:
    var output_path := _output_path()
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Preview capture could not load res://main.tscn")
        quit(1)
        return

    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
    DisplayServer.window_set_size(Vector2i(1280, 720))
    _stage_showcase()

    for frame_index in range(90):
        if frame_index == 30 or frame_index == 60:
            _main_scene.call("_update_ui")
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        push_error("Preview capture produced an empty image")
        quit(1)
        return
    var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
    if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
        push_error("Preview output directory could not be created (error %d)" % directory_error)
        quit(1)
        return
    var save_error := image.save_png(output_path)
    if save_error != OK:
        push_error("Preview PNG could not be saved (error %d)" % save_error)
        quit(1)
        return

    print("PREVIEW_CAPTURE_PASS path=%s size=%dx%d driver=%s" % [
        output_path,
        image.get_width(),
        image.get_height(),
        DisplayServer.get_name(),
    ])
    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    quit(0)


func _stage_showcase() -> void:
    _main_scene.level = 6
    _main_scene.score = 15_420
    _main_scene.hp = 4
    _main_scene.bombs = 3
    _main_scene.rng.seed = 20_260_829

    var scout: Node3D
    var heavy: Node3D
    for attempt in range(12):
        _main_scene.call("_spawn_enemy")
    for enemy in get_nodes_in_group("enemy"):
        if bool(enemy.get_meta("is_boss", false)):
            continue
        var enemy_type := str(enemy.get_meta("type", "scout"))
        if enemy_type == "heavy" and heavy == null:
            heavy = enemy
        elif enemy_type == "scout" and scout == null:
            scout = enemy
        else:
            _main_scene.call("_release_enemy", enemy)
    if scout != null:
        scout.position = Vector3(-4.7, 0.0, -0.8)
    if heavy != null:
        heavy.position = Vector3(4.6, 0.0, 0.0)

    _main_scene.call("_spawn_boss")
    for enemy in get_nodes_in_group("enemy"):
        if bool(enemy.get_meta("is_boss", false)):
            enemy.position = Vector3(0.0, 0.2, -6.8)
            break

    _main_scene.call("_spawn_pickup", Vector3(-2.1, 0.0, 3.2), "power")
    _main_scene.call("_spawn_pickup", Vector3(0.0, 0.0, 3.2), "health")
    _main_scene.call("_spawn_pickup", Vector3(2.1, 0.0, 3.2), "bomb")
    for x in [-1.2, -0.4, 0.4, 1.2]:
        _main_scene.call("_spawn_bullet", Vector3(x, 0.25, 4.5), true, 0.0)
    for x in [-4.0, 4.0]:
        _main_scene.call("_spawn_bullet", Vector3(x, 0.25, 1.5), false, 0.0)

    _main_scene.player.position = Vector3(0.0, 0.0, 6.3)
    _main_scene.is_paused = true
    _main_scene.ui_center.visible = false
    _main_scene.call("_update_ui")


func _output_path() -> String:
    var args := OS.get_cmdline_user_args()
    for index in range(args.size() - 1):
        if args[index] == "--output":
            return str(args[index + 1]).replace("\\", "/")
    return ProjectSettings.globalize_path("user://thunder_vector_preview.png")

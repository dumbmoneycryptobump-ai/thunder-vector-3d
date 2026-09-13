extends SceneTree

const SMOKE_FRAMES := 900

var _main_scene: Node


func _initialize() -> void:
    call_deferred("_run_smoke_test")


func _run_smoke_test() -> void:
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Headless smoke test could not load res://main.tscn")
        quit(1)
        return

    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)

    var frame_index: int = 0
    while frame_index < SMOKE_FRAMES:
        await process_frame
        frame_index += 1

    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
        await process_frame
    _main_scene.queue_free()
    await process_frame
    await process_frame
    quit(0)

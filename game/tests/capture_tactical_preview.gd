extends "res://tests/capture_map_preview.gd"

# Real GL rendered, deliberately staged visual acceptance fixture; no claim of
# a natural rescue/boss encounter or human playthrough. Uses parent's watchdog.


func _stage_showcase() -> void:
    super._stage_showcase()
    _main_scene.mission_director.reset()
    for index in range(9):
        if _main_scene.mission_director.get_state()["metric"] == "beacons":
            break
        _main_scene.mission_director.advance(1000.0)
        _main_scene.mission_director.advance(1000.0)
    _main_scene.mission_director.drain_events()
    _main_scene.world_events.reset()
    _main_scene.world_events.advance(8.4, Vector3(10.0, 0.0, 6.0))
    _main_scene.world_events.spawn_beacons()
    for index in range(3):
        var pod: Node3D = _main_scene.world_events.get_node("RescueBeacon_%d" % index)
        pod.position.z = -1.0 - float(index) * 2.5
    _main_scene.world_events.advance(0.0, Vector3(10.0, 0.0, 6.0))
    _main_scene._event_warning = "左航道即將放電：換道躲避"
    _main_scene.mission_presentation.show_notice("戰術任務 · 救援航道", "回收信標 · 躲避有預警的脈衝航道", Color("8effcf"))
    _main_scene.mission_presentation.advance(0.35)
    _main_scene.call("_update_ui")


func _validate_showcase() -> bool:
    if not super._validate_showcase():
        return false
    var state: Dictionary = _main_scene.mission_director.get_state()
    var world: Dictionary = _main_scene.world_events.get_stats()
    if state["metric"] != "beacons" or world["hazard_phase"] != "warning" or int(world["active"]) != 3 or not _main_scene.mission_presentation.visible:
        push_error("TACTICAL_PREVIEW_FAIL: staged actual mission/telegraph/beacons/animation missing")
        return false
    print("TACTICAL_PREVIEW_JSON " + JSON.stringify({"fixture": "staged real GL; not natural play", "mission": state, "world": world, "animation_remaining": _main_scene.mission_presentation.remaining}))
    return true

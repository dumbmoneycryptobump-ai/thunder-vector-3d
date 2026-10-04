extends SceneTree

const EVENTS := preload("res://scripts/world_events.gd")
const SAFE := Vector3(3.5, 0.0, 6.0)

var events: Node3D
var failures: Array[String] = []
var assertions := 0
var original_nodes := 0
var original_node_ids: Dictionary = {}
var original_resources: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    events = EVENTS.new()
    root.add_child(events)
    events.call("setup")
    original_nodes = _count_nodes(events)
    original_node_ids = _node_ids(events)
    original_resources = _resource_ids(events)
    _test_fixed_pool()
    _test_warning_active_and_repeated_hit()
    _test_lane_bounds_and_cycle()
    _test_large_steps_are_endpoint_samples()
    _test_atomic_beacon_collection()
    _test_expiry()
    _test_disabled_freeze_resume()
    _test_invalid_inputs()
    await _test_motion_and_owner_pause()
    _test_clear_and_reset()
    _test_long_fixed_pool_stability()
    events.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("WORLD_EVENTS_TEST_PASS assertions=%d nodes=%d meshes=4 materials=3 capacity=3 hazards=1 end_step_collision=once_per_wave stress_seconds=600 resources=stable" % [assertions, original_nodes])
        quit(0)
    else:
        for failure in failures:
            push_error("WORLD_EVENTS_TEST_FAIL: " + failure)
        quit(1)


func _test_fixed_pool() -> void:
    var before := _stats()
    _expect(original_nodes == 25 and before["nodes"] == 25, "setup must preallocate exactly25 nodes")
    _expect(original_resources["meshes"].size() == 4 and original_resources["materials"].size() == 3, "all25 nodes share four meshes and three materials")
    _expect(before["capacity"] == 3 and before["active"] == 0 and before["hazard_phase"] == "idle", "initial pool idle and hazard inactive")
    _expect(before["clock"] == 0.0 and before["serial"] == -1 and before["collected"] == 0, "initial counters reset")
    events.call("setup")
    _expect(_count_nodes(events) == original_nodes and _node_ids(events) == original_node_ids and _resource_ids(events) == original_resources, "setup repeated must not allocate nodes/resources")
    for child in events.get_children():
        _expect(child is Node3D and not child.visible, "all six fixed roots begin hidden")
        for renderer in child.get_children():
            _expect(renderer is MeshInstance3D and renderer.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "all procedural renderers have no shadow cost")


func _test_warning_active_and_repeated_hit() -> void:
    events.call("reset")
    var result := _advance(7.999, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 0 and result["warning"] == "" and _visible_lanes() == 0, "no early hazard before8seconds")
    result = _advance(0.001, Vector3(-7.0, 0.0, 6.0))
    _expect(_stats()["hazard_phase"] == "warning" and _stats()["serial"] == 0 and _visible_lanes() == 1, "first warning is left lane at8seconds")
    _expect(result["damage"] == 0 and not str(result["warning"]).is_empty(), "amber warning never damages and returns readable prompt")
    var stripe := events.get_node("PulseLane_0/Stripe") as MeshInstance3D
    var warning_color: Color = stripe.material_override.albedo_color
    _expect(warning_color.g > 0.5 and warning_color.a < 0.3, "warning is low-opacity amber floor not an opaque bullet screen")
    result = _advance(2.199, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 0 and _stats()["hazard_phase"] == "warning", "warning remains harmless for the full2.2seconds")
    result = _advance(0.001, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 1 and _stats()["hazard_phase"] == "active" and _stats()["hazard_active"] == 1, "active window starts at10.2 and reports one real damage")
    var active_color: Color = stripe.material_override.albedo_color
    _expect(active_color.r > 0.9 and active_color.g < 0.2, "active danger turns red")
    for index in range(50):
        result = _advance(0.01, Vector3(-7.0, 0.0, 6.0))
        _expect(result["damage"] == 0, "remaining same-wave samples never report damage twice")
    result = _advance(1.11, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 0 and _stats()["hazard_phase"] == "idle" and _visible_lanes() == 0, "active window ends after1.6seconds")


func _test_lane_bounds_and_cycle() -> void:
    for lane in range(3):
        events.call("reset")
        var result := _advance(10.3 + float(lane) * 16.0, SAFE)
        _expect(result["damage"] == 0 and _stats()["hazard_lane"] == lane and _visible_lanes() == 1, "waves rotate one lane with safe gaps")
        var center_x: float = EVENTS.LANE_X[lane]
        for other_lane in range(3):
            if other_lane == lane:
                continue
            result = _advance(0.0, Vector3(EVENTS.LANE_X[other_lane], 0.0, 6.0))
            _expect(result["damage"] == 0, "other two lanes always remain safe")
        for outside in [Vector3(center_x - 1.501, 0.0, 6.0), Vector3(center_x + 1.501, 0.0, 6.0), Vector3(center_x, 0.0, 0.499), Vector3(center_x, 0.0, 10.201)]:
            result = _advance(0.0, outside)
            _expect(result["damage"] == 0, "out-of-rectangle points never damage")
        result = _advance(0.0, Vector3(center_x + 1.5, 0.0, 10.2))
        _expect(result["damage"] == 1, "inclusive lane rectangle endpoint damages once")
    events.call("reset")
    _advance(58.3, SAFE)
    _expect(_stats()["hazard_lane"] == 0 and _stats()["serial"] == 3, "fourth wave wraps back to left lane")
    events.call("reset")
    _advance(10.3, SAFE)
    _expect(_advance(0.0, Vector3(-8.5, 0.0, 0.5))["damage"] == 1, "minimum inclusive lane corners damage")
    _expect(_advance(48.0, Vector3(-7.0, 0.0, 6.0))["damage"] == 1, "same lane in a later wave gets its independent once-only collision")
    _expect(_advance(0.0, Vector3(-7.0, 0.0, 6.0))["damage"] == 0, "later wave also cannot repeat its own report")


func _test_large_steps_are_endpoint_samples() -> void:
    events.call("reset")
    var result := _advance(12.0, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 0 and _stats()["hazard_phase"] == "idle", "whole-window hitch skips collision rather than retroactive damage")
    result = _advance(14.3, Vector3(0.0, 0.0, 6.0))
    _expect(result["damage"] == 1 and _stats()["serial"] == 1, "large step ending in next active window samples current lane once")
    result = _advance(0.0, Vector3(0.0, 0.0, 6.0))
    _expect(result["damage"] == 0, "zero step cannot replay a reported wave")
    events.call("reset")
    result = _advance(58.3, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 1 and _stats()["serial"] == 3, "multi-wave hitch can only report current sampled wave once")
    events.call("reset")
    events.call("spawn_beacons")
    result = _advance(1.0e200, SAFE)
    _expect(result["damage"] == 0 and _stats()["active"] == 0 and _stats()["clock"] == EVENTS.MAX_CLOCK, "huge finite delta saturates at idle and releases beacons without overflow")
    for child in events.get_children():
        _expect(child.position.is_finite(), "huge delta preserves finite transforms")


func _test_atomic_beacon_collection() -> void:
    events.call("reset")
    _expect(events.call("spawn_beacons"), "empty fixed pool accepts one rescue batch")
    var original_positions: Array[Vector3] = []
    for index in range(3):
        var pod := _pod(index)
        original_positions.append(pod.position)
        _expect(pod.visible and pod.position == Vector3(EVENTS.LANE_X[index], 0.25, -9.0 - float(index) * 4.0), "three beacons spawn with separated deterministic entry positions")
    _expect(not events.call("spawn_beacons") and _stats()["active"] == 3, "active batch rejects overwrite atomically")
    for index in range(3):
        _expect(_pod(index).position == original_positions[index], "rejected spawn preserves every active position")
    var result := _advance(3.3, SAFE)
    _expect(result["beacons"] == 0, "safe route cannot collect distant beacons")
    _expect(is_equal_approx(_pod(0).position.z, -9.0 + 2.8 * 3.3), "beacon entry speed is exactly2.8units/sec")
    for index in range(3):
        var position_value := _pod(index).position
        result = _advance(0.0, position_value + Vector3(1.101, 0.0, 0.0))
        _expect(result["beacons"] == 0, "outside1.1radius must not collect")
        result = _advance(0.0, position_value)
        _expect(result["beacons"] == 1 and not _pod(index).visible, "each exact beacon touch collects and releases exactly once")
        result = _advance(0.0, position_value)
        _expect(result["beacons"] == 0, "collected beacon cannot report a second reward")
        _expect(_stats()["collected"] == index + 1 and _stats()["active"] == 2 - index, "collection counts remain bounded and precise")
        if index < 2:
            _expect(not events.call("spawn_beacons"), "partially empty batch must not overwrite remaining beacons")
    _expect(events.call("spawn_beacons") and _stats()["active"] == 3 and _stats()["beacon_batches"] == 2, "fully released batch becomes reusable without new nodes")
    var position_value := _pod(0).position
    result = _advance(0.0, position_value + Vector3(0.0, 2.0, 0.0))
    _expect(result["beacons"] == 0, "collection uses actual3Ddistance not only screen coordinates")
    result = _advance(0.0, position_value + Vector3(0.0, 0.0, 1.1))
    _expect(result["beacons"] == 1, "exact inclusive1.1radius boundary collects")


func _test_expiry() -> void:
    events.call("reset")
    events.call("spawn_beacons")
    var result := _advance(9.0, SAFE)
    _expect(result["beacons"] == 0 and _stats()["active"] == 2 and not _pod(0).visible, "out-of-arena first beacon expires without reward")
    result = _advance(7.0, SAFE)
    _expect(result["beacons"] == 0 and _stats()["active"] == 0 and _stats()["collected"] == 0, "maximum16second lifetime releases remaining batch with no fake collection")
    _expect(events.call("spawn_beacons"), "expired batch reusable")
    result = _advance(16.0, _pod(0).position)
    _expect(result["beacons"] == 0 and _stats()["active"] == 0, "expiry takes precedence over end-of-step collection")


func _test_disabled_freeze_resume() -> void:
    events.call("reset")
    events.call("spawn_beacons")
    _advance(2.0, SAFE)
    var before := _stats()
    var position_value := _pod(0).position
    var result := _advance(123.0, position_value, false)
    _expect(result == {"damage": 0, "beacons": 0, "warning": ""}, "boss suppression reports no damage/collections/warnings")
    _expect(_stats()["clock"] == before["clock"] and _stats()["active"] == before["active"] and _pod(0).position == position_value, "disabled events freeze both clock and beacon state")
    for child in events.get_children():
        _expect(not child.visible, "boss suppression hides all visual roots")
    _expect(not events.call("spawn_beacons"), "disabled events reject rescue spawn")
    result = _advance(0.0, position_value)
    _expect(result["beacons"] == 1 and _stats()["clock"] == before["clock"] and _pod(1).visible, "resuming restores current state without advancing skipped boss time")
    events.call("reset")
    _advance(10.3, SAFE)
    result = _advance(80.0, Vector3(-7.0, 0.0, 6.0), false)
    _expect(result["damage"] == 0 and _stats()["clock"] == 10.3 and _visible_lanes() == 0, "disabled active wave cannot damage or expire")
    result = _advance(0.0, Vector3(-7.0, 0.0, 6.0))
    _expect(result["damage"] == 1 and _visible_lanes() == 1, "resume active wave remains exactly-once rather than silently consuming hit")


func _test_invalid_inputs() -> void:
    events.call("reset")
    events.call("spawn_beacons")
    var before := _stats()
    var position_value := _pod(0).position
    for delta_value in [-1.0, INF, -INF, NAN]:
        var result := _advance(delta_value, position_value)
        _expect(result == {"damage": 0, "beacons": 0, "warning": ""}, "invalid delta cannot collect, hit or warn")
        _expect(_stats() == before and _pod(0).position == position_value, "invalid delta does not corrupt or rewind world state")
    _advance(0.0, Vector3.INF)
    _expect(_stats()["active"] == 3, "nonfinite player position never collects")
    events.call("reset")
    var result := _advance(10.3, Vector3.INF)
    _expect(result["damage"] == 0 and _stats()["hazard_phase"] == "active", "nonfinite player suppresses collision but valid world clock still advances")
    _expect(_advance(0.0, Vector3(-7.0, 0.0, 6.0))["damage"] == 1, "invalid player position never consumes valid wave hit")


func _test_motion_and_owner_pause() -> void:
    events.call("reset")
    events.call("spawn_beacons")
    events.call("set_motion_enabled", false)
    _advance(0.5, SAFE)
    var body := _pod(0).get_node("Pod") as MeshInstance3D
    var before_body := body.transform
    var before_ring: Transform3D = _pod(0).get_node("Ring").transform
    _advance(0.5, SAFE)
    _expect(body.transform == before_body and _pod(0).get_node("Ring").transform == before_ring, "reduced motion disables hover/spin/pulse but not beacon entry")
    events.call("set_motion_enabled", true)
    _advance(0.1, SAFE)
    _expect(body.transform != before_body, "enabled motion restores original procedural animation")
    var frozen_stats := _stats()
    var frozen_position := _pod(0).position
    paused = true
    # No call to advance: the owner is responsible for physics/pause scheduling.
    await process_frame
    await process_frame
    _expect(_stats() == frozen_stats and _pod(0).position == frozen_position, "without owner advance paused state is fully frozen")
    paused = false
    events.call("reset")
    events.call("set_motion_enabled", false)
    _expect(_advance(10.3, Vector3(-7.0, 0.0, 6.0))["damage"] == 1, "reduced motion never disables actual hazard rules")


func _test_clear_and_reset() -> void:
    events.call("reset")
    events.call("spawn_beacons")
    _advance(3.0, SAFE)
    _advance(0.0, _pod(0).position)
    events.call("clear")
    events.call("clear")
    var before := _stats()
    _expect(before["active"] == 0 and before["cleared"] and before["collected"] == 1 and before["hazard_phase"] == "idle", "clear hides all activity, preserves run telemetry, is idempotent")
    _expect(not events.call("spawn_beacons"), "terminal clear prevents future spawns until reset")
    _expect(_advance(80.0, Vector3(-7.0, 0.0, 6.0)) == {"damage": 0, "beacons": 0, "warning": ""} and _stats() == before, "terminal advance cannot resurrect hazard or collect post-death")
    events.call("reset")
    var after := _stats()
    _expect(after["clock"] == 0.0 and after["collected"] == 0 and after["serial"] == -1 and after["beacon_batches"] == 0 and not after["cleared"], "restart resets full run telemetry and first-wave schedule")
    _expect(events.call("spawn_beacons"), "restart reenables rescue batches")
    _expect(_count_nodes(events) == original_nodes and _node_ids(events) == original_node_ids and _resource_ids(events) == original_resources, "clear/reset never destroy pooled nodes/resources")


func _test_long_fixed_pool_stability() -> void:
    events.call("reset")
    events.call("set_motion_enabled", true)
    for frame in range(36_000):
        if frame % 60 == 0 and _stats()["active"] == 0:
            events.call("spawn_beacons")
        var result := _advance(1.0 / 60.0, SAFE)
        _expect(result["damage"] == 0, "safe gap remains safe during600seconds stress")
        if frame % 60 == 0:
            var stats := _stats()
            _expect(stats["active"] >= 0 and stats["active"] <= 3 and stats["hazard_active"] <= 1 and _visible_lanes() <= 1, "long-lived event populations stay bounded")
            _expect(_count_nodes(events) == original_nodes and _node_ids(events) == original_node_ids and _resource_ids(events) == original_resources, "long simulation preserves actual node/resource identity")
            for index in range(3):
                _expect(_pod(index).position.is_finite(), "long simulation positions remain finite")
    _expect(absf(float(_stats()["clock"]) - 600.0) < 0.000001, "600seconds deterministic driver accumulates expected event clock")
    events.call("reset")
    _expect(_stats()["active"] == 0 and _stats()["clock"] == 0.0 and _count_nodes(events) == original_nodes and _node_ids(events) == original_node_ids and _resource_ids(events) == original_resources, "post-stress reset restores empty original pool")


func _advance(delta: float, player_position: Vector3, enabled: bool = true) -> Dictionary:
    return events.call("advance", delta, player_position, enabled)


func _stats() -> Dictionary:
    return events.call("get_stats")


func _pod(index: int) -> Node3D:
    return events.get_node("RescueBeacon_%d" % index) as Node3D


func _visible_lanes() -> int:
    var count := 0
    for index in range(3):
        count += int(events.get_node("PulseLane_%d" % index).visible)
    return count


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _resource_ids(node: Node) -> Dictionary:
    var meshes := {}
    var materials := {}
    for child in node.get_children():
        if child is MeshInstance3D:
            meshes[child.mesh.get_instance_id()] = true
            materials[child.material_override.get_instance_id()] = true
        var nested := _resource_ids(child)
        meshes.merge(nested["meshes"])
        materials.merge(nested["materials"])
    return {"meshes": meshes, "materials": materials}


func _node_ids(node: Node) -> Dictionary:
    var ids := {node.get_instance_id(): true}
    for child in node.get_children():
        ids.merge(_node_ids(child))
    return ids


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

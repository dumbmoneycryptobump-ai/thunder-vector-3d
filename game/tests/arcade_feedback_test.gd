extends SceneTree

const FEEDBACK_SCRIPT := preload("res://scripts/arcade_feedback.gd")

var failures: Array[String] = []
var assertions := 0
var feedback: Node3D
var camera: Camera3D
var container: Node3D
var initial_nodes := 0
var initial_resources: Dictionary = {}
var initial_camera_transform: Transform3D
var base_offsets := Vector2(0.011, -0.015)


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    container = Node3D.new()
    root.add_child(container)
    camera = Camera3D.new()
    camera.position = Vector3(0.5, 14.0, 7.0)
    camera.rotation_degrees.x = -62.0
    camera.h_offset = base_offsets.x
    camera.v_offset = base_offsets.y
    container.add_child(camera)
    initial_camera_transform = camera.transform
    feedback = FEEDBACK_SCRIPT.new()
    container.add_child(feedback)
    feedback.call("setup", camera)
    initial_nodes = _count_nodes(feedback)
    initial_resources = _resource_ids()
    _test_prewarm()
    _test_expansion_and_expiry()
    _test_overflow()
    _test_camera_and_motion_toggle()
    _test_clear_reuse_and_pause()
    await _test_camera_rebind_and_disposal()
    container.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("ARCADE_FEEDBACK_TEST_PASS assertions=%d capacity=24 meshes=2 materials=24 overflow=oldest camera_offset_max=0.07 clear=restored resources=stable" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("ARCADE_FEEDBACK_TEST_FAIL: " + failure)
        quit(1)


func _test_prewarm() -> void:
    var stats: Dictionary = feedback.call("get_stats")
    _expect(initial_nodes == 1 + 24 * 8, "prewarm must create exactly 24 roots with one ring and six sparks")
    _expect(stats == {"capacity": 24, "active": 0, "reused": 0, "overflow": 0}, "prewarm must expose an idle fixed pool")
    _expect(initial_resources["meshes"].size() == 2, "all pulses must share exactly one torus and one box mesh")
    _expect(initial_resources["materials"].size() == 24, "each slot must own one material shared by its ring and sparks")
    var ring_mesh: Mesh
    var spark_mesh: Mesh
    for slot in feedback.get_children():
        _expect(not slot.visible and slot.get_child_count() == 7, "each idle slot must contain seven hidden-by-parent renderers")
        var material: StandardMaterial3D
        for index in range(slot.get_child_count()):
            var child := slot.get_child(index) as MeshInstance3D
            _expect(child != null, "each slot child must be a lightweight mesh renderer")
            if child == null:
                continue
            if index == 0:
                _expect(child.mesh is TorusMesh, "first renderer must be the thin expanding torus")
                if ring_mesh == null:
                    ring_mesh = child.mesh
                _expect(child.mesh == ring_mesh, "all rings must share their mesh")
                material = child.material_override as StandardMaterial3D
                _expect(material != null and material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "slot material must be unshaded transparent color")
            else:
                _expect(child.mesh is BoxMesh, "spark renderers must use short shared box streaks")
                if spark_mesh == null:
                    spark_mesh = child.mesh
                _expect(child.mesh == spark_mesh, "all spark streaks must share their mesh")
            _expect(child.material_override == material, "a slot must share its single animated material across all seven renderers")
            _expect(child.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "cosmetic streaks must not cast shadows")
    _expect(not _contains_light_or_timer(feedback), "feedback must not allocate lights or timer nodes")


func _test_expansion_and_expiry() -> void:
    feedback.call("clear")
    feedback.call("set_motion_enabled", false)
    var first := feedback.get_child(0) as Node3D
    var ring := first.get_child(0) as MeshInstance3D
    var material := ring.material_override as StandardMaterial3D
    feedback.call("pulse", Vector3(2.0, 0.0, -3.0), Color.CYAN, 1.0)
    _expect(first.visible and first.position.is_equal_approx(Vector3(2.0, 0.07, -3.0)), "pulse must activate the first idle slot at the requested location")
    var initial_radius := ring.scale.x
    var initial_alpha := material.albedo_color.a
    feedback.call("advance", -1.0)
    _expect(is_equal_approx(ring.scale.x, initial_radius) and is_equal_approx(material.albedo_color.a, initial_alpha), "negative delta must not rewind cosmetics")
    feedback.call("advance", 0.16)
    _expect(ring.scale.x > initial_radius and ring.scale.x <= 1.1, "ordinary ring must expand within a compact 1.1-unit radius")
    _expect(material.albedo_color.a < initial_alpha and material.albedo_color.a > 0.0, "pulse alpha must fade as the ring expands")
    for index in range(1, 7):
        var spark := first.get_child(index) as MeshInstance3D
        _expect(spark.position.length() > 0.15 and spark.position.length() <= 1.35, "sparks must travel a short readable distance")
    feedback.call("advance", 0.16)
    _expect(not first.visible and feedback.call("get_stats")["active"] == 0, "exact lifetime must release a slot")
    feedback.call("pulse", Vector3.ZERO, Color.ORANGE, 999.0)
    feedback.call("advance", 0.31)
    _expect(ring.scale.x <= 2.0 and ring.scale.z <= 2.0, "unbounded requested intensity must clamp to a two-unit boss ring")
    feedback.call("clear")
    var stats: Dictionary = feedback.call("get_stats")
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 0.0)
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, -1.0)
    feedback.call("pulse", Vector3.INF, Color.WHITE, 1.0)
    _expect(feedback.call("get_stats") == stats, "zero/negative/nonfinite requests must not consume slots")


func _test_overflow() -> void:
    feedback.call("clear")
    var before: Dictionary = feedback.call("get_stats")
    for index in range(24):
        feedback.call("pulse", Vector3(float(index), 0.0, 0.0), Color.RED, 1.0)
    _expect(feedback.call("get_stats")["active"] == 24, "capacity-sized burst must fill exactly the fixed pool")
    feedback.call("advance", 0.2)
    feedback.call("pulse", Vector3(99.0, 0.0, 0.0), Color.BLUE, 0.5)
    _expect(feedback.get_child(0).position.x == 99.0, "overflow must recycle the oldest slot deterministically")
    _expect(int(feedback.call("get_stats")["overflow"]) == int(before["overflow"]) + 1, "overflow must increment telemetry without creating nodes")
    _expect(_count_nodes(feedback) == initial_nodes and _resource_ids() == initial_resources, "overflow must preserve all prewarmed nodes and resources")
    feedback.call("advance", 0.13)
    _expect(feedback.call("get_stats")["active"] == 1 and feedback.get_child(0).visible, "recycled effect must use its new lifetime while old slots expire")
    feedback.call("advance", 0.2)
    _expect(feedback.call("get_stats")["active"] == 0, "recycled effect must eventually return to idle")


func _test_camera_and_motion_toggle() -> void:
    feedback.call("clear")
    feedback.call("set_motion_enabled", true)
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 999.0)
    var moved := false
    for index in range(16):
        feedback.call("advance", 0.01)
        var current := Vector2(camera.h_offset, camera.v_offset)
        _expect(absf(current.x - base_offsets.x) <= 0.070001 and absf(current.y - base_offsets.y) <= 0.070001, "camera offsets must remain within the 0.07 per-axis cap")
        _expect(camera.transform.is_equal_approx(initial_camera_transform), "shake must never mutate the camera world transform")
        moved = moved or not current.is_equal_approx(base_offsets)
    _expect(moved, "motion-enabled pulse must produce a small projection-offset shake")
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "shake must restore original camera offsets within 0.15 seconds")
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 2.0)
    feedback.call("advance", 0.03)
    feedback.call("set_motion_enabled", false)
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "disabling motion must instantly neutralize the current shake")
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 2.0)
    feedback.call("advance", 0.03)
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "motion-disabled pulses must keep offsets neutral")
    _expect(feedback.call("get_stats")["active"] > 0, "disabling shake must not suppress crisp hit visuals")
    feedback.call("set_motion_enabled", true)
    feedback.call("advance", 0.01)
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "re-enabling motion must not replay a discarded old shake")


func _test_clear_reuse_and_pause() -> void:
    feedback.call("clear")
    var before: Dictionary = feedback.call("get_stats")
    paused = true
    feedback.call("pulse", Vector3.ZERO, Color.WHITE)
    feedback.call("advance", FEEDBACK_SCRIPT.LIFETIME)
    _expect(feedback.call("get_stats")["active"] == 0, "explicit cosmetic advancement must finish pulses while the scene tree is paused")
    paused = false
    for index in range(500):
        feedback.call("pulse", Vector3(float(index % 8), 0.0, 0.0), Color.CYAN, 1.0)
        if index % 11 == 0:
            feedback.call("advance", 0.025)
    feedback.call("clear")
    feedback.call("clear")
    var after: Dictionary = feedback.call("get_stats")
    _expect(after["active"] == 0 and int(after["reused"]) == int(before["reused"]) + 501, "clear must deactivate slots and preserve cumulative accepted-pulse telemetry")
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "clear/restart must restore camera offsets")
    _expect(_count_nodes(feedback) == initial_nodes and _resource_ids() == initial_resources, "repeated bursts, expiry and restart must keep all nodes/resources stable")
    for slot in feedback.get_children():
        _expect(not slot.visible, "clear must hide every pulse slot")
    feedback.call("setup", camera)
    _expect(_count_nodes(feedback) == initial_nodes and _resource_ids() == initial_resources, "repeated setup must not prewarm a duplicate pool")


func _test_camera_rebind_and_disposal() -> void:
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 2.0)
    feedback.call("advance", 0.03)
    var second_camera := Camera3D.new()
    second_camera.h_offset = -0.024
    second_camera.v_offset = 0.018
    container.add_child(second_camera)
    feedback.call("setup", second_camera)
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "camera rebinding must restore the previous camera")
    var second_base := Vector2(second_camera.h_offset, second_camera.v_offset)
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 2.0)
    feedback.call("advance", 0.03)
    feedback.call("clear")
    _expect(Vector2(second_camera.h_offset, second_camera.v_offset).is_equal_approx(second_base), "new camera must restore its own initial offsets")
    second_camera.queue_free()
    await process_frame
    feedback.call("pulse", Vector3.ZERO, Color.WHITE)
    feedback.call("advance", 0.03)
    feedback.call("clear")
    _expect(feedback.call("get_stats")["active"] == 0, "a freed optional camera must not break cleanup")
    feedback.call("setup", camera)
    feedback.call("pulse", Vector3.ZERO, Color.WHITE, 2.0)
    feedback.call("advance", 0.03)
    feedback.queue_free()
    await process_frame
    _expect(Vector2(camera.h_offset, camera.v_offset).is_equal_approx(base_offsets), "module disposal must leave the surviving camera neutral")


func _resource_ids() -> Dictionary:
    var meshes: Dictionary = {}
    var materials: Dictionary = {}
    for slot in feedback.get_children():
        for renderer in slot.get_children():
            if renderer is MeshInstance3D:
                meshes[renderer.mesh.get_instance_id()] = true
                materials[renderer.material_override.get_instance_id()] = true
    return {"meshes": meshes, "materials": materials}


func _contains_light_or_timer(node: Node) -> bool:
    if node is Light3D or node is Timer:
        return true
    for child in node.get_children():
        if _contains_light_or_timer(child):
            return true
    return false


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

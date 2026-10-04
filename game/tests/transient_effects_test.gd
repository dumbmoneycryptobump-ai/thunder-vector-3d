extends SceneTree

const EFFECTS_SCRIPT := preload("res://scripts/transient_effects.gd")

var failures: Array[String] = []
var effects: Node


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    effects = EFFECTS_SCRIPT.new()
    root.add_child(effects)
    var initial_nodes := _count_nodes(effects)
    _expect(initial_nodes == 1 + 32 * 3 + 16, "prewarm should create exactly 32 three-node effects and 16 audio voices")
    var stats: Dictionary = effects.get_stats()
    _expect(stats["fx"]["created"] == 32 and stats["audio"]["created"] == 16, "capacities should be fully prewarmed")
    _expect(stats["fx"]["active"] == 0 and stats["audio"]["active"] == 0, "prewarm should leave every slot idle")
    _expect(get_nodes_in_group(&"fx").is_empty(), "idle effect slots must not belong to fx group")

    var first_root := effects.get_child(0) as Node3D
    var first_sphere := first_root.get_child(0) as MeshInstance3D
    var first_light := first_root.get_child(1) as OmniLight3D
    var shared_mesh := first_sphere.mesh
    var materials: Array[int] = []
    var material_ids: Array[int] = []
    for index in range(32):
        var effect_root := effects.get_child(index) as Node3D
        var sphere := effect_root.get_child(0) as MeshInstance3D
        _expect(sphere.mesh == shared_mesh, "every FX slot should share the same SphereMesh")
        var material_id := sphere.material_override.get_instance_id()
        _expect(not materials.has(material_id), "FX materials must be independent while their alpha animates")
        materials.append(material_id)
        material_ids.append(material_id)

    var tint := Color(0.8, 0.4, 0.2, 1.0)
    effects.spawn_explosion(Vector3(1.0, 2.0, 3.0), tint, 2.0)
    _expect(first_root.visible and first_root.is_in_group(&"fx"), "activation should reveal and group the first idle effect")
    _expect(first_root.position == Vector3(1.0, 2.0, 3.0), "activation should set its position")
    _expect(first_sphere.scale.is_equal_approx(Vector3.ONE * 0.44), "initial shared mesh scale must preserve the old radius")
    _expect(is_equal_approx(first_light.light_energy, 9.0), "initial explosion light energy must preserve scale")
    var first_material := first_sphere.material_override as StandardMaterial3D
    _expect(first_material.albedo_color.is_equal_approx(tint.darkened(0.25)), "initial albedo must preserve the original darkened color")

    effects.advance(0.17)
    var expected_scale := 0.44 * lerpf(1.0, 6.8, 0.75)
    _expect(first_sphere.scale.is_equal_approx(Vector3.ONE * expected_scale), "half-time expansion should use quadratic ease-out")
    var expected_color := tint.darkened(0.25).lerp(Color(tint.r, tint.g, tint.b, 0.0), 0.17 / 0.38)
    _expect(first_material.albedo_color.is_equal_approx(expected_color), "albedo should interpolate independently from the expansion")
    _expect(is_equal_approx(first_light.light_energy, 9.0 * (1.0 - 0.17 / 0.36)), "light should fade linearly over 0.36 seconds")
    effects.advance(0.24)
    _expect(first_root.visible, "effect should stay reserved until its 0.42-second lifetime ends")
    _expect(is_zero_approx(first_light.light_energy) and is_zero_approx(first_material.albedo_color.a), "light and albedo should finish fading before expiry")
    effects.advance(0.02)
    _expect(not first_root.visible and get_nodes_in_group(&"fx").is_empty(), "expired effects should become idle immediately")
    effects.spawn_explosion(Vector3.ZERO, Color.CYAN)
    effects.advance(EFFECTS_SCRIPT.EFFECT_LIFETIME)
    _expect(effects.get_stats()["fx"]["active"] == 0, "an exact lifetime advance should expire an effect")

    for index in range(32):
        effects.spawn_explosion(Vector3(float(index), 0.0, 0.0), Color.RED)
    _expect(effects.get_stats()["fx"]["active"] == 32, "burst should use the whole fixed FX pool")
    effects.advance(0.2)
    effects.spawn_explosion(Vector3(99.0, 0.0, 0.0), Color.BLUE, 0.5)
    _expect(first_root.position.x == 99.0, "overflow should deterministically recycle the oldest active slot")
    _expect(effects.get_stats()["fx"]["overflow"] == 1, "overflow must be counted without allocating")
    _expect(first_material.emission == Color.BLUE, "recycled slots must reset emission color")
    _expect(first_sphere.scale.is_equal_approx(Vector3.ONE * 0.11), "recycled slots must reset expansion")
    effects.advance(0.23)
    _expect(effects.get_stats()["fx"]["active"] == 1 and first_root.visible, "old lifetimes must not release a recycled slot")
    effects.advance(0.2)
    _expect(effects.get_stats()["fx"]["active"] == 0, "recycled effect should expire from its own new birth time")

    paused = true
    effects.spawn_explosion(Vector3.ZERO, Color.WHITE)
    effects.advance(EFFECTS_SCRIPT.EFFECT_LIFETIME)
    _expect(effects.get_stats()["fx"]["active"] == 0, "explicit idle advancement should work even while the scene tree is paused")
    paused = false
    for index in range(400):
        effects.spawn_explosion(Vector3.ZERO, Color.WHITE)
        if index % 7 == 0:
            effects.advance(0.05)
    effects.clear()
    effects.clear()
    _expect(effects.get_stats()["fx"]["active"] == 0, "repeated clear should leave every effect idle")
    _expect(get_nodes_in_group(&"fx").is_empty(), "clear should remove every active fx group membership")
    _expect(_count_nodes(effects) == initial_nodes, "repeated bursts, overflow, expiry and clear must not create or delete nodes")
    for index in range(32):
        var sphere := effects.get_child(index).get_child(0) as MeshInstance3D
        _expect(sphere.mesh == shared_mesh and sphere.material_override.get_instance_id() == material_ids[index], "warm reuse must preserve the preallocated mesh/material resources")

    var stream := AudioStreamGenerator.new()
    effects.play_sfx(stream, -12.0)
    effects.play_sfx(null)
    if DisplayServer.get_name() == "headless":
        _expect(effects.get_stats()["audio"]["reused"] == 0, "headless playback should remain silent")
    else:
        for index in range(16):
            effects.play_sfx(stream, -12.0)
        stats = effects.get_stats()
        _expect(stats["audio"]["active"] == 16 and stats["audio"]["overflow"] == 1, "audio overflow must recycle a voice while preserving fixed capacity")
        var first_voice := effects.get_child(32) as AudioStreamPlayer
        _expect(first_voice.get_signal_connection_list(&"finished").is_empty(), "pooled voices should not accumulate completion callbacks")
        first_voice.stop()
        effects.advance(0.0)
        _expect(effects.get_stats()["audio"]["active"] == 15 and first_voice.stream == null, "completed/stopped voices should release stream references on advance")
    effects.clear()
    _expect(effects.get_stats()["audio"]["active"] == 0, "clear should stop all audio")
    for index in range(16):
        var voice := effects.get_child(32 + index) as AudioStreamPlayer
        _expect(voice.stream == null and not voice.playing, "cleared voices must be stopped without retaining streams")

    effects.spawn_explosion(Vector3.ZERO, Color.WHITE)
    effects.shutdown()
    effects.shutdown()
    var before_shutdown: Dictionary = effects.get_stats()
    effects.spawn_explosion(Vector3.ZERO, Color.RED)
    effects.play_sfx(stream)
    effects.advance(1.0)
    _expect(effects.get_stats() == before_shutdown, "shutdown must be idempotent and reject new work")
    _expect(before_shutdown["shutdown"] and before_shutdown["fx"]["active"] == 0, "shutdown should clear active effects")
    _expect(_count_nodes(effects) == initial_nodes, "shutdown should keep preallocated nodes intact until owner disposal")
    effects.queue_free()
    await process_frame
    await process_frame

    if failures.is_empty():
        print("TRANSIENT_EFFECTS_TEST_PASS fx_capacity=32 audio_capacity=16 shared_mesh=ready animation=preserved overflow=bounded expiry=ready pause=ready clear=ready shutdown=ready audio_driver=%s" % DisplayServer.get_name())
        quit(0)
    else:
        for failure in failures:
            push_error("TRANSIENT_EFFECTS_TEST_FAIL: %s" % failure)
        quit(1)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count

extends SceneTree

const SCENERY_SCRIPT := preload("res://scripts/sector_scenery.gd")

var scenery: Node3D
var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    scenery = SCENERY_SCRIPT.new()
    root.add_child(scenery)
    var initial_nodes := _count_nodes(scenery)
    var initial_resources := _resources(scenery)
    var initial_transforms := _transforms(scenery)
    var stats: Dictionary = scenery.call("get_stats")
    _expect(stats["ready"] and stats["themes"] == 3, "setup must prebuild three sector roots")
    _expect(stats["mesh_instances"] < 250 and stats["mesh_instances"] > 120, "scenery must remain inside its declared bounded geometry budget")
    _expect(stats["meshes"] == 6 and stats["materials"] == 10, "all scenery must share six meshes and ten materials")
    _expect(stats["deck_size"] == Vector2(28.0, 34.0), "the deck must fit the expanded shooting area")
    _expect(stats["raised_prop_min_x"] == 12.5, "raised props must preserve the expanded flight corridor")
    _expect(not _contains_forbidden_node(scenery), "scenery must have no collision, timer or light nodes")
    scenery.call("setup")
    scenery.call("setup")
    _expect(_count_nodes(scenery) == initial_nodes and _resources(scenery) == initial_resources, "setup must be idempotent")
    _check_safety(scenery)

    for index in range(3):
        scenery.call("set_sector", index)
        stats = scenery.call("get_stats")
        _expect(stats["sector"] == index and not String(stats["name"]).is_empty(), "sector index and name must switch immediately")
        var visible_roots := 0
        for sector_root in scenery.get_children():
            if String(sector_root.name).begins_with("Sector_") and sector_root.visible:
                visible_roots += 1
                _expect(String(sector_root.name) == "Sector_%02d" % index, "only the selected geometry root may be visible")
        _expect(visible_roots == 1, "exactly one sector geometry root must be visible")
        _expect(stats["visible_mesh_instances"] <= 70, "a single visible sector must stay inexpensive")
    scenery.call("set_sector", -9)
    _expect(scenery.call("get_stats")["sector"] == 0, "negative indices must clamp to the first sector")
    scenery.call("set_sector", 9)
    _expect(scenery.call("get_stats")["sector"] == 2, "large indices must clamp to the last sector")

    scenery.call("advance", 0.0)
    scenery.call("advance", -1.0)
    _expect(_transforms(scenery) == initial_transforms, "nonpositive delta must not advance scenery")
    scenery.call("advance", 0.25)
    _expect(_transforms(scenery) != initial_transforms, "active advancement must scroll prebuilt layers")
    _expect(is_equal_approx(float(scenery.call("get_stats")["travel"]), 0.65), "manual shader travel must follow active simulation time")
    _expect(scenery.call("get_stats")["phase"] == scenery.call("get_stats")["travel"], "phase must expose the same deterministic scroll clock")
    for index in range(2000):
        scenery.call("advance", 0.1)
        if index % 17 == 0:
            scenery.call("set_sector", index % 3)
    _expect(_count_nodes(scenery) == initial_nodes and _resources(scenery) == initial_resources, "scrolling, wraps and sector switching must not allocate scene resources")
    _check_safety(scenery)
    _check_scroll_bounds(scenery)
    var selected_sector: int = scenery.call("get_stats")["sector"]
    scenery.call("reset")
    _expect(_transforms(scenery) == initial_transforms, "reset must restore every original scrolling transform")
    _expect(scenery.call("get_stats")["travel"] == 0.0 and scenery.call("get_stats")["sector"] == selected_sector, "reset must clear phase without silently changing the selected sector")
    scenery.call("advance", 1.0)
    var one_step := _transforms(scenery)
    scenery.call("reset")
    for index in range(10):
        scenery.call("advance", 0.1)
    _expect(_transforms_approximately_equal(one_step, _transforms(scenery)), "scrolling must be deterministic across equivalent time partitions")
    stats = scenery.call("get_stats")
    scenery.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("SECTOR_SCENERY_TEST_PASS assertions=%d mesh_instances=%d visible_max=67 meshes=6 materials=10 clearance=preserved resources=stable" % [assertions, stats["mesh_instances"]])
        quit(0)
    else:
        for failure in failures:
            push_error("SECTOR_SCENERY_TEST_FAIL: " + failure)
        quit(1)


func _check_safety(node: Node) -> void:
    if node is MeshInstance3D:
        var instance := node as MeshInstance3D
        var bounds := instance.mesh.get_aabb()
        var min_x := INF
        var max_x := -INF
        var max_y := -INF
        for index in range(8):
            var corner: Vector3 = instance.global_transform * bounds.get_endpoint(index)
            min_x = minf(min_x, corner.x)
            max_x = maxf(max_x, corner.x)
            max_y = maxf(max_y, corner.y)
        _expect(max_y <= -1.3 or min_x >= 12.5 or max_x <= -12.5, "every raised prop must remain completely outside the expanded protected flight corridor: %s" % instance.get_path())
        _expect(instance.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "scenery must not add shadow casters")
    for child in node.get_children():
        _check_safety(child)


func _check_scroll_bounds(node: Node) -> void:
    if node is Node3D and String(node.name).begins_with("Scroll_"):
        _expect(node.position.z >= -28.0 and node.position.z < 28.0, "all scrolling groups must wrap inside the offscreen-safe repeat band")
    for child in node.get_children():
        _check_scroll_bounds(child)


func _contains_forbidden_node(node: Node) -> bool:
    if node is CollisionObject3D or node is CollisionShape3D or node is Light3D or node is Timer:
        return true
    for child in node.get_children():
        if _contains_forbidden_node(child):
            return true
    return false


func _resources(node: Node) -> Dictionary:
    var result := {"mesh": {}, "material": {}}
    _collect_resources(node, result)
    return result


func _collect_resources(node: Node, result: Dictionary) -> void:
    if node is MeshInstance3D:
        result["mesh"][node.mesh.get_instance_id()] = true
        result["material"][node.material_override.get_instance_id()] = true
    for child in node.get_children():
        _collect_resources(child, result)


func _transforms(node: Node) -> Dictionary:
    var result: Dictionary = {}
    _collect_transforms(node, result)
    return result


func _collect_transforms(node: Node, result: Dictionary) -> void:
    if node is Node3D:
        result[node.get_instance_id()] = node.transform
    for child in node.get_children():
        _collect_transforms(child, result)


func _transforms_approximately_equal(first: Dictionary, second: Dictionary) -> bool:
    if first.size() != second.size():
        return false
    for key in first:
        if not second.has(key) or not (first[key] as Transform3D).is_equal_approx(second[key]):
            return false
    return true


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

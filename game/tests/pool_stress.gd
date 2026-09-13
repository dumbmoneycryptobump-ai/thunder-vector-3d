extends SceneTree

const STRESS_FRAMES := 36_000
const WARMUP_FRAME := 28_800
const SAMPLE_INTERVAL := 600
const POOL_KINDS := ["player_bullet", "enemy_bullet", "scout", "heavy"]

var _main_scene: Node


func _initialize() -> void:
    call_deferred("_run_stress_test")


func _run_stress_test() -> void:
    var packed_scene: PackedScene = load("res://main.tscn") as PackedScene
    if packed_scene == null:
        push_error("Pool stress test could not load res://main.tscn")
        quit(1)
        return

    _main_scene = packed_scene.instantiate()
    root.add_child(_main_scene)
    var initial_node_count := _count_nodes(root)
    var initial_created := _created_counts(_main_scene.call("get_pool_stats"))
    _main_scene.call("enable_pool_stress_mode", 13_337)

    var warm_created: Dictionary = {}
    var first_late_node_count := -1
    var last_late_node_count := -1
    var late_node_min := 2_147_483_647
    var late_node_max := 0
    var frame_index := 0
    while frame_index < STRESS_FRAMES:
        await physics_frame
        frame_index += 1
        if frame_index == WARMUP_FRAME:
            warm_created = _created_counts(_main_scene.call("get_pool_stats"))
        if frame_index >= WARMUP_FRAME and frame_index % SAMPLE_INTERVAL == 0:
            var current_nodes := _count_nodes(root)
            if first_late_node_count < 0:
                first_late_node_count = current_nodes
            last_late_node_count = current_nodes
            late_node_min = mini(late_node_min, current_nodes)
            late_node_max = maxi(late_node_max, current_nodes)

    var final_stats: Dictionary = _main_scene.call("get_pool_stats")
    var final_created := _created_counts(final_stats)
    var failures: Array[String] = []
    for pool_kind in POOL_KINDS:
        var entry: Dictionary = final_stats[pool_kind]
        if int(entry["active"]) + int(entry["idle"]) != int(entry["created"]):
            failures.append("%s lost pooled nodes: %s" % [pool_kind, entry])
        if int(entry["reused"]) <= 0:
            failures.append("%s never reused an object" % pool_kind)
        if int(entry["exhausted"]) != 0:
            failures.append("%s exhausted its fixed pool %d time(s)" % [pool_kind, int(entry["exhausted"])])
        if int(initial_created[pool_kind]) != int(final_created[pool_kind]):
            failures.append("%s changed its fixed capacity (%s -> %s)" % [
                pool_kind,
                initial_created[pool_kind],
                final_created[pool_kind],
            ])
        if int(warm_created.get(pool_kind, -1)) != int(final_created[pool_kind]):
            failures.append("%s allocated after the 8-minute warmup (%s -> %s)" % [
                pool_kind,
                warm_created.get(pool_kind, -1),
                final_created[pool_kind],
            ])

    if last_late_node_count > first_late_node_count + 64:
        failures.append("scene node count trended upward late in the run (%d -> %d)" % [
            first_late_node_count,
            last_late_node_count,
        ])

    _main_scene.call("disable_pool_stress_mode")
    _main_scene.call("_restart_game")
    await process_frame
    await process_frame
    var reset_node_count := _count_nodes(root)
    if reset_node_count != initial_node_count:
        failures.append("restart did not restore the baseline node count (%d -> %d)" % [
            initial_node_count,
            reset_node_count,
        ])

    if failures.is_empty():
        print("POOL_STRESS_PASS simulated_seconds=600 created=%s nodes_initial=%d nodes_reset=%d nodes_first=%d nodes_last=%d nodes_min=%d nodes_max=%d" % [
            final_created,
            initial_node_count,
            reset_node_count,
            first_late_node_count,
            last_late_node_count,
            late_node_min,
            late_node_max,
        ])
    else:
        for failure in failures:
            push_error("POOL_STRESS_FAIL: %s" % failure)

    if _main_scene.has_method("prepare_for_shutdown"):
        _main_scene.call("prepare_for_shutdown")
    _main_scene.queue_free()
    await process_frame
    await process_frame
    quit(0 if failures.is_empty() else 1)


func _created_counts(stats: Dictionary) -> Dictionary:
    var counts := {}
    for pool_kind in POOL_KINDS:
        counts[pool_kind] = int(stats[pool_kind]["created"])
    return counts


func _count_nodes(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _count_nodes(child)
    return total

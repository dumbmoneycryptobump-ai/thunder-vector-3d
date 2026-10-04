extends "res://tests/arcade_window_benchmark.gd"

# Run one process per sector, sequentially, to avoid competing GPU workloads.
# Inherited fixture retains actual 100-shot volleys and all three GL readbacks.
# Example: -- --sector 2 --width 1280 --frames 720 --output C:/task-output/map.png
var _sector := 0
var _width := 1280
var _resources_initial := 0
var _resources_peak := 0
var _draw_calls_peak := 0
var _render_objects_peak := 0
var _scenery_nodes_initial := 0
var _scenery_nodes_peak := 0
var _scenery_stats_initial: Dictionary = {}


func _parse_arguments() -> bool:
    var args := OS.get_cmdline_user_args()
    var index := 0
    while index < args.size():
        var option: String = args[index]
        if option not in ["--sector", "--width", "--frames", "--output"] or index + 1 >= args.size():
            _failures.append("expected --sector <0|1|2>, --width <1280|1920>, --frames <121..3600> or --output <absolute PNG path>")
            return false
        var value: String = args[index + 1]
        match option:
            "--sector":
                if not value.is_valid_int() or int(value) not in [0, 1, 2]:
                    _failures.append("--sector must be 0, 1 or 2")
                    return false
                _sector = int(value)
            "--width":
                if not value.is_valid_int() or int(value) not in [1280, 1920]:
                    _failures.append("--width must be 1280 or 1920")
                    return false
                _width = int(value)
            "--frames":
                if not value.is_valid_int() or int(value) <= WARMUP_FRAMES or int(value) > 3600:
                    _failures.append("--frames must be an integer between 121 and 3600")
                    return false
                _frames = int(value)
            "--output":
                _output = value.replace("\\", "/")
                if not _output.is_absolute_path() or not _output.to_lower().ends_with(".png") or not DirAccess.dir_exists_absolute(_output.get_base_dir()):
                    _failures.append("--output must name a PNG inside an existing absolute task-output directory")
                    return false
        index += 2
    return true


func _seed_environment() -> void:
    super._seed_environment()
    DisplayServer.window_set_size(Vector2i(_width, _width * 9 / 16))
    _main_scene.bosses_defeated = _sector
    _main_scene.call("_set_sector", _sector)
    var scenery := _main_scene.get("map_scenery") as Node
    if scenery == null:
        _failures.append("map_scenery integration is missing")
    else:
        _scenery_nodes_initial = _subtree_node_count(scenery)
        _scenery_nodes_peak = _scenery_nodes_initial
        if scenery.has_method("get_stats"):
            _scenery_stats_initial = scenery.call("get_stats")
    _resources_initial = int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
    _resources_peak = _resources_initial
    print("MAP_WINDOW_BENCHMARK_START sector=%d requested_size=%dx%d staged_stress=true natural_wave=false" % [_sector, _width, _width * 9 / 16])


func _sample_counts() -> void:
    super._sample_counts()
    _resources_peak = maxi(_resources_peak, int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)))
    _draw_calls_peak = maxi(_draw_calls_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
    _render_objects_peak = maxi(_render_objects_peak, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))
    var scenery := _main_scene.get("map_scenery") as Node
    if scenery != null:
        _scenery_nodes_peak = maxi(_scenery_nodes_peak, _subtree_node_count(scenery))


func _capture_after_measurement() -> Dictionary:
    if _scenery_nodes_peak != _scenery_nodes_initial:
        _failures.append("map scenery node count grew during the rendered fixture")
    if int(_main_scene.sector_index) != _sector:
        _failures.append("selected sector changed during the fixture")
    var size := root.get_visible_rect().size
    if int(size.x) != _width or int(size.y) != _width * 9 / 16:
        _failures.append("requested viewport size did not settle")
    return await super._capture_after_measurement()


func _print_failures() -> void:
    super._print_failures()
    if not is_instance_valid(_main_scene):
        return
    var scenery := _main_scene.get("map_scenery") as Node
    print("MAP_WINDOW_BENCHMARK_JSON " + JSON.stringify({
        "fixture": "staged sustained 100-shot overload inherited from arcade_window_benchmark; not natural waves or general FPS",
        "sector": _sector,
        "width": _width,
        "height": _width * 9 / 16,
        "rendered_frames": _frames,
        "warmup_frames": WARMUP_FRAMES,
        "measured_intervals": _samples_ms.size(),
        "frame_ms_median": _percentile(0.5),
        "frame_ms_p95": _percentile(0.95),
        "frame_ms_p99": _percentile(0.99),
        "resources_initial": _resources_initial,
        "resources_peak": _resources_peak,
        "draw_calls_peak": _draw_calls_peak,
        "render_objects_peak": _render_objects_peak,
        "scenery_nodes_initial": _scenery_nodes_initial,
        "scenery_nodes_peak": _scenery_nodes_peak,
        "scenery_initial": _scenery_stats_initial,
        "scenery_final": scenery.call("get_stats") if scenery != null and scenery.has_method("get_stats") else {},
        "batch_readback": _batch_readback,
        "settings_writes": 0,
        "failures": _failures,
    }))


func _subtree_node_count(node: Node) -> int:
    var total := 1
    for child in node.get_children():
        total += _subtree_node_count(child)
    return total

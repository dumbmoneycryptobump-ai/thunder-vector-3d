extends SceneTree

# 600 seconds of fixed-60-Hz simulation, not ten minutes of wall time or an FPS test.
# Charge is refilled ONLY by this fixture every eight seconds: six seconds of
# maximum overdrive followed by two seconds of ordinary rank-five fire.
const SETTINGS_SCRIPT := preload("res://scripts/settings_store.gd")
const FRAMES := 36_000
const STEP := 1.0 / 60.0
const SAMPLE_INTERVAL := 600
const CAPACITIES := {"player_bullet": 1024, "enemy_bullet": 128, "scout": 64, "heavy": 16}

var main: Node
var failures: Array[String] = []
var assertions := 0
var peak_active := {"player_bullet": 0, "enemy_bullet": 0, "scout": 0, "heavy": 0}
var tick_us: Array[int] = []
var overdrive_volleys := 0
var ordinary_volleys := 0
var activations := 0
var node_samples: Array[int] = []
var wing_ids: Array[int] = []


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    if DisplayServer.get_name() != "headless":
        push_error("Arcade stress test requires --headless")
        quit(1)
        return
    var scene := load("res://main.tscn") as PackedScene
    if scene == null:
        push_error("ARCADE_STRESS_FAIL: main scene unavailable")
        quit(1)
        return
    main = scene.instantiate()
    root.add_child(main)
    main.set_process(false)
    main.set_physics_process(false)
    main.settings_values = SETTINGS_SCRIPT.DEFAULTS.duplicate(true)
    main.call("_apply_settings")
    main.rng.seed = 20261004
    main.set("_pool_stress_mode", true)
    main.weapon_rank = 5
    main.level = 6
    var initial_nodes := _count_nodes(main)
    for wing in main.wingmen:
        wing_ids.append(wing.get_instance_id())
    _expect(wing_ids.size() == 4, "four wingmen must exist before stress")
    _sample_state()

    for frame in range(FRAMES):
        if frame % 480 == 0:
            _expect(main.overdrive_timer <= 0.0, "previous full six-second overdrive must expire before the next fixture refill")
            main.overdrive_charge = 100.0 # Test-only resource injection, never runtime behavior.
            _expect(bool(main.call("_start_overdrive")), "each fixture cycle must activate at full charge")
            activations += 1
        var seconds := float(frame) * STEP
        main.player.position = Vector3(sin(seconds * 0.8) * 7.4, 0.0, 6.0 + sin(seconds * 0.43) * 1.8)
        # Normal encounter and fodder timers remain active throughout. Fixture
        # clears a long-lived boss periodically so spawning cannot stall forever.
        if frame % 900 == 899 and main.boss_active:
            var boss: Node3D = main.get("_active_boss")
            if is_instance_valid(boss) and not boss.is_queued_for_deletion():
                main.call("_damage_enemy", boss, int(boss.get_meta("hp", 1)))
        var before_volley: int = main.volley_count
        var will_overdrive := float(main.overdrive_timer) > STEP
        var tick_start := Time.get_ticks_usec()
        main.call("_physics_process", STEP)
        # Main idle processing is disabled: manually drain pooled FX and update
        # the MultiMesh after the tick, while excluding frame/render wait time.
        main.call("_process", STEP)
        tick_us.append(Time.get_ticks_usec() - tick_start)
        var fired_count := int(main.volley_count) - before_volley
        _expect(fired_count >= 0 and fired_count <= 1, "gameplay and stress auto-fire must never double-fire one tick")
        if fired_count == 1:
            if will_overdrive:
                overdrive_volleys += 1
                _expect(main.last_volley_size == 100, "every successful overdrive volley must contain exactly one hundred bullets")
            else:
                ordinary_volleys += 1
                _expect(main.last_volley_size == 40, "rank-five ordinary volley must contain forty bullets")
        _expect(not main.is_game_over and main.weapon_rank == 5, "test immunity and monotonic max rank must remain intact")
        var active_pb := 1024 - int(main.idle_player_bullets.size())
        var active_eb := 128 - int(main.idle_enemy_bullets.size())
        var active_scout := 64 - int(main.idle_scouts.size())
        var active_heavy := 16 - int(main.idle_heavies.size())
        peak_active["player_bullet"] = maxi(int(peak_active["player_bullet"]), active_pb)
        peak_active["enemy_bullet"] = maxi(int(peak_active["enemy_bullet"]), active_eb)
        peak_active["scout"] = maxi(int(peak_active["scout"]), active_scout)
        peak_active["heavy"] = maxi(int(peak_active["heavy"]), active_heavy)
        _expect(active_scout <= 28 and active_heavy <= 5, "normal gameplay must respect scout-family and heavy-family active budgets")
        if frame % 60 == 59:
            # Flush queued pickups/bosses without advancing manually disabled physics.
            await process_frame
        if (frame + 1) % SAMPLE_INTERVAL == 0:
            _sample_state()
        if failures.size() >= 30:
            break

    var final_stats: Dictionary = main.call("get_pool_stats")
    _expect(activations == 75 and tick_us.size() == FRAMES, "stress must finish all seventy-five full cycles and 36000 ticks")
    _expect(overdrive_volleys > 1500 and ordinary_volleys > 500, "stress must exercise many full overdrive and ordinary volleys")
    _expect(main.arcade_kills > 100 and main.wave_number > 4, "natural spawns and actual collision kills must run throughout the fixture")
    for kind in CAPACITIES:
        _expect(int(final_stats[kind]["reused"]) > 0, "%s must actually be exercised" % kind)
    var node_min := initial_nodes
    var node_max := initial_nodes
    for value in node_samples:
        node_min = mini(node_min, value)
        node_max = maxi(node_max, value)
    _expect(node_max - initial_nodes <= 128, "transient scene nodes must remain bounded above the fixed pool baseline")
    main.call("disable_pool_stress_mode")
    main.call("_restart_game")
    main.is_paused = true
    await process_frame
    await process_frame
    var reset_nodes := _count_nodes(main)
    _expect(reset_nodes == initial_nodes, "restart after queued cleanup must restore exact scene node count")
    _sample_state()
    for index in range(4):
        _expect(main.wingmen[index].get_instance_id() == wing_ids[index], "stress and reset must preserve each original wingman identity")
    _expect(main.player_bullet_batch.multimesh.visible_instance_count == 0, "reset must clear rendered bullet instances")
    tick_us.sort()
    var median_us := tick_us[tick_us.size() / 2] if not tick_us.is_empty() else -1
    var p95_us := tick_us[mini(tick_us.size() - 1, int(ceil(float(tick_us.size()) * 0.95)) - 1)] if not tick_us.is_empty() else -1
    print("ARCADE_STRESS_METRICS simulated_seconds=%d ticks=%d cycles=%d overdrive_volleys=%d ordinary_volleys=%d max_active=%s nodes_initial=%d nodes_reset=%d nodes_min=%d nodes_max=%d sample_count=%d cpu_tick_median_us=%d cpu_tick_p95_us=%d rendering_measured=false charge_refill=test_only" % [int(float(tick_us.size()) * STEP), tick_us.size(), activations, overdrive_volleys, ordinary_volleys, peak_active, initial_nodes, reset_nodes, node_min, node_max, node_samples.size(), median_us, p95_us])
    main.call("prepare_for_shutdown")
    main.queue_free()
    await process_frame
    await process_frame
    if failures.is_empty():
        print("ARCADE_STRESS_PASS assertions=%d capacities=1024,128,64,16 exhaustion=0 partitions=unique wings=identical reset=exact" % assertions)
    else:
        for failure in failures:
            push_error("ARCADE_STRESS_FAIL: " + failure)
    quit(0 if failures.is_empty() else 1)


func _sample_state() -> void:
    var stats: Dictionary = main.call("get_pool_stats")
    var all_ids: Dictionary = {}
    var active_by_kind := {"player_bullet": [], "enemy_bullet": [], "scout": [], "heavy": []}
    for group_name in ["player_bullet", "enemy_bullet", "enemy"]:
        for node in get_nodes_in_group(group_name):
            if bool(node.get_meta("is_boss", false)):
                continue
            var kind := str(node.get_meta("pool_kind", ""))
            _expect(active_by_kind.has(kind), "active pooled actor must declare a valid pool family")
            if active_by_kind.has(kind):
                active_by_kind[kind].append(node)
    var idle_by_kind := {"player_bullet": main.idle_player_bullets, "enemy_bullet": main.idle_enemy_bullets, "scout": main.idle_scouts, "heavy": main.idle_heavies}
    for kind in CAPACITIES:
        var entry: Dictionary = stats[kind]
        _expect(int(entry["created"]) == CAPACITIES[kind], "%s capacity must never grow" % kind)
        _expect(int(entry["exhausted"]) == 0, "%s must not exhaust under maximum cadence" % kind)
        _expect(int(entry["active"]) + int(entry["idle"]) == CAPACITIES[kind], "%s counters must conserve capacity" % kind)
        _expect(active_by_kind[kind].size() == int(entry["active"]), "%s reported active count must match actual group membership" % kind)
        for active in [true, false]:
            var nodes: Array = active_by_kind[kind] if active else idle_by_kind[kind]
            for node in nodes:
                _expect(is_instance_valid(node), "pool partition must contain only live objects")
                var instance_id: int = node.get_instance_id()
                _expect(not all_ids.has(instance_id), "a node must appear in exactly one family and exactly one active/idle partition")
                all_ids[instance_id] = true
                _expect(bool(node.get_meta("pooled_active", false)) == active, "active/idle partition must match actor activity flag")
    _expect(all_ids.size() == 1232, "sample must account for all 1232 fixed pooled nodes")
    node_samples.append(_count_nodes(main))


func _count_nodes(node: Node) -> int:
    var count := 1
    for child in node.get_children():
        count += _count_nodes(child)
    return count


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

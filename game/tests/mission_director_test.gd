extends SceneTree

const DIRECTOR_SCRIPT := preload("res://scripts/mission_director.gd")
const IDS := ["kills", "chain", "pickups", "overdrive", "elites", "survival", "weapons", "beacons", "boss"]
const TARGETS := [12, 12, 3, 1, 4, 20, 3, 3, 1]
const DURATIONS := [40.0, 45.0, 60.0, 45.0, 60.0, 45.0, 60.0, 75.0, 90.0]
const STATE_KEYS := ["id", "title", "description", "metric", "target", "progress", "remaining", "completed", "total", "phase", "serial"]
const EVENT_KEYS := ["type", "title", "metric", "reward_score", "reward_charge", "serial"]

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    _test_initial_catalog_and_reset()
    _test_progress_and_exactly_once()
    _test_damage_and_survival()
    _test_timeout_cooldown_and_invalid_delta()
    _test_copies_and_event_bounds()
    _test_long_rotation_and_rng_isolation()
    if failures.is_empty():
        print("MISSION_DIRECTOR_TEST_PASS assertions=%d missions=9 rounds=200 events_max=4 exactly_once=passed reset=isolated invalid_delta=rejected rng=unchanged" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("MISSION_DIRECTOR_TEST_FAIL: %s" % failure)
        quit(1)


func _test_initial_catalog_and_reset() -> void:
    var director := DIRECTOR_SCRIPT.new()
    var initial: Dictionary = director.get_state()
    _expect(initial.size() == STATE_KEYS.size(), "public state must contain only the agreed fields")
    for key in STATE_KEYS:
        _expect(initial.has(key), "state is missing %s" % key)
    _expect(initial["id"] == "kills" and initial["phase"] == "active", "construction starts the first mission")
    _expect(initial["completed"] == 0 and initial["total"] == 9, "initial run has no successes and nine mission kinds")
    var initial_events: Array[Dictionary] = director.drain_events()
    _expect(initial_events.size() == 1 and initial_events[0]["type"] == "started", "first mission emits one start notification")
    for index in range(IDS.size()):
        var state: Dictionary = director.get_state()
        _expect(state["id"] == IDS[index] and state["metric"] == IDS[index], "mission order and metric must be stable")
        _expect(int(state["target"]) == TARGETS[index], "mission target must match real objective")
        _expect(is_equal_approx(float(state["remaining"]), DURATIONS[index]), "mission deadline must match its catalog")
        _expect(not String(state["title"]).is_empty() and not String(state["description"]).is_empty(), "every objective has readable text")
        _complete_current(director)
        _expect(director.get_state()["phase"] == "complete", "all nine objective types must be completable")
        director.advance(5.0)
    _expect(director.get_state()["id"] == "kills", "the catalog loops without stopping boss or sector progression")
    var before_reset_serial := int(director.get_state()["serial"])
    director.record_kill(false, false, 1)
    director.reset()
    var reset_state: Dictionary = director.get_state()
    _expect(reset_state["id"] == "kills" and reset_state["progress"] == 0.0 and reset_state["completed"] == 0, "reset discards old objectives and all run progress")
    _expect(int(reset_state["serial"]) > before_reset_serial, "reset cannot reuse stale mission serials")
    var reset_events: Array[Dictionary] = director.drain_events()
    _expect(reset_events.size() == 1 and reset_events[0]["type"] == "started", "reset discards old queued rewards and failures")


func _test_progress_and_exactly_once() -> void:
    var director := DIRECTOR_SCRIPT.new()
    director.drain_events()
    director.record_pickup()
    director.record_beacon()
    director.record_weapon(2)
    director.record_overdrive()
    _expect(director.get_state()["progress"] == 0.0, "unrelated events must not advance a kill mission")
    for index in range(11):
        director.record_kill(index % 2 == 0, false, index + 1)
    _expect(director.get_state()["progress"] == 11.0 and director.drain_events().is_empty(), "one kill event counts once before target")
    var kill_serial := int(director.get_state()["serial"])
    director.record_kill(false, true, 12)
    var completion_events: Array[Dictionary] = director.drain_events()
    _expect(completion_events.size() == 1, "meeting the target emits exactly one completion")
    _expect(completion_events[0]["type"] == "completed" and completion_events[0]["serial"] == kill_serial, "completion is tied to the same objective serial")
    _expect(completion_events[0]["reward_score"] > 0 and completion_events[0]["reward_charge"] > 0.0, "only completed missions carry rewards")
    for index in range(50):
        director.record_kill(true, true, 1000)
        director.record_overdrive()
        director.record_pickup()
    _expect(director.drain_events().is_empty() and director.get_state()["completed"] == 1, "cooldown cannot issue duplicate rewards")
    _expect(director.get_state()["progress"] == 12.0, "post-completion progress stays clamped")
    director.advance(5.0)
    director.drain_events()
    director.record_kill(false, false, -99)
    _expect(director.get_state()["progress"] == 0.0, "negative chains cannot create negative progress")
    director.record_kill(false, false, 11)
    director.record_kill(false, false, 3)
    _expect(director.get_state()["progress"] == 3.0, "chain progress reports the current chain rather than summing or retaining an expired chain")
    director.record_damage()
    _expect(director.get_state()["progress"] == 0.0, "damage resets an active chain objective")
    director.record_kill(false, false, 999)
    _expect(director.get_state()["phase"] == "complete" and director.get_state()["progress"] == 12.0, "large real chains complete but remain clamped")
    _seek(director, "elites")
    director.record_kill(false, false, 1)
    director.record_kill(true, true, 2)
    _expect(director.get_state()["progress"] == 0.0, "ordinary and boss kills do not count as interceptor or bomber kills")
    for index in range(4):
        director.record_kill(true, false, index + 1)
    _expect(director.get_state()["phase"] == "complete", "four actual elite kills complete the elite objective")
    _seek(director, "weapons")
    for mode in [-100, 0, 1, 5, 100]:
        director.record_weapon(mode)
    _expect(director.get_state()["progress"] == 0.0, "invalid modes and ordinary guns do not count as special weapons")
    for index in range(100):
        director.record_weapon(2)
    _expect(director.get_state()["progress"] == 1.0, "repeated missiles count as only one distinct weapon")
    director.record_weapon(4)
    _expect(director.get_state()["progress"] == 2.0 and director.get_state()["phase"] == "active", "two distinct weapons are not enough")
    director.record_weapon(3)
    _expect(director.get_state()["phase"] == "complete", "all three distinct special weapons complete")
    _seek(director, "boss")
    director.record_kill(true, false, 99)
    _expect(director.get_state()["progress"] == 0.0, "elite kills never fabricate boss completion")
    director.record_kill(false, true, 1)
    _expect(director.get_state()["phase"] == "complete", "actual boss destruction completes the boss objective")


func _test_damage_and_survival() -> void:
    var director := DIRECTOR_SCRIPT.new()
    _seek(director, "survival")
    director.drain_events()
    director.advance(9.0)
    _expect(director.get_state()["progress"] == 9.0 and director.get_state()["remaining"] == 36.0, "survival tracks simulated active time")
    director.record_damage()
    _expect(director.get_state()["progress"] == 0.0 and director.get_state()["remaining"] == 36.0, "damage resets survival streak, not the mission deadline")
    director.advance(19.0)
    _expect(director.get_state()["phase"] == "active" and director.get_state()["progress"] == 19.0, "nineteen undamaged seconds are insufficient")
    director.advance(1.0)
    _expect(director.get_state()["phase"] == "complete" and director.get_state()["progress"] == 20.0, "twenty undamaged seconds complete")
    director.record_damage()
    _expect(director.get_state()["progress"] == 20.0 and director.drain_events().size() == 1, "damage during cooldown cannot undo completion or duplicate it")
    _seek(director, "survival")
    for index in range(4):
        director.advance(10.0)
        director.record_damage()
    director.advance(5.0)
    _expect(director.get_state()["phase"] == "failed" and director.get_state()["progress"] == 5.0, "repeated damage can exhaust the deadline without completing survival")


func _test_timeout_cooldown_and_invalid_delta() -> void:
    var director := DIRECTOR_SCRIPT.new()
    director.drain_events()
    var initial := director.get_state()
    for delta in [0.0, -0.001, -1000.0, INF, -INF, NAN]:
        director.advance(delta)
        _expect(director.get_state() == initial and director.drain_events().is_empty(), "invalid delta must leave all state and events unchanged")
    director.advance(10000.0)
    var failed := director.get_state()
    _expect(failed["phase"] == "failed" and failed["remaining"] == 3.0, "large finite advance fails only the current expired objective")
    var events: Array[Dictionary] = director.drain_events()
    _expect(events.size() == 1 and events[0]["type"] == "failed", "timeout emits exactly one failure event")
    _expect(events[0]["reward_score"] == 0 and events[0]["reward_charge"] == 0.0, "failure never grants rewards")
    director.record_kill(true, true, 999)
    _expect(director.get_state() == failed and director.drain_events().is_empty(), "events during failed cooldown cannot resurrect the objective")
    director.advance(2.0)
    _expect(director.get_state()["phase"] == "failed" and director.get_state()["remaining"] == 1.0, "failure cooldown lasts three active seconds")
    director.advance(10000.0)
    _expect(director.get_state()["id"] == "chain" and director.get_state()["phase"] == "active" and director.get_state()["remaining"] == 45.0, "overshoot starts one next mission without spending its deadline")
    director.record_kill(false, false, 12)
    director.advance(4.0)
    _expect(director.get_state()["phase"] == "complete" and director.get_state()["remaining"] == 1.0, "successful cooldown lasts five active seconds")
    var paused := director.get_state()
    _expect(director.get_state() == paused, "without scene advance calls, pause and death cannot consume time")
    director.advance(1.0)
    _expect(director.get_state()["id"] == "pickups" and director.get_state()["remaining"] == 60.0, "completion cooldown advances cleanly to pickup objective")
    director.reset()
    _expect(director.get_state()["id"] == "kills" and director.get_state()["remaining"] == 40.0, "restart restores the first full deadline")


func _test_copies_and_event_bounds() -> void:
    var director := DIRECTOR_SCRIPT.new()
    var state: Dictionary = director.get_state()
    state["id"] = "corrupt"
    state["target"] = -100
    state["progress"] = 999999.0
    state["serial"] = -10
    state["new_field"] = []
    _expect(director.get_state()["id"] == "kills" and director.get_state()["target"] == 12 and director.get_state()["progress"] == 0.0, "state copies cannot alter internal mission or catalog")
    var events: Array[Dictionary] = director.drain_events()
    _expect(events[0].size() == EVENT_KEYS.size(), "notifications contain only agreed scalar fields")
    for key in EVENT_KEYS:
        _expect(events[0].has(key), "event is missing %s" % key)
    events[0]["reward_score"] = 99999999
    events[0]["title"] = "corrupt"
    events.append({"injected": true})
    _expect(director.drain_events().is_empty(), "drained event array has no backdoor into pending notifications")
    for index in range(100):
        director.advance(float(director.get_state()["remaining"]) + 1.0)
        director.advance(3.0)
    var bounded: Array[Dictionary] = director.drain_events()
    _expect(bounded.size() == 4, "an undrained long notification backlog never exceeds four entries")
    var previous_serial := -1
    for event in bounded:
        _expect(int(event["serial"]) >= previous_serial, "retained events preserve chronological serial order")
        _expect(event["reward_score"] == 0 and event["reward_charge"] == 0.0, "start and failure notifications cannot leak old rewards")
        previous_serial = int(event["serial"])
    _expect(director.drain_events().is_empty(), "a drain consumes each retained event once")
    director.reset()
    _complete_current(director)
    var fresh: Array[Dictionary] = director.drain_events()
    _expect(fresh.size() == 2 and fresh[1]["reward_score"] == 600 and fresh[1]["title"] == "掃蕩先鋒", "mutating earlier results cannot corrupt future rewards or titles")


func _test_long_rotation_and_rng_isolation() -> void:
    seed(3194)
    var expected_random := randi()
    seed(3194)
    var director := DIRECTOR_SCRIPT.new()
    director.drain_events()
    var previous_serial := int(director.get_state()["serial"])
    var reward_serials: Dictionary = {}
    var initial_objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
    for round_index in range(200):
        for index in range(IDS.size()):
            var state: Dictionary = director.get_state()
            _expect(state["id"] == IDS[index] and state["phase"] == "active", "long rotation preserves nine mission order")
            _expect(state["progress"] == 0.0 and state["remaining"] == DURATIONS[index], "each rotated mission starts with isolated progress and a full timer")
            _complete_current(director)
            var events: Array[Dictionary] = director.drain_events()
            _expect(events.size() == 1 and events[0]["type"] == "completed", "drained long-run completions remain exactly once")
            if not events.is_empty():
                var serial := int(events[0]["serial"])
                _expect(not reward_serials.has(serial), "no mission serial can award twice")
                reward_serials[serial] = true
            director.advance(5.0)
            var started: Array[Dictionary] = director.drain_events()
            _expect(started.size() == 1 and started[0]["type"] == "started", "every cooldown emits one next mission start")
            var next_serial := int(director.get_state()["serial"])
            _expect(next_serial > previous_serial, "long-run mission serials are monotonic")
            previous_serial = next_serial
    _expect(director.get_state()["completed"] == 1800 and reward_serials.size() == 1800, "long-run success count agrees with unique issued rewards")
    _expect(director.get_state()["total"] == 9, "catalog size remains fixed during long play")
    _expect(int(Performance.get_monitor(Performance.OBJECT_COUNT)) <= initial_objects + 2, "pure mission cycling creates no growing Godot object resources")
    _expect(randi() == expected_random, "mission resets, events and rotations do not consume gameplay RNG")


func _seek(director: RefCounted, id: String) -> void:
    for attempt in range(20):
        var state: Dictionary = director.get_state()
        if state["id"] == id and state["phase"] == "active":
            return
        if state["phase"] == "active":
            director.advance(float(state["remaining"]) + 1.0)
        director.advance(float(director.get_state()["remaining"]))
    _expect(false, "test fixture could not find mission %s" % id)


func _complete_current(director: RefCounted) -> void:
    var state: Dictionary = director.get_state()
    match String(state["id"]):
        "kills", "elites":
            for index in range(int(state["target"])):
                director.record_kill(state["id"] == "elites", false, index + 1)
        "chain":
            director.record_kill(false, false, 12)
        "pickups":
            for index in range(3):
                director.record_pickup()
        "overdrive":
            director.record_overdrive()
        "survival":
            director.advance(20.0)
        "weapons":
            for mode in [2, 3, 4]:
                director.record_weapon(mode)
        "beacons":
            for index in range(3):
                director.record_beacon()
        "boss":
            director.record_kill(false, true, 1)


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition:
        failures.append(message)

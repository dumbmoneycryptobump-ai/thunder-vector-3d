extends SceneTree

const ARSENAL_SCRIPT := preload("res://scripts/arsenal.gd")
const NORMAL_TOTALS := [10, 14, 24, 32, 40]
const NORMAL_MAIN_COUNTS := [4, 8, 12, 20, 28]
const WING_OFFSETS := [Vector3(-2.2, 0.0, 0.5), Vector3(2.2, 0.0, 0.5), Vector3(-3.8, 0.0, 1.2), Vector3(3.8, 0.0, 1.2)]

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    _test_profiles()
    _test_patterns()
    _test_wing_offsets()
    _test_clamping()
    _test_no_aliasing()
    if failures.is_empty():
        print("ARSENAL_TEST_PASS assertions=%d ranks=5 normal_totals=10,14,24,32,40 overdrive=100 symmetry=paired duplicates=none catalog=isolated" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("ARSENAL_TEST_FAIL: " + failure)
        quit(1)


func _test_profiles() -> void:
    var arsenal := ARSENAL_SCRIPT.new()
    _expect(arsenal.MAX_VOLLEY == 100 and arsenal.MAX_RANK == 5, "public limits must match the integration contract")
    for rank in range(1, 6):
        var expected_wings := 2 if rank < 3 else 4
        _expect(arsenal.get_wing_count(rank) == expected_wings, "rank must select the expected number of wingmen")
        for overdrive in [false, true]:
            var profile: Dictionary = arsenal.get_profile(rank, overdrive)
            _expect(profile.size() == 6, "profile must expose exactly the six documented fields")
            _expect(profile["name"] is String and not String(profile["name"]).is_empty(), "every profile must have a display name")
            _expect(profile["wing_count"] == expected_wings, "profile wing count must match wing count API")
            _expect(profile["wing_shots"] == (10 if overdrive else 3), "wingman salvo must have its documented size")
            _expect(is_equal_approx(float(profile["interval"]), 0.20 if overdrive else 0.16), "profile must preserve the intended normal/overdrive cadence")
            var expected_total: int = 100 if overdrive else NORMAL_TOTALS[rank - 1]
            var expected_main: int = 100 - expected_wings * 10 if overdrive else NORMAL_MAIN_COUNTS[rank - 1]
            _expect(profile["main_count"] == expected_main and profile["total"] == expected_total, "profile must preserve exact shot counts")
            _expect(int(profile["main_count"]) + int(profile["wing_count"]) * int(profile["wing_shots"]) == int(profile["total"]), "all emitter counts must sum exactly to the profile total")
            _expect(int(profile["total"]) <= arsenal.MAX_VOLLEY, "a profile must never exceed the one-hundred-shot cap")


func _test_patterns() -> void:
    var arsenal := ARSENAL_SCRIPT.new()
    for rank in range(1, 6):
        for overdrive in [false, true]:
            var profile: Dictionary = arsenal.get_profile(rank, overdrive)
            var shots: Array[Dictionary] = arsenal.get_shots(rank, overdrive)
            _expect(shots.size() == profile["total"], "materialized pattern must match its profile count")
            _expect(shots == arsenal.get_shots(rank, overdrive), "pattern generation must be deterministic")
            var counts: Dictionary = {}
            var main_rows: Dictionary = {}
            var lateral_sum := 0.0
            var velocity_sum := 0.0
            for index in range(shots.size()):
                var shot: Dictionary = shots[index]
                _expect(shot.size() == 4, "each shot must expose exactly the four documented fields")
                _expect(shot["emitter"] is int and shot["offset"] is Vector3 and shot["velocity_x"] is float and shot["speed"] is float, "shot fields must retain their public types")
                var emitter: int = shot["emitter"]
                var offset: Vector3 = shot["offset"]
                var velocity_x: float = shot["velocity_x"]
                var speed: float = shot["speed"]
                _expect(emitter >= -1 and emitter < int(profile["wing_count"]), "every shot must reference an available emitter")
                _expect(offset.is_finite() and is_finite(velocity_x) and is_finite(speed), "all shot geometry must be finite")
                _expect(speed >= 30.0 and speed <= 36.0, "forward speed must stay in the intended fast range")
                _expect(is_zero_approx(offset.y) and offset.z < 0.0, "shots must start forward of their emitter in the collision plane")
                if emitter == -1:
                    _expect(absf(offset.x) <= 1.200001 and offset.z >= -2.300001 and offset.z <= -1.499999, "main shots must stay within the four-row muzzle band")
                    _expect(absf(velocity_x) <= (9.000001 if overdrive else 5.000001), "main fan must respect its lateral speed envelope")
                    main_rows[snappedf(offset.z, 0.0001)] = true
                else:
                    _expect(absf(offset.x) <= 0.360001 and offset.z >= -0.950001 and offset.z <= -0.649999, "wing shots must use a compact local fan")
                    _expect(absf(velocity_x) <= (4.000001 if overdrive else 2.500001), "wing fan must remain narrower than the main spread")
                counts[emitter] = int(counts.get(emitter, 0)) + 1
                lateral_sum += offset.x
                velocity_sum += velocity_x
                _expect(_has_mirror(shots, shot), "every shot must have a same-emitter reflected counterpart")
                for previous_index in range(index):
                    var previous: Dictionary = shots[previous_index]
                    if previous["emitter"] == emitter:
                        _expect(not ((previous["offset"] as Vector3).is_equal_approx(offset) and is_equal_approx(float(previous["velocity_x"]), velocity_x)), "same emitter must not emit duplicate position/velocity pairs")
            _expect(main_rows.size() == 4, "every main volley must show exactly four staggered muzzle rows")
            _expect(counts.get(-1, 0) == profile["main_count"], "main emitter must contribute exactly its allocated shots")
            for wing in range(int(profile["wing_count"])):
                _expect(counts.get(wing, 0) == profile["wing_shots"], "every active wingman must contribute equally")
            _expect(absf(lateral_sum) < 0.0001 and absf(velocity_sum) < 0.0001, "a complete volley must not bias its position or velocity to one side")


func _test_wing_offsets() -> void:
    var arsenal := ARSENAL_SCRIPT.new()
    for index in range(4):
        var offset: Vector3 = arsenal.get_wing_offset(index)
        _expect(offset.is_equal_approx(WING_OFFSETS[index]), "wing formation must preserve its documented local offset")
        _expect(is_zero_approx(offset.y) and offset.z > 0.0, "wingmen must follow behind the main ship on the gameplay plane")
    for left_index in [0, 2]:
        var left: Vector3 = arsenal.get_wing_offset(left_index)
        var right: Vector3 = arsenal.get_wing_offset(left_index + 1)
        _expect(left.is_equal_approx(Vector3(-right.x, right.y, right.z)), "wingman pairs must form a symmetric formation")
    _expect(arsenal.get_wing_offset(-99) == arsenal.get_wing_offset(0), "negative wing indices must clamp safely")
    _expect(arsenal.get_wing_offset(99) == arsenal.get_wing_offset(3), "large wing indices must clamp safely")


func _test_clamping() -> void:
    var arsenal := ARSENAL_SCRIPT.new()
    for rank in [-1000000, -1, 0, 1, 2, 3, 4, 5, 6, 99, 1000000]:
        var safe_rank := clampi(rank, 1, 5)
        _expect(arsenal.get_wing_count(rank) == arsenal.get_wing_count(safe_rank), "wing count rank must clamp at both boundaries")
        for overdrive in [false, true]:
            _expect(arsenal.get_profile(rank, overdrive) == arsenal.get_profile(safe_rank, overdrive), "profile rank must clamp at both boundaries")
            _expect(arsenal.get_shots(rank, overdrive) == arsenal.get_shots(safe_rank, overdrive), "pattern rank must clamp at both boundaries")


func _test_no_aliasing() -> void:
    var arsenal := ARSENAL_SCRIPT.new()
    var profile: Dictionary = arsenal.get_profile(5, true)
    var expected_profile := profile.duplicate(true)
    profile["main_count"] = 999
    profile["name"] = "mutated"
    profile["unexpected"] = true
    _expect(arsenal.get_profile(5, true) == expected_profile, "caller changes must not mutate the profile catalog")
    var shots: Array[Dictionary] = arsenal.get_shots(5, true)
    var expected_shots := shots.duplicate(true)
    var untouched_second: Dictionary = shots[1].duplicate(true)
    shots[0]["emitter"] = 99
    shots[0]["offset"] = Vector3(99.0, 99.0, 99.0)
    shots[0]["velocity_x"] = 999.0
    _expect(shots[1] == untouched_second, "shot dictionaries within the same volley must not alias")
    shots.remove_at(1)
    shots.append({"unexpected": true})
    _expect(arsenal.get_shots(5, true) == expected_shots, "caller changes must not mutate subsequent volleys")
    var wing_offset: Vector3 = arsenal.get_wing_offset(0)
    wing_offset.x = 999.0
    _expect(arsenal.get_wing_offset(0).is_equal_approx(WING_OFFSETS[0]), "wing offsets must return independent value data")
    var independent := ARSENAL_SCRIPT.new()
    _expect(independent.get_shots(5, true) == expected_shots, "catalog behavior must be independent across instances")


func _has_mirror(shots: Array[Dictionary], target: Dictionary) -> bool:
    var offset: Vector3 = target["offset"]
    var reflected := Vector3(-offset.x, offset.y, offset.z)
    for shot in shots:
        if shot["emitter"] == target["emitter"] and (shot["offset"] as Vector3).is_equal_approx(reflected) and is_equal_approx(float(shot["velocity_x"]), -float(target["velocity_x"])) and is_equal_approx(float(shot["speed"]), float(target["speed"])):
            return true
    return false


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 30:
        failures.append(message)

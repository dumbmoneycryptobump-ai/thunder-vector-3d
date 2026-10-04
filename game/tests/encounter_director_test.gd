extends SceneTree

const DIRECTOR_SCRIPT := preload("res://scripts/encounter_director.gd")
const EXPECTED_COUNTS := [1, 2, 3, 3]
const SECTOR_NAMES := ["霓虹前線", "琥珀殘骸帶", "紫電核心"]
const FORMATION_NAMES := ["巡邏先鋒", "雙翼攔截", "三角突擊", "重裝護航"]

var failures: Array[String] = []
var assertions := 0


func _initialize() -> void:
    call_deferred("_run_tests")


func _run_tests() -> void:
    _test_sector_catalog()
    _test_wave_bounds()
    _test_reset_and_independent_data()
    _test_sector_diversity_and_clamping()
    if failures.is_empty():
        print("ENCOUNTER_DIRECTOR_TEST_PASS assertions=%d sectors=3 waves=300 formations=4 archetypes=3 catalog=isolated" % assertions)
        quit(0)
    else:
        for failure in failures:
            push_error("ENCOUNTER_DIRECTOR_TEST_FAIL: %s" % failure)
        quit(1)


func _test_sector_catalog() -> void:
    var director := DIRECTOR_SCRIPT.new()
    for index in range(3):
        var sector: Dictionary = director.get_sector(index)
        _expect(sector.size() == 4, "sector descriptor must have exactly the four public fields")
        _expect(sector["name"] == SECTOR_NAMES[index], "sector names must be stable")
        _expect(sector["accent"] is Color and sector["ambient"] is Color, "sector palette fields must be colors")
        _expect(sector["sky_rotation"] is float, "sky rotation must be a float")
        var ambient: Color = sector["ambient"]
        _expect(maxf(ambient.r, maxf(ambient.g, ambient.b)) < 0.2, "ambient palette must remain dark enough for foreground contrast")
    _expect(director.get_sector(-999) == director.get_sector(0), "negative sector indices clamp to the first sector")
    _expect(director.get_sector(999) == director.get_sector(2), "large sector indices clamp to the final sector")
    _expect(director.wave_number == 0, "reading sector metadata must not consume waves")


func _test_wave_bounds() -> void:
    for sector_index in range(3):
        var director := DIRECTOR_SCRIPT.new()
        var seen_archetypes: Dictionary = {}
        var seen_heavy_archetypes: Dictionary = {}
        var seen_formations: Dictionary = {}
        for index in range(100):
            var wave: Dictionary = director.next_wave(sector_index)
            var entries: Array = wave["entries"]
            var formation_index := index % EXPECTED_COUNTS.size()
            _expect(wave.size() == 4, "wave descriptor must have exactly the four public fields")
            _expect(int(wave["number"]) == index + 1, "wave numbering must increment once per plan")
            _expect(wave["name"] == FORMATION_NAMES[formation_index], "formation cycle must be deterministic")
            _expect(entries.size() == EXPECTED_COUNTS[formation_index], "formation must have its expected entry count")
            _expect(entries.size() >= 1 and entries.size() <= 3, "each wave must contain one to three enemies")
            _expect(float(wave["interval_scale"]) >= float(entries.size()), "wave timing must compensate for simultaneous spawn density")
            seen_formations[wave["name"]] = true
            for entry in entries:
                _expect(entry is Dictionary and entry.size() == 3, "each entry must have exactly the three public fields")
                _expect(entry["pool_kind"] in ["scout", "heavy"], "entry must use an existing ordinary-enemy pool")
                _expect(entry["archetype"] in ["standard", "interceptor", "bomber"], "entry archetype must be supported")
                _expect(entry["position"] is Vector3, "entry position must be Vector3")
                var position_value: Vector3 = entry["position"]
                _expect(absf(position_value.x) <= 6.5, "spawn X must remain within the safe visible corridor")
                _expect(position_value.z >= -13.0 and position_value.z <= -11.2, "spawn Z must remain inside the offscreen entry band")
                _expect(is_zero_approx(position_value.y), "enemy entry must preserve the gameplay collision plane")
                if entry["archetype"] != "standard":
                    _expect(entry["pool_kind"] == "heavy" if entry["archetype"] == "bomber" else entry["pool_kind"] == "scout", "special archetype must match its reusable pool family")
                seen_archetypes[entry["archetype"]] = true
                if entry["pool_kind"] == "heavy":
                    seen_heavy_archetypes[entry["archetype"]] = true
            if index == 0:
                _expect(entries[0]["pool_kind"] == "scout" and entries[0]["archetype"] == "standard", "first wave must ease in with one ordinary scout")
            if index == 1:
                _expect(_has_archetype(entries, "interceptor"), "second wave must introduce the interceptor")
            if index == 3:
                _expect(_has_archetype(entries, "bomber"), "first escort wave must introduce the bomber")
        _expect(seen_archetypes.size() == 3, "every sector must expose all three archetypes")
        _expect(seen_formations.size() == 4, "every sector must expose all four formations")
        _expect(seen_heavy_archetypes.has("standard") and seen_heavy_archetypes.has("bomber"), "every sector must keep both original heavy and new bomber in its escort rotation")


func _test_reset_and_independent_data() -> void:
    var director := DIRECTOR_SCRIPT.new()
    var first: Dictionary = director.next_wave(0)
    var expected_first := first.duplicate(true)
    director.next_wave(2)
    director.reset()
    _expect(director.wave_number == 0, "reset must clear progression")
    _expect(director.next_wave(0) == expected_first, "reset must reproduce the first plan exactly")
    first["number"] = -1
    first["name"] = "mutated"
    first["entries"][0]["pool_kind"] = "boss"
    first["entries"][0]["position"] = Vector3(999.0, 999.0, 999.0)
    first["entries"].append({"unexpected": true})
    director.reset()
    _expect(director.next_wave(0) == expected_first, "mutating a returned nested plan must not mutate later plans")
    var sector: Dictionary = director.get_sector(1)
    sector["name"] = "mutated"
    sector["accent"] = Color.WHITE
    sector["ambient"] = Color.WHITE
    sector["sky_rotation"] = 99.0
    sector["new_key"] = true
    var fresh_sector: Dictionary = director.get_sector(1)
    _expect(fresh_sector["name"] == SECTOR_NAMES[1] and fresh_sector.size() == 4, "returned sector dictionaries must not expose the catalog")
    _expect(fresh_sector["accent"] != Color.WHITE and fresh_sector["ambient"] != Color.WHITE, "sector colors must remain isolated")
    _expect(is_equal_approx(float(fresh_sector["sky_rotation"]), 0.35), "sector transform must remain isolated")


func _test_sector_diversity_and_clamping() -> void:
    var first := DIRECTOR_SCRIPT.new()
    var second := DIRECTOR_SCRIPT.new()
    var third := DIRECTOR_SCRIPT.new()
    var first_plan: Dictionary = first.next_wave(0)
    var second_plan: Dictionary = second.next_wave(1)
    var third_plan: Dictionary = third.next_wave(2)
    _expect(first_plan["entries"] != second_plan["entries"] and second_plan["entries"] != third_plan["entries"], "sector layouts must have distinct entry positions")
    for index in range(16):
        first.reset()
        second.reset()
        for wave_index in range(index + 1):
            first_plan = first.next_wave(-50)
            second_plan = second.next_wave(0)
        _expect(first_plan == second_plan, "negative wave sector indices must clamp deterministically")
        first.reset()
        second.reset()
        for wave_index in range(index + 1):
            first_plan = first.next_wave(50)
            second_plan = second.next_wave(2)
        _expect(first_plan == second_plan, "large wave sector indices must clamp deterministically")


func _has_archetype(entries: Array, archetype: String) -> bool:
    for entry in entries:
        if entry["archetype"] == archetype:
            return true
    return false


func _expect(condition: bool, message: String) -> void:
    assertions += 1
    if not condition and failures.size() < 20:
        failures.append(message)

extends RefCounted

# Immutable firing recipes; main owns pool capacity, emitter placement and damage.
# Offsets are local to the named emitter. Positive speed travels toward negative Z.
const MAX_VOLLEY := 100
const MAX_RANK := 5
const NORMAL_MAIN_COUNTS: Array[int] = [4, 8, 12, 20, 28]
const RANK_NAMES: Array[String] = ["雙翼脈衝", "裂光陣列", "四翼火網", "雷光掃射", "天穹彈幕"]
const WING_OFFSETS: Array[Vector3] = [
    Vector3(-2.2, 0.0, 0.5),
    Vector3(2.2, 0.0, 0.5),
    Vector3(-3.8, 0.0, 1.2),
    Vector3(3.8, 0.0, 1.2),
]


func get_wing_count(rank: int) -> int:
    return 2 if clampi(rank, 1, MAX_RANK) < 3 else 4


func get_wing_offset(index: int) -> Vector3:
    return WING_OFFSETS[clampi(index, 0, WING_OFFSETS.size() - 1)]


func get_profile(rank: int, overdrive: bool) -> Dictionary:
    var safe_rank := clampi(rank, 1, MAX_RANK)
    var wing_count := get_wing_count(safe_rank)
    var wing_shots := 10 if overdrive else 3
    var main_count := MAX_VOLLEY - wing_count * wing_shots if overdrive else NORMAL_MAIN_COUNTS[safe_rank - 1]
    return {
        "name": "雷霆超載" if overdrive else RANK_NAMES[safe_rank - 1],
        "main_count": main_count,
        "wing_count": wing_count,
        "wing_shots": wing_shots,
        "interval": 0.20 if overdrive else 0.16,
        "total": main_count + wing_count * wing_shots,
    }


func get_shots(rank: int, overdrive: bool) -> Array[Dictionary]:
    var profile := get_profile(rank, overdrive)
    var shots: Array[Dictionary] = []
    var main_columns := int(profile["main_count"]) / 4
    var main_spread := 9.0 if overdrive else 5.0
    for row in range(4):
        var row_progress := float(row) / 3.0
        for column in range(main_columns):
            var lateral := _fan_position(column, main_columns)
            shots.append(_shot(
                -1,
                Vector3(lateral * 1.2, 0.0, -1.5 - row_progress * 0.8),
                lateral * main_spread,
                (34.0 if overdrive else 32.0) + row_progress * 2.0
            ))

    var wing_rows := 2 if overdrive else 1
    var wing_columns := int(profile["wing_shots"]) / wing_rows
    var wing_spread := 4.0 if overdrive else 2.5
    for wing in range(int(profile["wing_count"])):
        for row in range(wing_rows):
            for column in range(wing_columns):
                var lateral := _fan_position(column, wing_columns)
                shots.append(_shot(
                    wing,
                    Vector3(lateral * 0.36, 0.0, -0.65 - float(row) * 0.3),
                    lateral * wing_spread,
                    (34.0 if overdrive else 32.0) + float(row)
                ))
    return shots


func _fan_position(index: int, count: int) -> float:
    return 0.0 if count <= 1 else float(index) * 2.0 / float(count - 1) - 1.0


func _shot(emitter: int, offset: Vector3, velocity_x: float, speed: float) -> Dictionary:
    return {"emitter": emitter, "offset": offset, "velocity_x": velocity_x, "speed": speed}

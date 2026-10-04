extends RefCounted

# Pure encounter descriptions: the scene owns activation, capacity checks and timing.
# A returned plan is independent of both this catalog and every previous plan.
const SECTORS: Array[Dictionary] = [
    {
        "name": "霓虹前線",
        "accent": Color("44dce8"),
        "ambient": Color("061827"),
        "sky_rotation": 0.0,
    },
    {
        "name": "琥珀殘骸帶",
        "accent": Color("ffc16b"),
        "ambient": Color("21150f"),
        "sky_rotation": 0.35,
    },
    {
        "name": "紫電核心",
        "accent": Color("d299ff"),
        "ambient": Color("160d28"),
        "sky_rotation": -0.35,
    },
]
const FORMATION_NAMES: Array[String] = ["巡邏先鋒", "雙翼攔截", "三角突擊", "重裝護航"]

var wave_number := 0


func reset() -> void:
    wave_number = 0


func get_sector(index: int) -> Dictionary:
    return SECTORS[clampi(index, 0, SECTORS.size() - 1)].duplicate(true)


func next_wave(sector_index: int) -> Dictionary:
    var sector := clampi(sector_index, 0, SECTORS.size() - 1)
    wave_number += 1
    var formation := (wave_number - 1) % FORMATION_NAMES.size()
    var cycle := (wave_number - 1) / FORMATION_NAMES.size()
    var center_x := float((cycle + sector) % 3 - 1) * 1.4
    var spacing := 2.0 + float(sector) * 0.4
    var mirror := -1.0 if (wave_number + sector) % 2 == 0 else 1.0
    var entries: Array[Dictionary] = []

    match formation:
        0:
            entries.append(_entry("scout", "standard", center_x, -11.25))
        1:
            entries.append(_entry("scout", "interceptor", center_x - spacing * mirror, -11.25))
            entries.append(_entry("scout", "standard", center_x + spacing * mirror, -12.4))
        2:
            entries.append(_entry("scout", "interceptor", center_x, -11.25))
            entries.append(_entry("scout", "standard", center_x - spacing, -12.8))
            entries.append(_entry("scout", "interceptor" if sector > 0 else "standard", center_x + spacing, -12.8))
        3:
            entries.append(_entry("heavy", "bomber" if cycle % 2 == 0 else "standard", center_x, -12.8))
            entries.append(_entry("scout", "interceptor" if sector > 1 else "standard", center_x - spacing, -11.25))
            entries.append(_entry("scout", "standard", center_x + spacing, -11.25))

    return {
        "number": wave_number,
        "name": FORMATION_NAMES[formation],
        "entries": entries,
        # Preserve average pressure when several enemies arrive together.
        "interval_scale": float(entries.size()) * 1.1,
    }


func _entry(pool_kind: String, archetype: String, x: float, z: float) -> Dictionary:
    return {
        "pool_kind": pool_kind,
        "archetype": archetype,
        "position": Vector3(x, 0.0, z),
    }

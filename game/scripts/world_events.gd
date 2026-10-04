extends Node3D

# Owner-driven, fixed-pool world events. No autonomous timers/process callbacks.
# Collision is an END-OF-STEP sample: a hitch that skips a whole active window
# never retroactively damages the player. A sampled wave reports at most once.
const CAPACITY := 3
const FIRST_WARNING := 8.0
const WAVE_INTERVAL := 16.0
const WARNING_DURATION := 2.2
const ACTIVE_DURATION := 1.6
const LANE_HALF_WIDTH := 1.5
const LANE_MIN_Z := 0.5
const LANE_MAX_Z := 10.2
const BEACON_SPEED := 2.8
const BEACON_LIFETIME := 16.0
const BEACON_EXIT_Z := 12.5
const COLLECTION_RADIUS := 1.1
# Saturation is idle and prevents integer/transform overflow on invalidly huge
# but finite caller steps. This is over 694 days of continuous world time.
const MAX_CLOCK := 60_000_000.0
const LANE_X := [-7.0, 0.0, 7.0]
const LANE_LABEL := ["左", "中央", "右"]

class BeaconSlot:
    extends RefCounted

    var root: Node3D
    var body: MeshInstance3D
    var ring: MeshInstance3D
    var core: MeshInstance3D
    var active := false
    var age := 0.0
    var index := 0


var _lanes: Array[Node3D] = []
var _beacons: Array[BeaconSlot] = []
var _lane_material: StandardMaterial3D
var _beacon_material: StandardMaterial3D
var _clock := 0.0
var _serial := -1
var _reported_serial := -1
var _phase := "idle"
var _lane_index := -1
var _collected := 0
var _beacon_batches := 0
var _active_beacons := 0
var _nodes := 0
var _enabled := true
var _cleared := false
var _motion_enabled := true


func _ready() -> void:
    setup()


func setup() -> void:
    if not _lanes.is_empty():
        return
    var stripe := BoxMesh.new()
    stripe.size = Vector3(LANE_HALF_WIDTH * 2.0, 0.025, LANE_MAX_Z - LANE_MIN_Z)
    var ring := TorusMesh.new()
    ring.inner_radius = 0.92
    ring.outer_radius = 1.0
    ring.rings = 24
    ring.ring_segments = 6
    var pod := CylinderMesh.new()
    pod.top_radius = 0.12
    pod.bottom_radius = 0.28
    pod.height = 0.45
    pod.radial_segments = 12
    var core := SphereMesh.new()
    core.radius = 0.13
    core.height = 0.26
    core.radial_segments = 12
    core.rings = 6
    _lane_material = _material(Color(1.0, 0.67, 0.15, 0.24), true)
    _beacon_material = _material(Color(0.13, 0.91, 1.0, 1.0), false)
    var core_material := _material(Color(0.86, 1.0, 1.0, 1.0), false)
    for index in range(CAPACITY):
        var lane := Node3D.new()
        lane.name = "PulseLane_%d" % index
        lane.position.x = LANE_X[index]
        lane.visible = false
        add_child(lane)
        var deck := _renderer("Stripe", stripe, _lane_material)
        deck.position = Vector3(0.0, -0.035, (LANE_MIN_Z + LANE_MAX_Z) * 0.5)
        lane.add_child(deck)
        for ring_index in range(2):
            var marker := _renderer("WarningRing_%d" % ring_index, ring, _lane_material)
            marker.position = Vector3(0.0, 0.015, 1.5 if ring_index == 0 else 9.2)
            marker.scale = Vector3(0.8, 0.25, 0.8)
            lane.add_child(marker)
        _lanes.append(lane)
        var slot := BeaconSlot.new()
        slot.index = index
        slot.root = Node3D.new()
        slot.root.name = "RescueBeacon_%d" % index
        slot.root.visible = false
        add_child(slot.root)
        slot.body = _renderer("Pod", pod, _beacon_material)
        slot.root.add_child(slot.body)
        slot.ring = _renderer("Ring", ring, _beacon_material)
        slot.ring.scale = Vector3(0.52, 0.22, 0.52)
        slot.root.add_child(slot.ring)
        slot.core = _renderer("Core", core, core_material)
        slot.root.add_child(slot.core)
        _beacons.append(slot)
    _nodes = 1 + CAPACITY * 8


func _material(color: Color, transparent: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    if transparent:
        material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    return material


func _renderer(renderer_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
    var renderer := MeshInstance3D.new()
    renderer.name = renderer_name
    renderer.mesh = mesh
    renderer.material_override = material
    renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    return renderer


func reset() -> void:
    setup()
    _clock = 0.0
    _serial = -1
    _reported_serial = -1
    _phase = "idle"
    _lane_index = -1
    _collected = 0
    _beacon_batches = 0
    _enabled = true
    _cleared = false
    _release_all_beacons()
    _hide_lanes()


func spawn_beacons() -> bool:
    # No lazy allocations here: setup/ready is the sole prewarm path.
    if _beacons.size() != CAPACITY or _cleared or not _enabled or _active_beacons != 0:
        return false
    for slot in _beacons:
        slot.active = true
        slot.age = 0.0
        slot.root.position = Vector3(LANE_X[slot.index], 0.25, -9.0 - float(slot.index) * 4.0)
        slot.root.rotation = Vector3.ZERO
        slot.root.scale = Vector3.ONE
        slot.root.visible = true
        _render_beacon(slot)
    _active_beacons = CAPACITY
    _beacon_batches += 1
    return true


func advance(delta: float, player_position: Vector3, enabled: bool = true) -> Dictionary:
    var result := {"damage": 0, "beacons": 0, "warning": ""}
    if _lanes.is_empty() or _cleared:
        return result
    _enabled = enabled
    if not enabled:
        _hide_lanes()
        for slot in _beacons:
            slot.root.visible = false
        return result
    # Invalid steps may resume visibility but never move, collect or damage.
    if not is_finite(delta) or delta < 0.0:
        _render_lanes()
        for slot in _beacons:
            slot.root.visible = slot.active
        return result
    var step := minf(delta, MAX_CLOCK)
    _clock = minf(MAX_CLOCK, _clock + step)
    _update_phase()
    _render_lanes()
    if _phase == "warning":
        result["warning"] = "%s航道即將放電：換道躲避" % LANE_LABEL[_lane_index]
    elif _phase == "active":
        result["warning"] = "%s航道放電中" % LANE_LABEL[_lane_index]
        if player_position.is_finite() and _serial != _reported_serial and _inside_lane(player_position):
            _reported_serial = _serial
            result["damage"] = 1
    for slot in _beacons:
        if not slot.active:
            continue
        slot.age = minf(BEACON_LIFETIME, slot.age + step)
        if slot.age >= BEACON_LIFETIME:
            _release_beacon(slot)
            continue
        slot.root.position.z += BEACON_SPEED * step
        if slot.root.position.z > BEACON_EXIT_Z:
            _release_beacon(slot)
            continue
        if player_position.is_finite() and slot.root.position.distance_squared_to(player_position) <= COLLECTION_RADIUS * COLLECTION_RADIUS:
            _release_beacon(slot)
            _collected += 1
            result["beacons"] += 1
        else:
            slot.root.visible = true
            _render_beacon(slot)
    return result


func _inside_lane(player_position: Vector3) -> bool:
    return absf(player_position.x - float(LANE_X[_lane_index])) <= LANE_HALF_WIDTH and player_position.z >= LANE_MIN_Z and player_position.z <= LANE_MAX_Z


func _update_phase() -> void:
    if _clock < FIRST_WARNING:
        _serial = -1
        _lane_index = -1
        _phase = "idle"
        return
    _serial = int(floor((_clock - FIRST_WARNING) / WAVE_INTERVAL))
    var warning_start := FIRST_WARNING + float(_serial) * WAVE_INTERVAL
    var active_start := warning_start + WARNING_DURATION
    if _clock < active_start:
        _phase = "warning"
    elif _clock < active_start + ACTIVE_DURATION:
        _phase = "active"
    else:
        _phase = "idle"
    _lane_index = _serial % CAPACITY if _phase != "idle" else -1


func _render_lanes() -> void:
    _hide_lanes()
    if not _enabled or _cleared or _lane_index < 0:
        return
    var lane: Node3D = _lanes[_lane_index]
    lane.visible = true
    var pulse := 0.5 + 0.5 * sin(_clock * 9.0) if _motion_enabled else 0.5
    var color := Color(1.0, 0.67, 0.15, 0.19 + pulse * 0.09)
    if _phase == "active":
        color = Color(1.0, 0.14, 0.22, 0.25 + pulse * 0.11)
    _lane_material.albedo_color = color
    for index in range(1, 3):
        var marker := lane.get_child(index) as MeshInstance3D
        var radius := 0.72 + pulse * 0.16
        marker.scale = Vector3(radius, 0.25, radius)


func _render_beacon(slot: BeaconSlot) -> void:
    var visual_age := slot.age if _motion_enabled else 0.0
    slot.body.position.y = 0.06 + sin(visual_age * 4.0 + float(slot.index)) * 0.07 if _motion_enabled else 0.06
    slot.body.rotation.y = visual_age * 2.0
    slot.core.position.y = slot.body.position.y + 0.23
    var radius := 0.52 + 0.04 * sin(visual_age * 6.0) if _motion_enabled else 0.52
    slot.ring.scale = Vector3(radius, 0.22, radius)


func set_motion_enabled(enabled: bool) -> void:
    _motion_enabled = enabled
    if not _lanes.is_empty():
        _render_lanes()
        for slot in _beacons:
            if slot.active:
                _render_beacon(slot)


func _hide_lanes() -> void:
    for lane in _lanes:
        lane.visible = false


func _release_beacon(slot: BeaconSlot) -> void:
    if slot.active:
        _active_beacons -= 1
    slot.active = false
    slot.age = 0.0
    slot.root.visible = false


func _release_all_beacons() -> void:
    for slot in _beacons:
        _release_beacon(slot)
    _active_beacons = 0


func clear() -> void:
    _cleared = true
    _phase = "idle"
    _lane_index = -1
    _release_all_beacons()
    _hide_lanes()


func get_stats() -> Dictionary:
    return {"capacity": CAPACITY, "active": _active_beacons,
        "hazard_phase": _phase, "hazard_active": int(_enabled and not _cleared and _phase == "active"),
        "hazard_lane": _lane_index, "clock": _clock, "serial": _serial,
        "nodes": _nodes, "collected": _collected, "beacon_batches": _beacon_batches,
        "enabled": _enabled, "cleared": _cleared}

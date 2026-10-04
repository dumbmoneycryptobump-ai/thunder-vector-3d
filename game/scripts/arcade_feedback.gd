extends Node3D

# Cosmetic only. The owner advances this module, including while play is paused.
const CAPACITY := 24
const SPARKS_PER_SLOT := 6
const LIFETIME := 0.32
const SHAKE_DURATION := 0.15
const MAX_CAMERA_OFFSET := 0.07

class PulseSlot:
    extends RefCounted

    var root: Node3D
    var ring: MeshInstance3D
    var sparks: Array[MeshInstance3D] = []
    var material: StandardMaterial3D
    var active := false
    var age := 0.0
    var sequence := 0
    var strength := 1.0
    var color := Color.WHITE


var _slots: Array[PulseSlot] = []
var _camera: Camera3D
var _base_h_offset := 0.0
var _base_v_offset := 0.0
var _motion_enabled := true
var _shake_remaining := 0.0
var _shake_age := 0.0
var _shake_strength := 0.0
var _active := 0
var _sequence := 0
var _reused := 0
var _overflow := 0


func _ready() -> void:
    _prewarm()


func _exit_tree() -> void:
    clear()


func setup(camera: Camera3D) -> void:
    _restore_camera()
    _camera = camera
    if is_instance_valid(_camera):
        _base_h_offset = _camera.h_offset
        _base_v_offset = _camera.v_offset
    _shake_remaining = 0.0
    _shake_age = 0.0
    _shake_strength = 0.0
    _prewarm()


func _prewarm() -> void:
    if not _slots.is_empty():
        return
    var ring_mesh := TorusMesh.new()
    ring_mesh.inner_radius = 0.94
    ring_mesh.outer_radius = 1.0
    ring_mesh.rings = 24
    ring_mesh.ring_segments = 6
    var spark_mesh := BoxMesh.new()
    spark_mesh.size = Vector3(0.045, 0.025, 0.22)
    for index in range(CAPACITY):
        var slot := PulseSlot.new()
        slot.root = Node3D.new()
        slot.root.name = "ArcadePulse_%02d" % index
        slot.root.visible = false
        add_child(slot.root)
        slot.material = StandardMaterial3D.new()
        slot.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        slot.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        slot.material.cull_mode = BaseMaterial3D.CULL_DISABLED
        slot.material.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
        slot.ring = MeshInstance3D.new()
        slot.ring.name = "Ring"
        slot.ring.mesh = ring_mesh
        slot.ring.material_override = slot.material
        slot.ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        slot.root.add_child(slot.ring)
        for spark_index in range(SPARKS_PER_SLOT):
            var spark := MeshInstance3D.new()
            spark.name = "Spark_%d" % spark_index
            spark.mesh = spark_mesh
            spark.material_override = slot.material
            spark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            slot.root.add_child(spark)
            slot.sparks.append(spark)
        _slots.append(slot)


func pulse(position_value: Vector3, color: Color, strength: float = 1.0) -> void:
    if _slots.is_empty() or not position_value.is_finite() or not is_finite(strength) or strength <= 0.0:
        return
    var selected: PulseSlot = null
    for slot in _slots:
        if not slot.active:
            selected = slot
            break
        if selected == null or slot.sequence < selected.sequence:
            selected = slot
    if selected.active:
        _overflow += 1
    else:
        _active += 1
    _sequence += 1
    _reused += 1
    selected.active = true
    selected.sequence = _sequence
    selected.age = 0.0
    selected.strength = clampf(strength, 0.0, 2.0)
    selected.color = color.clamp()
    selected.root.position = position_value + Vector3(0.0, 0.07, 0.0)
    selected.root.rotation = Vector3.ZERO
    selected.root.scale = Vector3.ONE
    selected.root.visible = true
    _render_slot(selected)
    if _motion_enabled:
        _shake_remaining = SHAKE_DURATION
        _shake_age = 0.0
        _shake_strength = maxf(_shake_strength, selected.strength)


func advance(delta: float) -> void:
    var step := maxf(delta, 0.0) if is_finite(delta) else 0.0
    for slot in _slots:
        if not slot.active:
            continue
        slot.age += step
        if slot.age >= LIFETIME:
            _release_slot(slot)
        else:
            _render_slot(slot)
    _advance_camera(step)


func _render_slot(slot: PulseSlot) -> void:
    var progress := clampf(slot.age / LIFETIME, 0.0, 1.0)
    var eased := 1.0 - (1.0 - progress) * (1.0 - progress)
    var max_radius := minf(1.1 * slot.strength, 2.0)
    var radius := lerpf(0.14 * slot.strength, max_radius, eased)
    slot.ring.scale = Vector3(radius, 0.45, radius)
    slot.material.albedo_color = Color(slot.color.r, slot.color.g, slot.color.b, slot.color.a * 0.72 * (1.0 - progress))
    var spark_distance := lerpf(0.15, minf(1.35 * slot.strength, 2.2), eased)
    for index in range(SPARKS_PER_SLOT):
        var angle := float(index) * TAU / float(SPARKS_PER_SLOT)
        var spark: MeshInstance3D = slot.sparks[index]
        spark.position = Vector3(sin(angle) * spark_distance, 0.0, cos(angle) * spark_distance)
        spark.rotation = Vector3(0.0, angle, 0.0)
        spark.scale = Vector3(1.0, 1.0, lerpf(1.6, 0.25, progress))


func _release_slot(slot: PulseSlot) -> void:
    if not slot.active:
        return
    slot.active = false
    slot.age = 0.0
    slot.root.visible = false
    slot.material.albedo_color.a = 0.0
    _active -= 1


func _advance_camera(delta: float) -> void:
    if not _motion_enabled or _shake_remaining <= 0.0:
        _restore_camera()
        return
    _shake_remaining = maxf(0.0, _shake_remaining - delta)
    _shake_age += delta
    if _shake_remaining <= 0.0:
        _shake_strength = 0.0
        _restore_camera()
        return
    if is_instance_valid(_camera):
        var amplitude := MAX_CAMERA_OFFSET * clampf(_shake_strength / 2.0, 0.0, 1.0) * (_shake_remaining / SHAKE_DURATION)
        _camera.h_offset = _base_h_offset + sin(_shake_age * 96.0) * amplitude
        _camera.v_offset = _base_v_offset + sin(_shake_age * 121.0) * amplitude


func set_motion_enabled(enabled: bool) -> void:
    _motion_enabled = enabled
    if not enabled:
        _shake_remaining = 0.0
        _shake_age = 0.0
        _shake_strength = 0.0
        _restore_camera()


func _restore_camera() -> void:
    if is_instance_valid(_camera):
        _camera.h_offset = _base_h_offset
        _camera.v_offset = _base_v_offset


func clear() -> void:
    for slot in _slots:
        _release_slot(slot)
    _shake_remaining = 0.0
    _shake_age = 0.0
    _shake_strength = 0.0
    _restore_camera()


func get_stats() -> Dictionary:
    # Cumulative accepted-pulse/recycle counts intentionally survive clear/restart.
    return {"capacity": CAPACITY, "active": _active, "reused": _reused, "overflow": _overflow}

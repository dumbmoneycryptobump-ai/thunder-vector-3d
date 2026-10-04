extends Node

# Short-lived presentation nodes stay allocated for the whole game session.
# The owner advances these from _process so pause/game-over do not strand effects.
const EFFECT_CAPACITY := 32
const AUDIO_CAPACITY := 16
const EFFECT_LIFETIME := 0.42

class EffectSlot:
    extends RefCounted

    var root: Node3D
    var sphere: MeshInstance3D
    var material: StandardMaterial3D
    var light: OmniLight3D
    var active := false
    var age := 0.0
    var sequence := 0
    var color := Color.WHITE
    var scale_factor := 1.0


class AudioSlot:
    extends RefCounted

    var player: AudioStreamPlayer
    var active := false
    var sequence := 0


var _effects: Array[EffectSlot] = []
var _audio: Array[AudioSlot] = []
var _sequence := 0
var _effects_active := 0
var _audio_active := 0
var _effects_reused := 0
var _audio_reused := 0
var _effects_overflow := 0
var _audio_overflow := 0
var _is_shutdown := false


func _ready() -> void:
    if _is_shutdown:
        return
    var shared_sphere := SphereMesh.new()
    shared_sphere.radius = 1.0
    shared_sphere.height = 2.0
    shared_sphere.radial_segments = 20
    shared_sphere.rings = 10
    for index in range(EFFECT_CAPACITY):
        var slot := EffectSlot.new()
        slot.root = Node3D.new()
        slot.root.name = "PooledExplosion_%02d" % index
        slot.root.visible = false
        add_child(slot.root)

        slot.material = StandardMaterial3D.new()
        slot.material.metallic = 0.62
        slot.material.roughness = 0.24
        slot.material.emission_enabled = true
        slot.material.emission_energy_multiplier = 6.0
        slot.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        slot.sphere = MeshInstance3D.new()
        slot.sphere.mesh = shared_sphere
        slot.sphere.material_override = slot.material
        slot.root.add_child(slot.sphere)

        slot.light = OmniLight3D.new()
        slot.light.light_energy = 0.0
        slot.root.add_child(slot.light)
        _effects.append(slot)

    for index in range(AUDIO_CAPACITY):
        var slot := AudioSlot.new()
        slot.player = AudioStreamPlayer.new()
        slot.player.name = "PooledSFX_%02d" % index
        if AudioServer.get_bus_index(&"SFX") >= 0:
            slot.player.bus = &"SFX"
        add_child(slot.player)
        _audio.append(slot)


func _exit_tree() -> void:
    shutdown()


func spawn_explosion(position_value: Vector3, color: Color, scale_factor: float = 1.0) -> void:
    if _is_shutdown or _effects.is_empty():
        return
    var selected: EffectSlot = null
    for slot in _effects:
        if not slot.active:
            selected = slot
            break
        if selected == null or slot.sequence < selected.sequence:
            selected = slot

    if selected.active:
        _effects_overflow += 1
    else:
        _effects_active += 1
        selected.root.add_to_group(&"fx")
    _sequence += 1
    _effects_reused += 1
    selected.active = true
    selected.sequence = _sequence
    selected.age = 0.0
    selected.color = color
    selected.scale_factor = scale_factor
    selected.root.position = position_value
    selected.root.rotation = Vector3.ZERO
    selected.root.scale = Vector3.ONE
    selected.root.visible = true
    selected.material.emission = color
    selected.light.light_color = color
    selected.light.omni_range = 4.0 * scale_factor
    _render_effect(selected)


func play_sfx(stream: AudioStream, volume_db: float = -6.0) -> void:
    if _is_shutdown or stream == null or _audio.is_empty() or DisplayServer.get_name() == "headless":
        return
    _release_finished_audio()
    var selected: AudioSlot = null
    for slot in _audio:
        if not slot.active:
            selected = slot
            break
        if selected == null or slot.sequence < selected.sequence:
            selected = slot

    if selected.active:
        _audio_overflow += 1
        selected.player.stop()
    else:
        _audio_active += 1
    _sequence += 1
    _audio_reused += 1
    selected.active = true
    selected.sequence = _sequence
    selected.player.stream = stream
    selected.player.volume_db = volume_db
    selected.player.play()


func advance(delta: float) -> void:
    if _is_shutdown:
        return
    for slot in _effects:
        if not slot.active:
            continue
        slot.age += maxf(delta, 0.0)
        if slot.age >= EFFECT_LIFETIME:
            _release_effect(slot)
        else:
            _render_effect(slot)
    _release_finished_audio()


func _render_effect(slot: EffectSlot) -> void:
    var expansion_time := clampf(slot.age / 0.34, 0.0, 1.0)
    var expansion_weight := 1.0 - (1.0 - expansion_time) * (1.0 - expansion_time)
    # The former mesh radius and tween scale both depended on scale_factor.
    var original_scale := lerpf(1.0, 3.4 * slot.scale_factor, expansion_weight)
    slot.sphere.scale = Vector3.ONE * (0.22 * slot.scale_factor * original_scale)
    var faded_color := Color(slot.color.r, slot.color.g, slot.color.b, 0.0)
    slot.material.albedo_color = slot.color.darkened(0.25).lerp(faded_color, clampf(slot.age / 0.38, 0.0, 1.0))
    slot.light.light_energy = 4.5 * slot.scale_factor * (1.0 - clampf(slot.age / 0.36, 0.0, 1.0))


func _release_effect(slot: EffectSlot) -> void:
    if not slot.active:
        return
    slot.active = false
    slot.root.remove_from_group(&"fx")
    slot.root.visible = false
    slot.light.light_energy = 0.0
    slot.age = 0.0
    _effects_active -= 1


func _release_finished_audio() -> void:
    for slot in _audio:
        if slot.active and not slot.player.playing:
            _release_audio(slot)


func _release_audio(slot: AudioSlot) -> void:
    if not slot.active:
        return
    slot.player.stop()
    slot.player.stream = null
    slot.active = false
    _audio_active -= 1


func clear() -> void:
    for slot in _effects:
        _release_effect(slot)
    for slot in _audio:
        _release_audio(slot)


func shutdown() -> void:
    if _is_shutdown:
        return
    clear()
    _is_shutdown = true


func get_stats() -> Dictionary:
    # Session totals intentionally survive clear()/restart; active/idle are current.
    return {
        "fx": {
            "capacity": EFFECT_CAPACITY,
            "created": _effects.size(),
            "active": _effects_active,
            "idle": _effects.size() - _effects_active,
            "reused": _effects_reused,
            "overflow": _effects_overflow,
        },
        "audio": {
            "capacity": AUDIO_CAPACITY,
            "created": _audio.size(),
            "active": _audio_active,
            "idle": _audio.size() - _audio_active,
            "reused": _audio_reused,
            "overflow": _audio_overflow,
        },
        "shutdown": _is_shutdown,
    }

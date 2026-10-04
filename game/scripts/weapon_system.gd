extends Node3D

# Gameplay weapons with prewarmed visuals. The owner controls cadence and wingguns.
# Enemy locks include an activation token because pooled nodes can represent new foes.
const MISSILE_CAPACITY := 64
const SEGMENT_CAPACITY := 96
const MISSILE_COUNT := 4
const MISSILE_SPEED := 22.0
const MISSILE_TURN_RATE := 3.2
const MISSILE_LIFETIME := 2.5
const MISSILE_RADIUS := 0.24
const TARGET_RANGE := 26.0
const SPLASH_RADIUS := 1.8
const CHAIN_RANGE := 5.5
const CHAIN_TARGETS := 5
const BEAM_RADIUS := 0.24

class MissileSlot:
    extends RefCounted
    var root: Node3D
    var flame: MeshInstance3D
    var active := false
    var age := 0.0
    var velocity := Vector3.ZERO
    var target_id := 0
    var target_activation_id := 0
    var damage := 4

class SegmentSlot:
    extends RefCounted
    var node: MeshInstance3D
    var active := false
    var age := 0.0
    var lifetime := 0.13
    var width := 0.06

var _game: Node
var _missiles: Array[MissileSlot] = []
var _segments: Array[SegmentSlot] = []
var _box: BoxMesh
var _missile_material: StandardMaterial3D
var _fin_material: StandardMaterial3D
var _flame_material: StandardMaterial3D
var _lightning_material: StandardMaterial3D
var _laser_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _missiles_active := 0
var _segments_active := 0
var _missile_reused := 0
var _segment_reused := 0
var _overflow := 0
var _last_hits := 0
var _total_hits := 0
var _hits_by_mode: Array[int] = [0, 0, 0, 0, 0]
var _shots_by_mode: Array[int] = [0, 0, 0, 0, 0]


func setup(game: Node) -> void:
    if _game != game:
        clear()
    _game = game
    if not _missiles.is_empty():
        return
    _box = BoxMesh.new()
    _box.size = Vector3.ONE
    _missile_material = _material(Color("ed7356"))
    _fin_material = _material(Color("bad3dd"))
    _flame_material = _material(Color("ffe49a"))
    _lightning_material = _material(Color("a3bfff"))
    _laser_material = _material(Color("ef76dc"))
    _core_material = _material(Color("ffe6fb"))
    for index in range(MISSILE_CAPACITY):
        var slot := MissileSlot.new()
        slot.root = Node3D.new()
        slot.root.name = "Missile_%02d" % index
        slot.root.visible = false
        add_child(slot.root)
        _mesh(slot.root, _missile_material, Vector3(0.18, 0.15, 0.6), Vector3.ZERO)
        _mesh(slot.root, _fin_material, Vector3(0.5, 0.06, 0.18), Vector3(0.0, 0.0, 0.13))
        slot.flame = _mesh(slot.root, _flame_material, Vector3(0.1, 0.1, 0.3), Vector3(0.0, 0.0, 0.42))
        _missiles.append(slot)
    for index in range(SEGMENT_CAPACITY):
        var slot := SegmentSlot.new()
        slot.node = _mesh(self, _lightning_material, Vector3.ONE, Vector3.ZERO)
        slot.node.name = "EnergySegment_%02d" % index
        slot.node.visible = false
        _segments.append(slot)


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = color
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _mesh(parent: Node, material: Material, size: Vector3, at: Vector3) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = _box
    instance.material_override = material
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    instance.scale = size
    instance.position = at
    parent.add_child(instance)
    return instance


func get_profile(mode: int, _rank: int) -> Dictionary:
    match mode:
        2:
            return {"name": "追蹤導彈", "interval": 0.32, "projectiles": 4, "description": "四枚追蹤 · 小範圍爆炸"}
        3:
            return {"name": "連鎖閃電", "interval": 0.32, "projectiles": 0, "description": "瞬間連鎖 · 最多五目標"}
        4:
            return {"name": "雙束雷射", "interval": 0.16, "projectiles": 0, "description": "雙束貫穿 · 直線清場"}
    return {"name": "機砲", "interval": 0.16, "projectiles": 0, "description": "機砲與僚機齊射"}


func _can_play() -> bool:
    return is_instance_valid(_game) and _game.is_inside_tree() and not bool(_game.get("is_paused")) and not bool(_game.get("is_game_over"))


func fire(mode: int, origin: Vector3, rank: int) -> bool:
    if not _can_play() or not origin.is_finite() or _missiles.is_empty() or mode < 2 or mode > 4:
        return false
    _last_hits = 0
    match mode:
        2:
            if MISSILE_CAPACITY - _missiles_active < MISSILE_COUNT:
                _overflow += 1
                return false
            _fire_missiles(origin, clampi(rank, 1, 5))
        3:
            var chain := _select_chain(origin)
            var needed := maxi(chain.size(), 1) * 4
            if SEGMENT_CAPACITY - _segments_active < needed:
                _overflow += 1
                return false
            _fire_lightning(origin, chain)
        4:
            if SEGMENT_CAPACITY - _segments_active < 4:
                _overflow += 1
                return false
            _fire_laser(origin)
    _shots_by_mode[mode] += 1
    return true


func _fire_missiles(origin: Vector3, rank: int) -> void:
    var candidates := _candidates(origin, TARGET_RANGE)
    var chosen: Array[int] = []
    for index in range(MISSILE_COUNT):
        var slot := _idle_missile()
        slot.active = true
        slot.age = 0.0
        slot.damage = 4 + rank / 3
        slot.root.position = origin + Vector3(-0.9 + float(index) * 0.6, 0.0, -1.3)
        slot.root.visible = true
        slot.velocity = Vector3(-3.0 + float(index) * 2.0, 0.0, -MISSILE_SPEED).normalized() * MISSILE_SPEED
        slot.target_id = 0
        slot.target_activation_id = 0
        var target := _nearest(candidates, origin, TARGET_RANGE, chosen)
        if target == null:
            target = _nearest(candidates, origin, TARGET_RANGE, [])
        if target != null:
            _lock_target(slot, target)
            chosen.append(target.get_instance_id())
        _orient_missile(slot)
        _missiles_active += 1
        _missile_reused += 1


func _idle_missile() -> MissileSlot:
    for slot in _missiles:
        if not slot.active:
            return slot
    return null


func _lock_target(slot: MissileSlot, target: Node3D) -> void:
    slot.target_id = target.get_instance_id()
    slot.target_activation_id = int(target.get_meta("activation_id", 0))


func _locked_target(slot: MissileSlot) -> Node3D:
    if slot.target_id == 0:
        return null
    var target: Object = instance_from_id(slot.target_id)
    if not is_instance_valid(target) or not target is Node3D:
        return null
    if not _is_target(target) or int(target.get_meta("activation_id", 0)) != slot.target_activation_id:
        return null
    if target.position.z >= slot.root.position.z or target.position.distance_squared_to(slot.root.position) > TARGET_RANGE * TARGET_RANGE:
        return null
    return target as Node3D


func advance(delta: float) -> void:
    if not _can_play() or not is_finite(delta) or delta <= 0.0:
        return
    _last_hits = 0
    for slot in _segments:
        if not slot.active:
            continue
        slot.age += delta
        if slot.age >= slot.lifetime:
            _release_segment(slot)
        else:
            var width := slot.width * (1.0 - 0.55 * slot.age / slot.lifetime)
            slot.node.scale.x = width
            slot.node.scale.y = width
    # One group query per tick; callbacks can release targets, so still revalidate.
    var targets: Array[Node3D] = []
    if _missiles_active > 0:
        targets = _all_targets()
    for slot in _missiles:
        if not slot.active:
            continue
        var step := minf(delta, MISSILE_LIFETIME - slot.age)
        var from := slot.root.position
        var target := _locked_target(slot)
        if target == null:
            slot.target_id = 0
            slot.target_activation_id = 0
            target = _nearest(_forward_targets(targets, from, TARGET_RANGE), from, TARGET_RANGE, [])
            if target != null:
                _lock_target(slot, target)
        if target != null:
            var aim: Vector3 = target.position - from
            aim.y = 0.0
            if aim.length_squared() > 0.000001:
                var current_angle := atan2(slot.velocity.x, -slot.velocity.z)
                var desired_angle := atan2(aim.x, -aim.z)
                var turn := clampf(wrapf(desired_angle - current_angle, -PI, PI), -MISSILE_TURN_RATE * step, MISSILE_TURN_RATE * step)
                var heading := current_angle + turn
                slot.velocity = Vector3(sin(heading), 0.0, -cos(heading)) * MISSILE_SPEED
        var to := from + slot.velocity * step
        var first_hit: Node3D = null
        var first_time := INF
        for enemy in targets:
            if not _is_target(enemy):
                continue
            var hit_time := _sphere_hit_time(from, to, enemy.position, MISSILE_RADIUS + float(enemy.get_meta("radius", 0.8)))
            if hit_time >= 0.0 and hit_time < first_time:
                first_hit = enemy
                first_time = hit_time
        slot.age += step
        if first_hit != null:
            var impact := from.lerp(to, first_time)
            _explode_missile(first_hit, impact, slot.damage)
            _release_missile(slot)
            continue
        slot.root.position = to
        _orient_missile(slot)
        if slot.age >= MISSILE_LIFETIME or absf(to.x) > 32.0 or to.z < -40.0 or to.z > 24.0:
            _release_missile(slot)


func _orient_missile(slot: MissileSlot) -> void:
    slot.root.rotation = Vector3(0.0, atan2(-slot.velocity.x, -slot.velocity.z), 0.0)
    slot.flame.scale = Vector3(0.1, 0.1, 0.3 + 0.05 * sin(slot.age * 70.0))


func _explode_missile(primary: Node3D, impact: Vector3, damage: int) -> void:
    # Snapshot identity/activation before any owner callback can release a pool node.
    var primary_id := primary.get_instance_id()
    var victims: Array[Dictionary] = []
    victims.append(_target_record(primary, damage))
    for enemy in _all_targets():
        if enemy.get_instance_id() != primary_id and enemy.position.distance_squared_to(impact) <= SPLASH_RADIUS * SPLASH_RADIUS:
            victims.append(_target_record(enemy, 2))
    for victim in victims:
        _damage_record(victim, 2)


func _select_chain(origin: Vector3) -> Array[Dictionary]:
    var candidates := _candidates(origin, TARGET_RANGE)
    var chain: Array[Dictionary] = []
    var selected: Array[int] = []
    var from := origin
    for index in range(CHAIN_TARGETS):
        var target := _nearest(candidates, from, 24.0 if index == 0 else CHAIN_RANGE, selected)
        if target == null:
            break
        var record := _target_record(target, 3)
        record["position"] = target.position
        chain.append(record)
        selected.append(target.get_instance_id())
        from = target.position
    return chain


func _fire_lightning(origin: Vector3, chain: Array[Dictionary]) -> void:
    var from := origin + Vector3(0.0, 0.05, -1.0)
    if chain.is_empty():
        _zigzag(from, from + Vector3(0.0, 0.0, -4.0), 0)
        return
    for index in range(chain.size()):
        var to: Vector3 = chain[index]["position"] + Vector3(0.0, 0.05, 0.0)
        _zigzag(from, to, index)
        from = to
    # All visual slots were reserved by fire before any damage can mutate enemies.
    for victim in chain:
        _damage_record(victim, 3)


func _zigzag(from: Vector3, to: Vector3, phase: int) -> void:
    var offset_axis := Vector3(to.z - from.z, 0.0, from.x - to.x).normalized()
    var previous := from
    for index in range(1, 5):
        var point := from.lerp(to, float(index) / 4.0)
        if index < 4:
            point += offset_axis * (0.22 if (index + phase) % 2 == 0 else -0.22)
        _segment(previous, point, 0.065, 0.13, _lightning_material)
        previous = point


func _fire_laser(origin: Vector3) -> void:
    var victims: Array[Dictionary] = []
    # Capsule length is measured from each muzzle, not a radial origin cutoff.
    # Thus the rendered tips and the exact damage volume agree.
    for enemy in _all_targets():
        if enemy.position.z >= origin.z:
            continue
        var hit := false
        for offset in [-0.65, 0.65]:
            var from := origin + Vector3(offset, 0.0, -1.1)
            var to := from + Vector3(0.0, 0.0, -26.0)
            if _sphere_hit_time(from, to, enemy.position, BEAM_RADIUS + float(enemy.get_meta("radius", 0.8))) >= 0.0:
                hit = true
                break
        if hit:
            victims.append(_target_record(enemy, 2))
    for offset in [-0.65, 0.65]:
        var from := origin + Vector3(offset, 0.06, -1.1)
        var to := from + Vector3(0.0, 0.0, -26.0)
        _segment(from, to, 0.16, 0.11, _laser_material)
        _segment(from + Vector3(0.0, 0.03, 0.0), to + Vector3(0.0, 0.03, 0.0), 0.055, 0.11, _core_material)
    for victim in victims:
        _damage_record(victim, 4)


func _segment(from: Vector3, to: Vector3, width: float, lifetime: float, material: Material) -> void:
    for slot in _segments:
        if slot.active:
            continue
        var direction := to - from
        slot.active = true
        slot.age = 0.0
        slot.lifetime = lifetime
        slot.width = width
        slot.node.position = (from + to) * 0.5
        if direction.length_squared() <= 0.000001:
            slot.node.basis = Basis.IDENTITY
        else:
            var unit := direction.normalized()
            var up := Vector3.RIGHT if absf(unit.dot(Vector3.UP)) > 0.99 else Vector3.UP
            slot.node.basis = Basis.looking_at(unit, up)
        slot.node.scale = Vector3(width, width, maxf(direction.length(), 0.01))
        slot.node.material_override = material
        slot.node.visible = true
        _segments_active += 1
        _segment_reused += 1
        return


func _all_targets() -> Array[Node3D]:
    var targets: Array[Node3D] = []
    if not is_instance_valid(_game) or not _game.is_inside_tree():
        return targets
    for candidate in _game.get_tree().get_nodes_in_group("enemy"):
        if candidate is Node3D and _game.is_ancestor_of(candidate) and _is_target(candidate):
            targets.append(candidate)
    return targets


func _is_target(candidate: Node3D) -> bool:
    return is_instance_valid(candidate) and not candidate.is_queued_for_deletion() and candidate.is_in_group("enemy") and int(candidate.get_meta("hp", 1)) > 0


func _candidates(origin: Vector3, reach: float) -> Array[Node3D]:
    return _forward_targets(_all_targets(), origin, reach)


func _forward_targets(targets: Array[Node3D], origin: Vector3, reach: float) -> Array[Node3D]:
    var candidates: Array[Node3D] = []
    for enemy in targets:
        if _is_target(enemy) and enemy.position.z < origin.z and enemy.position.distance_squared_to(origin) <= reach * reach:
            candidates.append(enemy)
    return candidates


func _nearest(candidates: Array[Node3D], from: Vector3, reach: float, excluded: Array) -> Node3D:
    var nearest: Node3D = null
    var distance := reach * reach
    for candidate in candidates:
        if not _is_target(candidate) or candidate.get_instance_id() in excluded:
            continue
        var candidate_distance := candidate.position.distance_squared_to(from)
        if candidate_distance <= distance and (nearest == null or candidate_distance < distance):
            nearest = candidate
            distance = candidate_distance
    return nearest


func _target_record(target: Node3D, damage: int) -> Dictionary:
    return {"id": target.get_instance_id(), "activation_id": int(target.get_meta("activation_id", 0)), "damage": damage}


func _damage_record(record: Dictionary, mode: int) -> void:
    var target: Object = instance_from_id(int(record["id"]))
    if not _can_play() or not is_instance_valid(target) or not target is Node3D:
        return
    if not _is_target(target) or int(target.get_meta("activation_id", 0)) != int(record["activation_id"]):
        return
    _game.call("_damage_enemy", target, int(record["damage"]))
    _last_hits += 1
    _total_hits += 1
    _hits_by_mode[mode] += 1


func _sphere_hit_time(from: Vector3, to: Vector3, center: Vector3, radius: float) -> float:
    var delta := to - from
    var relative := from - center
    var c := relative.length_squared() - radius * radius
    if c <= 0.0:
        return 0.0
    var a := delta.length_squared()
    if a <= 0.0000001:
        return -1.0
    var b := relative.dot(delta)
    var discriminant := b * b - a * c
    if discriminant < 0.0:
        return -1.0
    var hit_time := (-b - sqrt(discriminant)) / a
    return hit_time if hit_time >= 0.0 and hit_time <= 1.0 else -1.0


func _release_missile(slot: MissileSlot) -> void:
    if not slot.active:
        return
    slot.active = false
    slot.age = 0.0
    slot.target_id = 0
    slot.target_activation_id = 0
    slot.velocity = Vector3.ZERO
    slot.root.visible = false
    _missiles_active -= 1


func _release_segment(slot: SegmentSlot) -> void:
    if not slot.active:
        return
    slot.active = false
    slot.age = 0.0
    slot.node.visible = false
    _segments_active -= 1


func clear() -> void:
    for slot in _missiles:
        _release_missile(slot)
    for slot in _segments:
        _release_segment(slot)
    _last_hits = 0


func get_stats() -> Dictionary:
    # Lifetime counters intentionally survive clear/restart; active state does not.
    return {
        "missile_capacity": MISSILE_CAPACITY, "missiles_active": _missiles_active,
        "segment_capacity": SEGMENT_CAPACITY, "segments_active": _segments_active,
        "missile_reused": _missile_reused, "segment_reused": _segment_reused,
        "overflow": _overflow, "last_hits": _last_hits, "total_hits": _total_hits,
        "hits_by_mode": {2: _hits_by_mode[2], 3: _hits_by_mode[3], 4: _hits_by_mode[4]},
        "shots_by_mode": {2: _shots_by_mode[2], 3: _shots_by_mode[3], 4: _shots_by_mode[4]},
    }


func get_active_missiles() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for index in range(_missiles.size()):
        var slot := _missiles[index]
        if slot.active:
            result.append({"slot": index, "position": slot.root.position, "velocity": slot.velocity,
                "target_id": slot.target_id, "target_activation_id": slot.target_activation_id,
                "age": slot.age, "damage": slot.damage})
    return result

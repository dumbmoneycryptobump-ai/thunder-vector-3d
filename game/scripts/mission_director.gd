extends RefCounted

# Pure offline mission state. The scene owns pause/death gating and all rewards.
# At most four notification dictionaries are retained, regardless of play time.
const EVENT_CAPACITY := 4
const COMPLETE_COOLDOWN := 5.0
const FAILED_COOLDOWN := 3.0
const MISSIONS: Array[Dictionary] = [
    {"id": "kills", "title": "掃蕩先鋒", "description": "消滅 12 架敵機", "metric": "kills", "target": 12, "duration": 40.0, "reward_score": 600, "reward_charge": 15.0},
    {"id": "chain", "title": "連殺王牌", "description": "達成 12 連殺", "metric": "chain", "target": 12, "duration": 45.0, "reward_score": 900, "reward_charge": 20.0},
    {"id": "pickups", "title": "補給航線", "description": "收集 3 個補給", "metric": "pickups", "target": 3, "duration": 60.0, "reward_score": 750, "reward_charge": 25.0},
    {"id": "overdrive", "title": "百發時刻", "description": "啟動 1 次百發超載", "metric": "overdrive", "target": 1, "duration": 45.0, "reward_score": 1000, "reward_charge": 15.0},
    {"id": "elites", "title": "精英獵手", "description": "消滅 4 架攔截機或轟炸機", "metric": "elites", "target": 4, "duration": 60.0, "reward_score": 1200, "reward_charge": 25.0},
    {"id": "survival", "title": "無傷穿越", "description": "連續 20 秒不損失生命", "metric": "survival", "target": 20, "duration": 45.0, "reward_score": 1000, "reward_charge": 25.0},
    {"id": "weapons", "title": "三重火力", "description": "導彈、閃電、雷射各實際開火一次", "metric": "weapons", "target": 3, "duration": 60.0, "reward_score": 1500, "reward_charge": 30.0},
    {"id": "beacons", "title": "救援航道", "description": "回收 3 個救援信標", "metric": "beacons", "target": 3, "duration": 75.0, "reward_score": 1500, "reward_charge": 30.0},
    {"id": "boss", "title": "核心攻堅", "description": "擊破 1 架首領", "metric": "boss", "target": 1, "duration": 90.0, "reward_score": 3000, "reward_charge": 50.0},
]

var _index := 0
var _serial := 0
var _completed := 0
var _phase := "active"
var _progress := 0.0
var _remaining := 0.0
var _weapon_mask := 0
var _events: Array[Dictionary] = []


func _init() -> void:
    reset()


func reset() -> void:
    _events.clear()
    _completed = 0
    _index = 0
    _start_mission()


func advance(delta: float, health_intact: bool = true) -> void:
    if not is_finite(delta) or delta <= 0.0:
        return
    if _phase != "active":
        _remaining = maxf(0.0, _remaining - delta)
        if _remaining <= 0.0:
            _index = (_index + 1) % MISSIONS.size()
            _start_mission()
        # Do not spend old-frame overshoot on a newly displayed objective.
        return
    var spent := minf(delta, _remaining)
    _remaining = maxf(0.0, _remaining - spent)
    if MISSIONS[_index]["metric"] == "survival" and health_intact:
        _add_progress(spent)
    if _phase == "active" and _remaining <= 0.0:
        _finish(false)


func record_kill(elite: bool, boss: bool, chain: int) -> void:
    if _phase != "active":
        return
    match MISSIONS[_index]["metric"]:
        "kills":
            _add_progress(1.0)
        "chain":
            record_chain(chain)
        "elites":
            if elite and not boss:
                _add_progress(1.0)
        "boss":
            if boss:
                _add_progress(1.0)


func record_pickup() -> void:
    _record_unit("pickups")


func record_chain(chain: int) -> void:
    if _phase == "active" and MISSIONS[_index]["metric"] == "chain":
        _progress = float(clampi(chain, 0, int(MISSIONS[_index]["target"])))
        _check_complete()


func record_beacon() -> void:
    _record_unit("beacons")


func record_weapon(mode: int) -> void:
    if _phase != "active" or MISSIONS[_index]["metric"] != "weapons" or mode < 2 or mode > 4:
        return
    _weapon_mask |= 1 << (mode - 2)
    _progress = float((_weapon_mask & 1) + ((_weapon_mask >> 1) & 1) + ((_weapon_mask >> 2) & 1))
    _check_complete()


func record_overdrive() -> void:
    _record_unit("overdrive")


func record_damage() -> void:
    if _phase == "active" and MISSIONS[_index]["metric"] in ["survival", "chain"]:
        _progress = 0.0


func get_state() -> Dictionary:
    var mission: Dictionary = MISSIONS[_index]
    return {
        "id": mission["id"],
        "title": mission["title"],
        "description": mission["description"],
        "metric": mission["metric"],
        "target": mission["target"],
        "progress": _progress,
        "remaining": _remaining,
        "completed": _completed,
        "total": MISSIONS.size(),
        "phase": _phase,
        "serial": _serial,
    }.duplicate(true)


func drain_events() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    for event in _events:
        result.append(event.duplicate(true))
    _events.clear()
    return result


func _record_unit(metric: String) -> void:
    if _phase == "active" and MISSIONS[_index]["metric"] == metric:
        _add_progress(1.0)


func _add_progress(amount: float) -> void:
    _progress = minf(float(MISSIONS[_index]["target"]), _progress + amount)
    _check_complete()


func _check_complete() -> void:
    if _phase == "active" and _progress >= float(MISSIONS[_index]["target"]):
        _finish(true)


func _start_mission() -> void:
    _serial += 1
    _phase = "active"
    _progress = 0.0
    _remaining = float(MISSIONS[_index]["duration"])
    _weapon_mask = 0
    _emit_event("started")


func _finish(success: bool) -> void:
    if _phase != "active":
        return
    _phase = "complete" if success else "failed"
    _remaining = COMPLETE_COOLDOWN if success else FAILED_COOLDOWN
    if success:
        _completed += 1
    _emit_event("completed" if success else "failed")


func _emit_event(kind: String) -> void:
    var mission: Dictionary = MISSIONS[_index]
    if _events.size() >= EVENT_CAPACITY:
        _events.pop_front()
    _events.append({
        "type": kind,
        "title": mission["title"],
        "metric": mission["metric"],
        "reward_score": mission["reward_score"] if kind == "completed" else 0,
        "reward_charge": mission["reward_charge"] if kind == "completed" else 0.0,
        "serial": _serial,
    })

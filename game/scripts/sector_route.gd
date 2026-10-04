extends Control

# A status map, not a selectable level menu: progression still belongs to main.
const NAMES: Array[String] = ["霓虹前線", "琥珀殘骸帶", "紫電核心"]
const NOTES: Array[String] = ["軌道船塢", "殘骸精煉區", "核心要塞"]
const ACCENTS: Array[Color] = [Color("44dce8"), Color("ffc16b"), Color("d299ff")]
var status_label: Label
var _rows: Array[Label] = []
var _notes: Array[Label] = []
var _sector := 0
var _completed := 0
var _boss := false
var _dead := false
var _state_key := ""


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    _panel_style()
    size = Vector2(237.0, 229.0)
    var heading := _label(Vector2(14.0, 10.0), "航線導覽  /  SECTOR ROUTE", 13, Color("8cabbf"))
    add_child(heading)
    for index in range(3):
        var row := _label(Vector2(42.0, 38.0 + index * 44.0), "%02d  %s" % [index + 1, NAMES[index]], 16, Color.WHITE)
        _rows.append(row)
        add_child(row)
        var note := _label(Vector2(42.0, 59.0 + index * 44.0), NOTES[index], 11, Color("708497"))
        _notes.append(note)
        add_child(note)
    status_label = _label(Vector2(14.0, 186.0), "", 14, Color("b9d1df"))
    add_child(status_label)
    update_state(0, 0, 20, false, false)


func update_state(sector: int, kills: int, next_target: int, boss: bool, dead: bool) -> void:
    var normalized := clampi(sector, 0, 2)
    var completed := clampi(kills - maxi(0, next_target - 20), 0, 20)
    var key := "%d/%d/%d/%d" % [normalized, completed, int(boss), int(dead)]
    if key == _state_key or not is_instance_valid(status_label):
        return
    _state_key = key
    _sector = normalized
    _completed = completed
    _boss = boss
    _dead = dead
    for index in range(3):
        _rows[index].add_theme_color_override("font_color", ACCENTS[index] if index == _sector else Color("71899b"))
        _notes[index].text = "當前戰區 · " + NOTES[index] if index == _sector else ("已通過" if index < _sector else NOTES[index])
    status_label.text = "任務失敗 · R 重開" if dead else ("BOSS 鎖定 · 交戰中" if boss else "BOSS 進度 %02d / 20" % completed)
    status_label.add_theme_color_override("font_color", Color("ff8199") if dead else ACCENTS[_sector])
    queue_redraw()


func get_snapshot() -> Dictionary:
    return {"sector": _sector, "completed": _completed, "boss": _boss, "dead": _dead}


func _draw() -> void:
    draw_style_box(_panel_style(), Rect2(Vector2.ZERO, size))
    draw_line(Vector2(24.0, 49.0), Vector2(24.0, 137.0), Color("283e52"), 2.0, true)
    for index in range(3):
        var point := Vector2(24.0, 49.0 + index * 44.0)
        var color := ACCENTS[index] if index <= _sector else Color("405167")
        draw_circle(point, 5.0, color, index != _sector)
        if index == _sector:
            draw_arc(point, 8.0, 0.0, TAU, 24, color, 1.2, true)
            draw_circle(point, 2.0, color)
    draw_line(Vector2(14.0, 173.0), Vector2(223.0, 173.0), Color("263a4d"), 1.0)
    draw_rect(Rect2(14.0, 213.0, 209.0, 3.0), Color("263c50"))
    var fraction := 1.0 if _boss else float(_completed) / 20.0
    draw_rect(Rect2(14.0, 213.0, 209.0 * fraction, 3.0), Color("ff8199") if _dead else ACCENTS[_sector])


var _style: StyleBoxFlat


func _panel_style() -> StyleBoxFlat:
    if _style == null:
        _style = StyleBoxFlat.new()
        _style.bg_color = Color(0.008, 0.023, 0.045, 0.88)
        _style.border_color = Color(0.18, 0.3, 0.39, 0.7)
        _style.border_width_left = 2
        _style.corner_radius_top_right = 5
        _style.corner_radius_bottom_right = 5
    return _style


func _label(at: Vector2, value: String, font_size: int, color: Color) -> Label:
    var label := Label.new()
    label.position = at
    label.text = value
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", font_size)
    label.add_theme_color_override("font_color", color)
    return label

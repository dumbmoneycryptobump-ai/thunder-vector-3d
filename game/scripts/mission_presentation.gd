extends Control

# Fixed original HUD animation, advanced by active gameplay only; no Tweens,
# timers, frame allocations or input capture. World hazards live in world_events.
var title_label: Label
var detail_label: Label
var remaining := 0.0
var age := 0.0
var lifetime := 3.0
var tint := Color("7af5ec")


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    position = Vector2(390.0, 210.0)
    size = Vector2(500.0, 100.0)
    title_label = Label.new()
    title_label.position = Vector2(16.0, 12.0)
    title_label.size = Vector2(468.0, 42.0)
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.add_theme_font_size_override("font_size", 28)
    title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(title_label)
    detail_label = Label.new()
    detail_label.position = Vector2(16.0, 60.0)
    detail_label.size = Vector2(468.0, 30.0)
    detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    detail_label.add_theme_font_size_override("font_size", 17)
    detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(detail_label)
    clear()


func show_notice(title: String, detail: String, color: Color = Color("7af5ec"), seconds: float = 3.0) -> void:
    lifetime = clampf(seconds, 0.5, 5.0) if is_finite(seconds) else 3.0
    remaining = lifetime
    age = 0.0
    tint = color
    title_label.text = title
    title_label.add_theme_color_override("font_color", color)
    detail_label.text = detail
    detail_label.add_theme_color_override("font_color", Color("dffaff"))
    visible = true
    _refresh()


func advance(delta: float) -> void:
    if not is_finite(delta) or delta <= 0.0 or remaining <= 0.0:
        return
    age += delta
    remaining = maxf(0.0, remaining - delta)
    _refresh()


func clear() -> void:
    remaining = 0.0
    age = 0.0
    visible = false
    position.y = 210.0
    modulate = Color.WHITE
    queue_redraw()


func _refresh() -> void:
    visible = remaining > 0.0
    var entrance := clampf(age / 0.25, 0.0, 1.0)
    position.y = 210.0 - 22.0 * (1.0 - entrance) * (1.0 - entrance)
    modulate.a = minf(entrance, clampf(remaining / 0.4, 0.0, 1.0))
    queue_redraw()


func _draw() -> void:
    if remaining <= 0.0:
        return
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.005, 0.025, 0.06, 0.88))
    draw_rect(Rect2(Vector2.ZERO, size), Color(tint, 0.8), false, 2.0)
    var sweep := fmod(age * 200.0, size.x)
    draw_line(Vector2(sweep, 1.0), Vector2(minf(size.x, sweep + 52.0), 1.0), tint, 4.0)
    var fraction := clampf(remaining / lifetime, 0.0, 1.0)
    draw_rect(Rect2(0.0, size.y - 3.0, size.x * fraction, 3.0), tint)

extends Node3D

# Decorative scenery only: no collisions, gameplay RNG, lights or runtime spawning.
# The owner advances it only during active gameplay, so pause freezes every layer.
const SECTOR_NAMES := ["霓虹前線", "琥珀殘骸帶", "紫電核心"]
const WRAP_MIN := -28.0
const WRAP_SPAN := 56.0
const FLOOR_SPEED := 2.6
const DECK_SIZE := Vector2(28.0, 34.0)
const RAISED_PROP_MIN_X := 12.5
const PALETTES := [
    {"base": Color("07121e"), "hull": Color("142a3a"), "trim": Color("29485c"), "accent": Color("367582")},
    {"base": Color("15120f"), "hull": Color("352f29"), "trim": Color("504535"), "accent": Color("94713c")},
    {"base": Color("100e1c"), "hull": Color("26243d"), "trim": Color("433d62"), "accent": Color("796b9d")},
]
const FLOOR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 deck_base : source_color;
uniform vec4 deck_accent : source_color;
uniform float travel = 0.0;
uniform int sector = 0;

float line(float value, float width) {
    float distance_to_line = min(fract(value), 1.0 - fract(value));
    return 1.0 - smoothstep(width, width + 0.012, distance_to_line);
}

void fragment() {
    vec2 p = UV * vec2(28.0, 34.0);
    p.y += travel;
    float lateral = abs(p.x - 14.0);
    float quiet_lane = mix(0.28, 1.0, smoothstep(7.0, 12.0, lateral));
    float seams = max(line(p.x / 4.0, 0.007), line(p.y / 4.0, 0.005));
    float tracks = (1.0 - smoothstep(0.035, 0.095, abs(lateral - 11.75)));
    float dashes = step(0.63, fract(p.y / 4.0));
    float detail = 0.0;
    if (sector == 0) {
        detail = line((p.x + 0.28) / 4.0, 0.006) * step(0.72, fract(p.y / 4.0));
    } else if (sector == 1) {
        detail = line((p.x + p.y) / 4.0, 0.007) * step(11.6, lateral);
        seams *= 0.75;
    } else {
        detail = max(line((p.x + 0.8) / 4.0, 0.006) * step(0.70, fract(p.y / 4.0)),
                     line((p.y + 0.8) / 4.0, 0.006) * step(0.70, fract(p.x / 4.0)));
    }
    float panel = step(0.12, fract(p.x / 4.0)) * step(0.12, fract(p.y / 4.0));
    ALBEDO = deck_base.rgb * (0.88 + panel * 0.12)
           + deck_accent.rgb * ((seams * 0.105 + detail * 0.12) * quiet_lane + tracks * dashes * 0.22);
}
"""

class ScrollGroup:
    extends RefCounted

    var node: Node3D
    var start_z := 0.0
    var phase := 0.0
    var speed := 1.0


var _ready_scenery := false
var _sector := 0
var _travel := 0.0
var _roots: Array[Node3D] = []
var _scroll_groups: Array[ScrollGroup] = []
var _meshes: Array[Mesh] = []
var _materials: Array[Material] = []
var _sector_mesh_counts: Array[int] = [0, 0, 0]
var _mesh_instances := 0
var _building_sector := -1
var _floor_material: ShaderMaterial
var _box: BoxMesh
var _column: CylinderMesh
var _crystal: CylinderMesh
var _rock: SphereMesh
var _ring: TorusMesh


func _ready() -> void:
    setup()


func setup() -> void:
    if _ready_scenery:
        return
    _ready_scenery = true
    _make_shared_meshes()
    _make_floor()
    for index in range(3):
        _building_sector = index
        var sector_root := Node3D.new()
        sector_root.name = "Sector_%02d" % index
        add_child(sector_root)
        _roots.append(sector_root)
        var hull := _surface(PALETTES[index]["hull"], false)
        var trim := _surface(PALETTES[index]["trim"], false)
        var accent := _surface(PALETTES[index]["accent"], true)
        _build_insets(sector_root, hull, trim)
        match index:
            0:
                _build_shipyard(sector_root, hull, trim, accent)
            1:
                _build_refinery(sector_root, hull, trim, accent)
            2:
                _build_citadel(sector_root, hull, trim, accent)
    _building_sector = -1
    set_sector(_sector)
    reset()


func _make_shared_meshes() -> void:
    _box = BoxMesh.new()
    _box.size = Vector3.ONE
    _column = CylinderMesh.new()
    _column.top_radius = 1.0
    _column.bottom_radius = 1.0
    _column.height = 1.0
    _column.radial_segments = 12
    _column.rings = 1
    _crystal = CylinderMesh.new()
    _crystal.top_radius = 0.0
    _crystal.bottom_radius = 0.8
    _crystal.height = 2.0
    _crystal.radial_segments = 5
    _crystal.rings = 1
    _rock = SphereMesh.new()
    _rock.radius = 1.0
    _rock.height = 2.0
    _rock.radial_segments = 7
    _rock.rings = 3
    _ring = TorusMesh.new()
    _ring.inner_radius = 0.92
    _ring.outer_radius = 1.0
    _ring.rings = 20
    _ring.ring_segments = 4
    _meshes.assign([_box, _column, _crystal, _rock, _ring])


func _make_floor() -> void:
    var plane := PlaneMesh.new()
    plane.size = DECK_SIZE
    _meshes.append(plane)
    var shader := Shader.new()
    shader.code = FLOOR_SHADER
    _floor_material = ShaderMaterial.new()
    _floor_material.shader = shader
    _materials.append(_floor_material)
    var floor_node := _place(self, plane, _floor_material, Vector3(0.0, -1.8, 0.0), Vector3.ONE)
    floor_node.name = "FlightDeck"


func _surface(color: Color, unshaded: bool) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.metallic = 0.55 if not unshaded else 0.0
    material.roughness = 0.65
    if unshaded:
        material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _materials.append(material)
    return material


func _build_insets(parent: Node3D, hull: Material, trim: Material) -> void:
    for side in [-1.0, 1.0]:
        _place(parent, _box, trim, Vector3(side * 11.75, -1.64, 0.0), Vector3(0.09, 0.04, 34.0))
        for index in range(4):
            var group := _scrolling(parent, Vector3(side * 9.1, 0.0, -23.0 + float(index) * 14.0), FLOOR_SPEED)
            _place(group, _box, hull, Vector3(0.0, -1.68, 0.0), Vector3(2.5, 0.08, 6.7))
            _place(group, _box, trim, Vector3(side * 0.98, -1.62, 0.0), Vector3(0.045, 0.02, 4.8))


func _build_shipyard(parent: Node3D, hull: Material, trim: Material, accent: Material) -> void:
    for side in [-1.0, 1.0]:
        for index in range(4):
            var group := _scrolling(parent, Vector3(side * 14.9, 0.0, -23.0 + float(index) * 14.0), 1.6)
            _place(group, _box, hull, Vector3(0.0, -1.72, 0.0), Vector3(3.1, 0.65, 7.2))
            _place(group, _box, hull, Vector3(0.0, -0.75, -0.45), Vector3(2.25, 1.4, 3.7))
            _place(group, _box, trim, Vector3(0.0, -0.02, -0.45), Vector3(2.2, 0.12, 3.6))
            _place(group, _box, accent, Vector3(-side * 1.15, -0.64, -0.45), Vector3(0.07, 0.5, 2.4))
            _place(group, _box, trim, Vector3(side * 1.03, -0.34, 2.4), Vector3(0.34, 2.4, 0.48))


func _build_refinery(parent: Node3D, hull: Material, trim: Material, accent: Material) -> void:
    for side in [-1.0, 1.0]:
        for index in range(4):
            var group := _scrolling(parent, Vector3(side * 16.7, 0.0, -23.0 + float(index) * 14.0), 0.9)
            _place(group, _rock, hull, Vector3(0.0, -2.0, 0.0), Vector3(2.25, 1.2, 2.6), Vector3(0.12, float(index) * 0.34, 0.16))
            _place(group, _crystal, trim, Vector3(-side * 0.42, -0.7, 0.1), Vector3(0.6, 0.7, 0.6), Vector3(0.0, 0.3, side * 0.12))
            _place(group, _box, accent, Vector3(0.45, -0.77, -0.4), Vector3(0.12, 0.04, 1.7), Vector3(0.0, -0.5, 0.0))
        for index in range(3):
            var group := _scrolling(parent, Vector3(side * 14.85, 0.0, -19.0 + float(index) * 18.0), 1.7)
            _place(group, _box, hull, Vector3(0.0, -1.65, 0.0), Vector3(2.5, 0.4, 4.2))
            _place(group, _column, trim, Vector3(0.0, -0.61, 0.0), Vector3(0.82, 1.8, 0.82))
            _place(group, _ring, accent, Vector3(0.0, 0.08, 0.0), Vector3(0.86, 0.22, 0.86))
            _place(group, _box, hull, Vector3(0.0, -0.3, 1.1), Vector3(2.25, 0.2, 0.2))


func _build_citadel(parent: Node3D, hull: Material, trim: Material, accent: Material) -> void:
    for side in [-1.0, 1.0]:
        for index in range(4):
            var group := _scrolling(parent, Vector3(side * 14.9, 0.0, -23.0 + float(index) * 14.0), 1.35)
            _place(group, _column, hull, Vector3(0.0, -1.63, 0.0), Vector3(1.65, 0.28, 1.65))
            _place(group, _ring, accent, Vector3(0.0, -1.46, 0.0), Vector3(1.42, 0.18, 1.42))
            _place(group, _crystal, trim, Vector3(0.0, -0.12, 0.0), Vector3(0.7, 1.55, 0.7), Vector3(0.0, float(index) * 0.45, 0.0))
            _place(group, _crystal, hull, Vector3(side * 0.92, -0.71, 0.8), Vector3(0.45, 0.94, 0.45), Vector3(0.0, 0.55, side * 0.12))
            _place(group, _crystal, accent, Vector3(-side * 0.81, -0.85, -0.75), Vector3(0.28, 0.62, 0.28), Vector3(0.0, 0.3, -side * 0.12))


func _scrolling(parent: Node3D, at: Vector3, speed: float) -> Node3D:
    var group := ScrollGroup.new()
    group.node = Node3D.new()
    group.node.name = "Scroll_%02d" % _scroll_groups.size()
    group.node.position = at
    parent.add_child(group.node)
    group.start_z = at.z
    group.speed = speed
    _scroll_groups.append(group)
    return group.node


func _place(parent: Node3D, mesh: Mesh, material: Material, at: Vector3, size: Vector3, rotation_value: Vector3 = Vector3.ZERO) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.mesh = mesh
    instance.material_override = material
    instance.position = at
    instance.rotation = rotation_value
    instance.scale = size
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    parent.add_child(instance)
    _mesh_instances += 1
    if _building_sector >= 0:
        _sector_mesh_counts[_building_sector] += 1
    return instance


func set_sector(index: int) -> void:
    _sector = clampi(index, 0, 2)
    if not _ready_scenery:
        setup()
    for root_index in range(_roots.size()):
        _roots[root_index].visible = root_index == _sector
    _floor_material.set_shader_parameter("sector", _sector)
    _floor_material.set_shader_parameter("deck_base", PALETTES[_sector]["base"])
    _floor_material.set_shader_parameter("deck_accent", PALETTES[_sector]["accent"])


func advance(delta: float) -> void:
    if not _ready_scenery or not is_finite(delta) or delta <= 0.0:
        return
    _travel = fposmod(_travel + delta * FLOOR_SPEED, WRAP_SPAN)
    _floor_material.set_shader_parameter("travel", _travel)
    for group in _scroll_groups:
        group.phase = fposmod(group.phase + delta * group.speed, WRAP_SPAN)
        group.node.position.z = wrapf(group.start_z + group.phase, WRAP_MIN, WRAP_MIN + WRAP_SPAN)


func reset() -> void:
    _travel = 0.0
    if _floor_material != null:
        _floor_material.set_shader_parameter("travel", 0.0)
    for group in _scroll_groups:
        group.phase = 0.0
        group.node.position.z = group.start_z


func get_stats() -> Dictionary:
    return {
        "ready": _ready_scenery,
        "sector": _sector,
        "name": SECTOR_NAMES[_sector],
        "themes": _roots.size(),
        "mesh_instances": _mesh_instances,
        "visible_mesh_instances": 1 + _sector_mesh_counts[_sector] if _ready_scenery else 0,
        "meshes": _meshes.size(),
        "materials": _materials.size(),
        "scrolling_groups": _scroll_groups.size(),
        "phase": _travel,
        "travel": _travel,
        "deck_size": DECK_SIZE,
        "raised_prop_min_x": RAISED_PROP_MIN_X,
    }

"""Offline static checks for the starter kit.

This does not replace Godot parser/runtime validation. Run Godot headless afterward.
"""
from __future__ import annotations

import json
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "AGENTS.md",
    "README.md",
    "knowledge_graph/knowledge_graph.json",
    "knowledge_graph/smart_graph.png",
    "game/project.godot",
    "game/main.tscn",
    "game/default_bus_layout.tres",
    "game/assets/fonts/NotoSansTC-Variable.ttf",
    "game/assets/fonts/FONT_PROVENANCE.md",
    "docs/licenses/OFL_NotoSansTC.txt",
    "game/scripts/device_controls.gd",
    "game/tests/device_controls_test.gd",
    "game/tests/device_integration_test.gd",
    "scripts/build_web.ps1",
    "scripts/serve_web.py",
    "web/index.html",
    "docs/CROSS_DEVICE.md",
    "game/scripts/main.gd",
    "game/scripts/settings_store.gd",
    "game/scripts/visual_factory.gd",
    "game/scripts/transient_effects.gd",
    "game/scripts/encounter_director.gd",
    "game/scripts/arsenal.gd",
    "game/scripts/arcade_feedback.gd",
    "game/scripts/sector_scenery.gd",
    "game/scripts/sector_route.gd",
    "game/scripts/weapon_system.gd",
    "game/tests/weapon_system_test.gd",
    "game/tests/weapon_stress.gd",
    "game/tests/capture_weapon_preview.gd",
    "game/tests/weapon_window_benchmark.gd",
    "game/tests/expanded_edge_test.gd",
    "docs/screenshots/map_sector_0.png",
    "docs/screenshots/map_sector_1.png",
    "docs/screenshots/map_sector_2.png",
    "docs/screenshots/weapon_2.png",
    "docs/screenshots/weapon_3.png",
    "docs/screenshots/weapon_4.png",
    "game/tests/sector_scenery_test.gd",
    "game/tests/map_integration_test.gd",
    "game/tests/capture_map_preview.gd",
    "game/tests/map_window_benchmark.gd",
    "game/assets/generated/orbital_planet_imagegen_v1.png",
    "game/assets/generated/MAP_ART_PROVENANCE.md",
    "game/tests/arsenal_test.gd",
    "game/tests/arcade_feedback_test.gd",
    "game/tests/arcade_combat_test.gd",
    "game/tests/arcade_flow_test.gd",
    "game/tests/arcade_stress.gd",
    "game/tests/arcade_window_benchmark.gd",
    "docs/screenshots/arcade_overdrive.png",
    "game/tests/capture_arcade_preview.gd",
    "game/assets/generated/wingman_imagegen_v1.png",
    "game/assets/generated/ARCADE_ART_PROVENANCE.md",
    "game/tests/headless_smoke.gd",
    "game/tests/art_integration_test.gd",
    "game/tests/capture_preview.gd",
    "game/tests/gameplay_flow_test.gd",
    "game/tests/transient_effects_test.gd",
    "game/tests/runtime_benchmark.gd",
    "game/tests/runtime_optimization_test.gd",
    "game/tests/hud_runtime_test.gd",
    "game/tests/encounter_director_test.gd",
    "game/tests/content_expansion_test.gd",
    "game/tests/shield_pickup_test.gd",
    "game/tests/capture_content_preview.gd",
    "game/tests/pool_stress.gd",
    "game/tests/settings_store_test.gd",
    "game/tests/settings_ui_test.gd",
    "game/assets/ui/player_ship.png",
    "game/assets/ui/enemy_scout.png",
    "game/assets/effects/explosion_8x8.png",
    "game/assets/audio/laser.wav",
    "game/assets/generated/player_ship_imagegen_v1.png",
    "game/assets/generated/enemy_scout_imagegen_v1.png",
    "game/assets/generated/enemy_heavy_imagegen_v1.png",
    "game/assets/generated/boss_core_imagegen_v1.png",
    "game/assets/generated/pickup_power_imagegen_v1.png",
    "game/assets/generated/pickup_health_imagegen_v1.png",
    "game/assets/generated/pickup_bomb_imagegen_v1.png",
    "game/assets/generated/enemy_interceptor_imagegen_v1.png",
    "game/assets/generated/enemy_bomber_imagegen_v1.png",
    "game/assets/generated/pickup_shield_imagegen_v1.png",
    "game/assets/generated/sector_nebula_imagegen_v1.png",
    "game/assets/generated/CONTENT_ART_PROVENANCE.md",
    "docs/screenshots/gameplay_preview.png",
    "docs/screenshots/content_preview.png",
    "docs/CONTENT_EXPANSION.md",
    "docs/RELEASE_README.txt",
    "docs/licenses/GODOT_COPYRIGHT.txt",
    "docs/licenses/GODOT_LICENSE.txt",
    "docs/licenses/GODOT_THIRD_PARTY_NOTICES.txt",
    "scripts/build_windows.ps1",
    "scripts/start_game.ps1",
    "tools/local_model_mcp.py",
]


def fail(message: str, failures: list[str]) -> None:
    failures.append(message)
    print(f"[FAIL] {message}")


def ok(message: str) -> None:
    print(f"[ OK ] {message}")


def read_png_dimensions(path: Path) -> tuple[int, int]:
    """Read PNG dimensions from the signature and IHDR chunk using stdlib only."""
    with path.open("rb") as stream:
        header = stream.read(24)
    if len(header) != 24 or header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError("invalid PNG signature or IHDR header")
    if struct.unpack(">I", header[8:12])[0] != 13:
        raise ValueError("invalid IHDR chunk length")
    width, height = struct.unpack(">II", header[16:24])
    if width == 0 or height == 0:
        raise ValueError("PNG dimensions must be positive")
    return width, height


def main() -> int:
    failures: list[str] = []
    for rel in REQUIRED:
        path = ROOT / rel
        if not path.exists():
            fail(f"Missing {rel}", failures)
        elif path.is_file() and path.stat().st_size == 0:
            fail(f"Empty file {rel}", failures)
        else:
            ok(rel)

    graph_path = ROOT / "knowledge_graph/knowledge_graph.json"
    if graph_path.exists():
        try:
            graph = json.loads(graph_path.read_text(encoding="utf-8"))
            ids = [node["id"] for node in graph["nodes"]]
            if len(ids) != len(set(ids)):
                fail("Knowledge graph contains duplicate node IDs", failures)
            else:
                ok(f"Knowledge graph: {len(ids)} nodes / {len(graph['edges'])} edges")
            missing_edges = [e for e in graph["edges"] if e["from"] not in ids or e["to"] not in ids]
            if missing_edges:
                fail(f"Knowledge graph has dangling edges: {missing_edges}", failures)
        except Exception as exc:
            fail(f"Knowledge graph JSON invalid: {exc}", failures)

    gd_path = ROOT / "game/scripts/main.gd"
    if gd_path.exists():
        text = gd_path.read_text(encoding="utf-8")
        required_functions = [
            "_ready",
            "_physics_process",
            "_spawn_enemy",
            "_spawn_boss",
            "_resolve_collisions",
            "_restart_game",
            "_load_settings",
            "_apply_settings",
        ]
        for name in required_functions:
            if not re.search(rf"^func {re.escape(name)}\b", text, re.MULTILINE):
                fail(f"GDScript missing function {name}", failures)
        if text.count("(") != text.count(")"):
            fail("GDScript parentheses count does not match", failures)
        if text.count("[") != text.count("]"):
            fail("GDScript bracket count does not match", failures)
        if text.count("{") != text.count("}"):
            fail("GDScript brace count does not match", failures)
        ok(f"GDScript static scan: {len(text.splitlines())} lines")

    bus_layout_path = ROOT / "game/default_bus_layout.tres"
    if bus_layout_path.exists():
        text = bus_layout_path.read_text(encoding="utf-8")
        if not re.search(r'^\[gd_resource\b[^]]*\btype="AudioBusLayout"', text, re.MULTILINE):
            fail("Audio bus layout is missing its AudioBusLayout resource type", failures)
        else:
            ok("Audio bus layout resource header")
        if 'bus/1/name = &"SFX"' not in text or 'bus/1/send = &"Master"' not in text:
            fail("Audio bus layout is missing the SFX bus routed to Master", failures)
        else:
            ok("SFX audio bus routing")

    project_settings_path = ROOT / "game/project.godot"
    if project_settings_path.exists():
        text = project_settings_path.read_text(encoding="utf-8")
        expected_bus_setting = 'buses/default_bus_layout="res://default_bus_layout.tres"'
        if expected_bus_setting not in text:
            fail("project.godot is missing the audio/buses/default_bus_layout setting", failures)
        else:
            ok("Project audio bus setting")

    export_preset_path = ROOT / "game/export_presets.cfg"
    if export_preset_path.exists():
        text = export_preset_path.read_text(encoding="utf-8")
        expected_settings = [
            'binary_format/architecture="x86_64"',
            'binary_format/embed_pck=true',
            'application/file_version="1.1.0.0"',
            'application/product_version="1.1.0.0"',
            'exclude_filter="tests/*"',
        ]
        missing_settings = [setting for setting in expected_settings if setting not in text]
        if missing_settings:
            fail(f"Windows export preset is missing reproducible release settings: {missing_settings}", failures)
        else:
            ok("Windows x86_64 release preset")

    build_script_path = ROOT / "scripts/build_windows.ps1"
    if build_script_path.exists():
        text = build_script_path.read_text(encoding="utf-8")
        required_release_gates = [
            "Assert-WindowsX64Executable",
            "windows_release_x86_64.exe",
            "^4\\.7\\.2\\.stable",
            "Get-GodotErrorLines",
            "SkipLaunchValidation",
            "launch_validation=$launchValidation",
            "Release ZIP entry whitelist mismatch",
        ]
        missing_gates = [gate for gate in required_release_gates if gate not in text]
        if missing_gates:
            fail(f"Windows build script is missing release gates: {missing_gates}", failures)
        else:
            ok("Windows build/export/launch/package gates")

    for rel, expected in [
        ("game/assets/ui/player_ship.png", (512, 512)),
        ("game/assets/effects/explosion_8x8.png", (1024, 1024)),
        ("game/assets/generated/player_ship_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/enemy_scout_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/enemy_heavy_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/boss_core_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/pickup_power_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/pickup_health_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/pickup_bomb_imagegen_v1.png", (1254, 1254)),
        ("docs/screenshots/gameplay_preview.png", (1280, 720)),
        ("docs/screenshots/content_preview.png", (1280, 720)),
        ("game/assets/generated/enemy_interceptor_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/enemy_bomber_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/pickup_shield_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/sector_nebula_imagegen_v1.png", (1774, 887)),
        ("game/assets/generated/wingman_imagegen_v1.png", (1254, 1254)),
        ("game/assets/generated/orbital_planet_imagegen_v1.png", (1254, 1254)),
        ("docs/screenshots/arcade_overdrive.png", (1280, 720)),
        ("docs/screenshots/map_sector_0.png", (1280, 720)),
        ("docs/screenshots/map_sector_1.png", (1280, 720)),
        ("docs/screenshots/map_sector_2.png", (1280, 720)),
        ("docs/screenshots/weapon_2.png", (1280, 720)),
        ("docs/screenshots/weapon_3.png", (1280, 720)),
        ("docs/screenshots/weapon_4.png", (1280, 720)),
    ]:
        path = ROOT / rel
        if path.exists():
            try:
                dimensions = read_png_dimensions(path)
                if dimensions != expected:
                    fail(f"{rel} size {dimensions}, expected {expected}", failures)
                else:
                    ok(f"{rel} dimensions {dimensions}")
            except Exception as exc:
                fail(f"Cannot read {rel}: {exc}", failures)

    if failures:
        print(f"\nStatic verification failed: {len(failures)} issue(s).")
        return 1
    print("\nStatic verification passed. Next: run Godot headless validation on a machine with Godot installed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

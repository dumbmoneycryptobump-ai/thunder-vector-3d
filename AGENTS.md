# AGENTS.md — Thunder Vector 3D

## Mission
Maintain a small, offline-first Windows 3D vertical shooter built with **Godot 4.7.2 stable and GDScript**. Preserve the fast arcade loop: move, dodge, shoot, destroy enemies, collect upgrades, defeat a boss, restart quickly.

## Mandatory workflow
1. Read `knowledge_graph/knowledge_graph.json` before planning or editing.
2. Work on one graph node or one clearly scoped bug at a time.
3. Before a non-trivial edit, use the `thunder_local` MCP tool `plan_game_feature` when it is available.
4. Make the smallest coherent change. Do not rewrite the entire prototype unless the user explicitly approves it.
5. Run `python tools/verify_project.py` after every change.
6. When Godot is installed, run `godot --headless --path game --editor --quit` and report the real result.
7. Ask the local reviewer to inspect the final diff with `review_change`; fix BLOCKER findings.
8. Update the graph only with evidence. Never mark headless validation or a Windows build complete without an actual command result.
9. Create a Git checkpoint after a passing change.

## Technical constraints
- Target Godot 4.7.2 APIs and GDScript, not Unity or C#.
- The game must work without a network connection. AI tools are development-only and never ship inside the game runtime.
- Preserve GL Compatibility unless a measured rendering need justifies Forward+.
- Avoid paid assets and copied commercial game art. Generated placeholder assets in this repository may be replaced with original GLB/PNG files.
- Keep controls: WASD/arrows move, Space/left-click shoots, B bomb, P/Esc pause, R/Enter restart.
- Do not commit `.venv`, `.godot`, exported binaries, credentials, or Codex authentication files.
- Never print to stdout from `tools/local_model_mcp.py`; stdout is reserved for MCP JSON-RPC.

## Definition of done for code changes
- Acceptance criteria stated.
- Diff is focused.
- Static verifier passes.
- Godot headless parser check passes when Godot is available.
- Local reviewer returns `PASS`, or remaining findings are documented and explicitly accepted.
- Graph status/evidence updated when applicable.

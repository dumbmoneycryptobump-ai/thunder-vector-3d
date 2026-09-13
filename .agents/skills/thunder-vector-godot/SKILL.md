---
name: thunder-vector-godot
description: Develop, debug, review, test, optimize, or package the Thunder Vector 3D offline Godot vertical shooter. Use only inside this repository; always coordinate work through the project knowledge graph and the thunder_local reviewer when available.
---

# Thunder Vector 3D Codex skill

## Start every task
1. Read `/AGENTS.md` and obey it.
2. Read `/knowledge_graph/knowledge_graph.json` before planning or editing.
3. State the selected graph node, acceptance criteria, files likely to change, tests, and rollback plan.
4. Work on one node or one tightly scoped bug only.
5. When the `thunder_local` MCP server is available, call `plan_game_feature` before a non-trivial edit.

## Implementation rules
- Target Godot 4.7.2 stable and GDScript.
- Keep the game offline at runtime. AI services are development-only.
- Preserve controls: WASD/arrows, Space/left-click, B, P/Esc, R/Enter.
- Prefer focused changes; do not rewrite the entire main script in one task.
- Use original or permissively licensed assets only. Do not copy commercial Raiden art, music, names, logos, or levels.
- Do not report a test, build, or gameplay check as passed unless the corresponding command actually ran.

## Required verification
Run after each code change:

```powershell
python tools/verify_project.py
```

When Godot is available:

```powershell
godot --headless --path game --editor --quit
```

Before finishing:
1. Ask `thunder_local.review_change` to review the current git diff when available.
2. Fix every BLOCKER or explicitly report why it remains.
3. Update the knowledge graph only with real command output or an explicit manual-test record.
4. Return changed files, command results, known limitations, and the next recommended graph node.

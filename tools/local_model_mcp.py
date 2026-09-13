"""Codex MCP bridge for a local Ollama reviewer.

Requirements:
    Python 3.10+
    pip install -r tools/requirements.txt
    Ollama running at http://localhost:11434

The server uses stdio. Never print to stdout; MCP JSON-RPC uses stdout.
"""
from __future__ import annotations

import json
import logging
import os
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from mcp.server import MCPServer

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("thunder_local_model_mcp")

PROJECT_ROOT = Path(os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[1])).resolve()
OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434").rstrip("/")
OLLAMA_MODEL = os.environ.get("OLLAMA_MODEL", "qwen3.5")
OLLAMA_TIMEOUT = float(os.environ.get("OLLAMA_TIMEOUT", "180"))
MAX_CONTEXT_CHARS = int(os.environ.get("MAX_CONTEXT_CHARS", "48000"))

mcp = MCPServer("Thunder Vector Local Reviewer")


def _safe_path(relative_path: str) -> Path:
    candidate = (PROJECT_ROOT / relative_path).resolve()
    if candidate != PROJECT_ROOT and PROJECT_ROOT not in candidate.parents:
        raise ValueError("Path escapes PROJECT_ROOT")
    return candidate


def _ollama_chat(system: str, user: str) -> str:
    payload: dict[str, Any] = {
        "model": OLLAMA_MODEL,
        "stream": False,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user[:MAX_CONTEXT_CHARS]},
        ],
        "options": {"temperature": 0.15},
    }
    request = urllib.request.Request(
        f"{OLLAMA_BASE_URL}/api/chat",
        data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=OLLAMA_TIMEOUT) as response:
            data = json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(
            f"Cannot reach Ollama at {OLLAMA_BASE_URL}. Start Ollama and pull model '{OLLAMA_MODEL}'. Error: {exc}"
        ) from exc
    except TimeoutError as exc:
        raise RuntimeError(f"Ollama timed out after {OLLAMA_TIMEOUT} seconds") from exc

    message = data.get("message", {})
    content = message.get("content")
    if not content:
        raise RuntimeError(f"Unexpected Ollama response: {json.dumps(data, ensure_ascii=False)[:1200]}")
    return str(content)


def _graph_text() -> str:
    graph_path = PROJECT_ROOT / "knowledge_graph" / "knowledge_graph.json"
    return graph_path.read_text(encoding="utf-8")


@mcp.tool()
async def plan_game_feature(feature: str, constraints: str = "") -> str:
    """Plan one Godot feature before Codex edits files.

    Args:
        feature: The requested game feature or bug fix.
        constraints: Optional scope, performance, style, or file constraints.
    """
    system = (
        "You are a conservative senior Godot 4.7.2 reviewer. Reply in Traditional Chinese. "
        "Do not write a broad rewrite. Produce a small implementation plan, risks, files to touch, "
        "verification commands, and a rollback point. The game must remain offline at runtime."
    )
    user = f"PROJECT GRAPH:\n{_graph_text()}\n\nFEATURE:\n{feature}\n\nCONSTRAINTS:\n{constraints}"
    return _ollama_chat(system, user)


@mcp.tool()
async def review_change(task: str, changed_files: str, diff_or_code: str, constraints: str = "") -> str:
    """Review a proposed or completed change and return actionable findings.

    Args:
        task: Intended behavior and acceptance criteria.
        changed_files: File paths that were changed.
        diff_or_code: Git diff, GDScript, logs, or other evidence.
        constraints: Extra project constraints.
    """
    system = (
        "You are the local review gate for a Godot 4.7.2 vertical shooter. Reply in Traditional Chinese. "
        "Find parser/API errors, gameplay regressions, unsafe file operations, performance risks, and missing tests. "
        "Separate BLOCKER, IMPORTANT, and OPTIONAL. End with PASS or NEEDS_CHANGES. Do not fabricate test results."
    )
    user = (
        f"PROJECT GRAPH:\n{_graph_text()}\n\nTASK:\n{task}\n\nFILES:\n{changed_files}\n"
        f"\nCONSTRAINTS:\n{constraints}\n\nDIFF OR CODE:\n{diff_or_code}"
    )
    return _ollama_chat(system, user)


@mcp.tool()
async def audit_project_file(relative_path: str, focus: str = "correctness and Godot 4.7.2 compatibility") -> str:
    """Read and audit one UTF-8 project file inside the repository.

    Args:
        relative_path: Path relative to the project root.
        focus: What the reviewer should prioritize.
    """
    path = _safe_path(relative_path)
    if not path.is_file():
        raise ValueError(f"File not found: {relative_path}")
    if path.stat().st_size > 2_000_000:
        raise ValueError("File is too large for text review")
    text = path.read_text(encoding="utf-8", errors="replace")
    system = (
        "You audit one file from a Godot 4.7.2 game repository. Reply in Traditional Chinese. "
        "Cite line numbers when possible. Do not claim you executed the file."
    )
    user = f"FOCUS: {focus}\nFILE: {relative_path}\n\n{text}"
    return _ollama_chat(system, user)


@mcp.tool()
async def read_knowledge_graph() -> str:
    """Return the project's source-of-truth knowledge graph JSON."""
    return _graph_text()


@mcp.tool()
async def propose_graph_update(completed_work: str, evidence: str) -> str:
    """Propose JSON changes after work is completed; never edits the graph directly.

    Args:
        completed_work: What changed and why.
        evidence: Tests, commands, file paths, screenshots, or build outputs.
    """
    system = (
        "You maintain a project knowledge graph. Reply in Traditional Chinese. "
        "Return a minimal RFC 6902-style patch proposal in a fenced JSON block, then a short rationale. "
        "Never mark a test done without concrete evidence."
    )
    user = f"CURRENT GRAPH:\n{_graph_text()}\n\nCOMPLETED WORK:\n{completed_work}\n\nEVIDENCE:\n{evidence}"
    return _ollama_chat(system, user)


if __name__ == "__main__":
    mcp.run(transport="stdio")

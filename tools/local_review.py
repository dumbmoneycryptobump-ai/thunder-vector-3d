"""Standalone local review command for use outside MCP."""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# Import helper without launching the MCP server.
from local_model_mcp import _ollama_chat, _graph_text


def main() -> int:
    parser = argparse.ArgumentParser(description="Review stdin or a file with the configured local Ollama model")
    parser.add_argument("--task", required=True, help="Intended task and acceptance criteria")
    parser.add_argument("--file", help="Read review material from this file; otherwise stdin")
    parser.add_argument("--output", default="logs/local-review-last.md", help="Output Markdown path")
    args = parser.parse_args()

    if args.file:
        material = Path(args.file).read_text(encoding="utf-8", errors="replace")
    else:
        material = sys.stdin.read()
    if not material.strip():
        print("No review input was provided.", file=sys.stderr)
        return 2

    system = (
        "You are a strict Godot 4.7.2 code reviewer. Reply in Traditional Chinese. "
        "Classify findings as BLOCKER, IMPORTANT, OPTIONAL; end with PASS or NEEDS_CHANGES. "
        "Never claim tests ran unless logs are provided."
    )
    prompt = f"PROJECT GRAPH:\n{_graph_text()}\n\nTASK:\n{args.task}\n\nMATERIAL:\n{material}"
    result = _ollama_chat(system, prompt)

    output = Path(args.output)
    if not output.is_absolute():
        output = Path(os.environ.get("PROJECT_ROOT", Path(__file__).resolve().parents[1])) / output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(result + "\n", encoding="utf-8")
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

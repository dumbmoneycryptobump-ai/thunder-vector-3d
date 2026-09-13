"""Safely update one knowledge-graph node status and append local evidence."""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GRAPH = ROOT / "knowledge_graph" / "knowledge_graph.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("node_id")
    parser.add_argument("status")
    parser.add_argument("--evidence", default="")
    args = parser.parse_args()

    data = json.loads(GRAPH.read_text(encoding="utf-8"))
    node = next((n for n in data["nodes"] if n["id"] == args.node_id), None)
    if node is None:
        raise SystemExit(f"Unknown node: {args.node_id}")
    node["status"] = args.status
    if args.evidence:
        node.setdefault("evidence", []).append({
            "timestamp_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "text": args.evidence,
        })
    GRAPH.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Updated {args.node_id} -> {args.status}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

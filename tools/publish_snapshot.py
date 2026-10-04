#!/usr/bin/env python3
"""Copy a filtered tracked commit into an existing clean public Git worktree.

No checkout, index, commit, deletion, ref update or network operation is performed.
First use --dry-run; then --apply --expect-plan with its plan_sha256. The source
repository is this script's repository. JSON contains only repository-relative
paths, never machine-specific absolute paths. This is a heuristic safety audit,
not proof that all source content is free of private information.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
BLOCKED_DIRS = {".git", ".godot", ".venv", "venv", "__pycache__", "node_modules",
                ".pytest_cache", "build", "logs"}
BLOCKED_SUFFIXES = {".exe", ".dll", ".pdb", ".pck", ".wasm", ".so", ".dylib",
                    ".pyc", ".pyo", ".class", ".zip", ".7z", ".tar", ".gz",
                    ".pem", ".pfx", ".key", ".keystore"}
PRIVATE_FILES = {"reference_images/gameplay_visual_target.jpg",
                 "reference_images/title_card.jpg", "manifest_sha256.txt"}
CONTENT_FLAGS = (
    ("private_key", rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    ("credential_token", rb"(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,}|AKIA[A-Z0-9]{16})"),
    ("machine_home_path", rb"(?i)(?:[a-z]:[\\/]Users[\\/]|/Users/|/home/)[A-Za-z0-9_.-]+"),
)


class Failure(Exception):
    pass


def git(repository, *arguments):
    env = dict(os.environ, GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0")
    result = subprocess.run(["git", "-C", str(repository), *arguments],
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=env, timeout=60)
    if result.returncode:
        raise Failure("Read-only Git inspection failed; details suppressed.")
    return result.stdout


def safe_relative(name):
    path = PurePosixPath(name)
    if (path.is_absolute() or not name or "\\" in name or str(path) != name
            or any(ord(c) < 32 or c in ':<>"|?*' for c in name)):
        raise Failure("Source contains an unsafe or nonportable path.")
    for part in path.parts:
        if (part in (".", "..") or part.endswith((".", " "))
                or re.fullmatch(r"(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?", part)):
            raise Failure("Source contains an unsafe or nonportable path.")
    return path


def exclusion(name):
    path = safe_relative(name)
    lower = name.lower()
    parts = [p.lower() for p in path.parts]
    base = parts[-1]
    if lower in PRIVATE_FILES or lower.startswith("docs/早期參考稿/"):
        return "private_reference_or_stale_manifest"
    if lower.startswith("docs/") and base.endswith("_handoff.json"):
        return "task_local_handoff"
    if parts[0] == ".codex" and lower != ".codex/config.toml.example":
        return "private_codex_state"
    if any(p in BLOCKED_DIRS for p in parts):
        return "cache_build_or_log"
    if (base == ".env" or base.startswith(".env.") or base.startswith("credentials")
            or base in {"auth.json", "secrets.json", "export_credentials.cfg", ".netrc",
                        ".npmrc", ".pypirc", "id_rsa", "id_ed25519", "id_ecdsa"}
            or PurePosixPath(lower).suffix in BLOCKED_SUFFIXES):
        return "credential_or_compiled_archive"
    return None


def tracked_tree(repository, commit):
    entries = {}
    folded = set()
    for record in git(repository, "ls-tree", "-rz", commit).split(b"\0"):
        if not record:
            continue
        metadata, raw_name = record.split(b"\t", 1)
        mode, kind, oid = metadata.decode("ascii").split()
        name = raw_name.decode("utf-8")
        safe_relative(name)
        if name.casefold() in folded:
            raise Failure("Source tree has case-insensitive path collisions.")
        folded.add(name.casefold())
        if kind != "blob" or mode not in ("100644", "100755"):
            raise Failure("Source/public tree contains symlinks or submodules; manual review required.")
        entries[name] = {"mode": mode, "oid": oid}
    return entries


def no_links(path):
    # Check lexical ancestors before resolve(): resolving first would hide junctions.
    for item in [*reversed(path.parents), path]:
        try:
            info = item.lstat()
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
            raise Failure("Refused symlink/reparse-point traversal.")
    return path.resolve()


def destination_path(destination, name):
    result = no_links(destination.joinpath(*safe_relative(name).parts))
    if not result.is_relative_to(destination):
        raise Failure("Destination path escaped its checked worktree.")
    if result.exists() and (not result.is_file() or result.stat().st_nlink != 1):
        raise Failure("Destination collision or hard link requires manual review.")
    return result


def validate_destination(source, destination, commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise Failure("Source commit must be a complete lowercase 40-character SHA.")
    if not destination.is_absolute() or not destination.is_dir():
        raise Failure("Destination must be an existing absolute Git worktree directory.")
    destination = no_links(destination)
    if (destination == source.resolve() or destination.is_relative_to(source.resolve())
            or source.resolve().is_relative_to(destination)):
        raise Failure("Destination must be a separate public worktree, outside the source checkout.")
    top = Path(git(destination, "rev-parse", "--show-toplevel").decode().strip()).resolve()
    if top != destination or git(destination, "rev-parse", "--is-inside-work-tree").strip() != b"true":
        raise Failure("Destination must be the exact Git worktree root.")
    if git(source, "rev-parse", "--verify", commit + "^{commit}").decode().strip() != commit:
        raise Failure("Source does not resolve to the exact requested commit.")
    tip = git(source, "rev-parse", "refs/remotes/origin/main").decode().strip()
    if (git(destination, "rev-parse", "HEAD").decode().strip() != tip
            or git(destination, "rev-parse", "refs/remotes/origin/main").decode().strip() != tip):
        raise Failure("Destination HEAD and both local origin/main refs must match.")
    status = git(destination, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    if any(record and not record.startswith(b"?? ") for record in status.split(b"\0")):
        raise Failure("Destination has staged/tracked changes; start from a clean public worktree.")
    if any(record and not record.startswith(b"H ") for record in
           git(destination, "ls-files", "-v", "-z").split(b"\0")):
        raise Failure("Destination has hidden/index flags; refuse assume-unchanged or sparse files.")
    return destination, tip


def plan_snapshot(source, destination, commit):
    destination, tip = validate_destination(source, destination, commit)
    source_tree = tracked_tree(source, commit)
    public_tree = tracked_tree(destination, tip)
    plan = {"source_commit": commit, "public_base": tip, "copy": [], "excluded": [],
            "manual_tracked_removal": [], "retained_public_files": [], "content_flags": []}
    for name, entry in source_tree.items():
        reason = exclusion(name)
        if reason:
            plan["excluded"].append({"path": name, "reason": reason})
            continue
        target = destination_path(destination, name)
        if target.exists() and name not in public_tree:
            raise Failure("An untracked/ignored destination file would be overwritten; refusing.")
        data = git(source, "cat-file", "blob", entry["oid"])
        for label, pattern in CONTENT_FLAGS:
            if re.search(pattern, data):
                plan["content_flags"].append({"path": name, "reason": label})
        action = "add" if name not in public_tree else ("unchanged" if public_tree[name] == entry else "update")
        plan["copy"].append({"path": name, "action": action, **entry,
                             "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)})
    for name in public_tree:
        reason = exclusion(name)
        if reason:
            plan["manual_tracked_removal"].append({"path": name, "reason": reason})
        elif name not in source_tree:
            plan["retained_public_files"].append(name)
    encoded = json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()
    plan["plan_sha256"] = hashlib.sha256(encoded).hexdigest()
    plan["counts"] = {key: len(plan[key]) for key in ("copy", "excluded", "manual_tracked_removal",
                                                   "retained_public_files", "content_flags")}
    plan["publication_ready"] = not (plan["manual_tracked_removal"] or plan["content_flags"]
                                     or plan["retained_public_files"])
    return destination, plan


def apply_snapshot(source, destination, plan, expected):
    if expected != plan["plan_sha256"]:
        raise Failure("Plan confirmation differs; run --dry-run and review its plan_sha256 first.")
    if plan["content_flags"]:
        raise Failure("Content safety flags require manual source review; nothing copied.")
    # Recheck root/ref/cleanliness immediately before writing; never touch Git metadata.
    validate_destination(source, destination, plan["source_commit"])
    for entry in plan["copy"]:
        if entry["action"] == "unchanged":
            continue
        target = destination_path(destination, entry["path"])
        data = git(source, "cat-file", "blob", entry["oid"])
        if hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise Failure("Source object content differs from the reviewed plan; stopped.")
        target.parent.mkdir(parents=True, exist_ok=True)
        destination_path(destination, entry["path"])
        with target.open("xb" if entry["action"] == "add" else "wb") as stream:
            stream.write(data)
        target.chmod(0o755 if entry["mode"] == "100755" else 0o644)
        if hashlib.sha256(target.read_bytes()).hexdigest() != entry["sha256"]:
            raise Failure("Written snapshot verification failed; inspect worktree manually.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--dest", required=True)
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument("--dry-run", action="store_true")
    modes.add_argument("--apply", action="store_true")
    parser.add_argument("--expect-plan", help="Required for --apply: hash from reviewed --dry-run")
    args = parser.parse_args()
    destination, plan = plan_snapshot(ROOT, Path(args.dest), args.source_commit)
    if args.apply:
        apply_snapshot(ROOT, destination, plan, args.expect_plan)
    plan["applied"] = args.apply
    plan["no_deletions"] = True
    plan["no_git_mutations_or_network"] = True
    plan["safety_note"] = "Heuristic checks only; inspect all public changes before committing."
    print(json.dumps(plan, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Failure as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("ERROR: Local path/object operation failed; details suppressed.", file=sys.stderr)
        sys.exit(1)

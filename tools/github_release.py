#!/usr/bin/env python3
"""Bounded GitHub publication CLI; GCM secrets never enter arguments or output.

inspect/actions are read-only. enable-pages and release are explicit mutations.
release requires absolute notes/ZIP paths and a full commit on the public default
branch. It never replaces assets or modifies published releases. Repeat the same
command with --publish only after reviewing the verified draft output.
Use --draft-id to resume a known draft when release enumeration is incomplete.
Use --account to select an existing GCM account and verify its API identity before
any operation. A mismatched or unavailable account never falls back or logs in.
GitHub metadata writes are not atomic against concurrent privileged writers; use
an exclusively managed draft. Post-publication checks detect mismatches but never
delete or silently roll back an already-public release.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
import zipfile


class Failure(Exception):
    """Only fixed, credential-free messages may be raised here."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def account_name(value):
    if not isinstance(value, str) or not re.fullmatch(
            r"(?=.{1,39}\Z)[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*", value):
        raise Failure("Account must be a GitHub username of at most 39 letters, digits or single hyphens.")
    return value


def credential(account=None):
    if account is not None:
        account_name(account)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("GIT_TRACE", "GCM_TRACE")) and k != "GIT_CURL_VERBOSE"}
    env.update(GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    result = subprocess.run(
        ["git", "-c", "credential.interactive=never", "credential", "fill"],
        input="protocol=https\nhost=github.com\n" +
              ("username=" + account + "\n" if account is not None else "") + "\n", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env, timeout=45)
    values = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if result.returncode or not values.get("username") or not values.get("password"):
        raise Failure("Existing GitHub GCM credential unavailable; authenticate separately.")
    return values["password"]


class GitHub:
    def __init__(self, repo, account=None):
        self.account = account_name(account) if account is not None else None
        self.base = "https://api.github.com/repos/" + repo
        self.token = credential(account) if account is not None else credential()
        self.opener = urllib.request.build_opener(NoRedirect())
        self.scopes = None
        if self.account is not None:
            identity = self.request("GET", "https://api.github.com/user")
            login = identity.get("login") if isinstance(identity, dict) else None
            if not isinstance(login, str) or login.casefold() != self.account.casefold():
                raise Failure("Authenticated GitHub account does not match --account; no writes attempted.")

    def request(self, method, path, payload=None, missing=False, binary=None):
        url = path if path.startswith("https://") else self.base + path
        parsed = urllib.parse.urlsplit(url)
        if (parsed.scheme != "https" or parsed.hostname not in
                {"api.github.com", "uploads.github.com"} or parsed.username or
                parsed.password or parsed.port not in (None, 443) or parsed.fragment):
            raise Failure("Refused non-allowlisted GitHub URL.")
        headers = {"Authorization": "Bearer " + self.token,
                   "Accept": "application/vnd.github+json",
                   "X-GitHub-Api-Version": "2022-11-28",
                   "User-Agent": "thunder-vector-release"}
        data = binary
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
        if data is not None:
            headers.update({"Content-Type": "application/zip" if binary is not None
                            else "application/json", "Content-Length": str(len(data))})
        try:
            request = urllib.request.Request(url, data=data, headers=headers, method=method)
            with self.opener.open(request, timeout=180 if binary is not None else 45) as response:
                scope_header = response.headers.get("X-OAuth-Scopes")
                if scope_header is not None:
                    self.scopes = [s.strip() for s in scope_header.split(",") if s.strip()]
                raw = response.read(8 * 1024 * 1024 + 1)
                if len(raw) > 8 * 1024 * 1024:
                    raise Failure("GitHub response exceeded the safe size limit.")
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            if missing and exc.code == 404:
                return None
            # Never print server bodies, request objects, credential subprocess output,
            # exception strings, Location headers, or full URLs.
            raise Failure("GitHub HTTP %d; request refused/failed; no automatic retry." % exc.code) from None
        except (urllib.error.URLError, TimeoutError, ValueError):
            raise Failure("GitHub transport/response failure; details suppressed.") from None


def picked(item, names):
    return {name: item.get(name) for name in names.split()}


def release_summary(item):
    result = picked(item, "id tag_name target_commitish draft html_url")
    result["assets"] = [picked(a, "name size digest state browser_download_url")
                        for a in item.get("assets", [])]
    return result


def inspect(api):
    repo = api.request("GET", "")
    pages = api.request("GET", "/pages", missing=True)
    releases = api.request("GET", "/releases?per_page=10")
    return {"repository": picked(repo, "full_name visibility default_branch permissions"),
            "pages": picked(pages, "build_type html_url status") if pages else None,
            "releases": [release_summary(r) for r in releases],
            "oauth_scopes": api.scopes,
            "scope_note": "Header scopes are not proof of write permission; null means unavailable."}


def enable_pages(api):
    pages = api.request("GET", "/pages", missing=True)
    if not pages or pages.get("build_type") != "workflow":
        api.request("PUT" if pages else "POST", "/pages", {"build_type": "workflow"})
        pages = api.request("GET", "/pages")
    return picked(pages, "build_type html_url status")


def input_file(value, suffix=None):
    path = Path(value)
    if not path.is_absolute() or path.is_symlink() or not path.is_file():
        raise Failure("Input files must be exact absolute regular file paths.")
    if suffix and path.suffix.lower() != suffix:
        raise Failure("Release assets must be ZIP files.")
    return path.resolve(strict=True)


def resolve_tag(api, tag):
    """Test tag existence without treating /commits' missing-ref HTTP 422 as 404."""
    encoded = urllib.parse.quote(tag, safe="")
    if api.request("GET", "/git/ref/tags/" + encoded, missing=True) is None:
        return None
    # The ref object may point at an annotated-tag object, not the final commit.
    # Resolve it through the commits API; deletion or other races must fail closed.
    return api.request("GET", "/commits/" + encoded)


def positive_int(value):
    try:
        result = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("Must be a positive integer.") from None
    if result <= 0:
        raise argparse.ArgumentTypeError("Must be a positive integer.")
    return result


def publish_release(api, args):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,99}", args.tag):
        raise Failure("Use a simple version tag containing letters, digits, dot, dash or underscore.")
    if not re.fullmatch(r"[0-9a-f]{40}", args.target):
        raise Failure("Target must be the complete lowercase public commit SHA.")
    draft_id = getattr(args, "draft_id", None)
    if draft_id is not None and (type(draft_id) is not int or draft_id <= 0):
        raise Failure("Draft ID must be a positive integer.")
    notes_path = input_file(args.notes_file)
    if notes_path.stat().st_size > 200000:
        raise Failure("Release notes exceed the size limit.")
    notes = notes_path.read_text(encoding="utf-8-sig")
    assets = []
    for value in args.asset:
        path = input_file(value, ".zip")
        size = path.stat().st_size
        if not 0 < size <= 512 * 1024 * 1024 or not zipfile.is_zipfile(path):
            raise Failure("ZIP must be nonempty, recognizable and at most 512 MiB.")
        with path.open("rb") as stream:
            digest = hashlib.file_digest(stream, "sha256").hexdigest()
        assets.append((path, size, "sha256:" + digest))
    if len({p.name for p, _, _ in assets}) != len(assets):
        raise Failure("Duplicate release asset names are not allowed.")
    # Enumeration can be incomplete even with valid authentication. Check the
    # direct tag endpoint first so an existing publication is never recreated.
    tagged_release = api.request("GET", "/releases/tags/" + urllib.parse.quote(args.tag, safe=""), missing=True)
    if tagged_release is not None and tagged_release.get("draft") is not True:
        raise Failure("Refusing to modify or recreate an already published release.")
    repo = api.request("GET", "")
    if repo.get("visibility") != "public":
        raise Failure("This helper publishes only already-public repositories.")
    branch = urllib.parse.quote(repo["default_branch"], safe="")
    comparison = api.request("GET", "/compare/" + args.target + "..." + branch)
    if comparison.get("status") not in ("ahead", "identical"):
        raise Failure("Target is not an ancestor of the public default branch.")
    tag = resolve_tag(api, args.tag)
    if tag and tag.get("sha") != args.target:
        raise Failure("Existing tag resolves to another commit; refusing to move it.")
    owner = api.request("GET", "https://api.github.com/user")["login"]
    marker = "<!-- thunder-vector-release target=" + args.target + " -->"
    existing = tagged_release
    if draft_id is not None:
        existing = api.request("GET", "/releases/" + str(draft_id), missing=True)
        if existing is None or existing.get("id") != draft_id:
            raise Failure("Explicit draft ID was not found; refusing fallback creation.")
    elif existing is None:
        for page in range(1, 11):
            releases = api.request("GET", "/releases?per_page=100&page=" + str(page))
            existing = next((r for r in releases if r.get("tag_name") == args.tag), None)
            if existing or len(releases) < 100:
                break
        else:
            raise Failure("Release lookup exceeded 1000 entries; refusing ambiguous creation.")
    if existing and (not existing.get("draft") or existing.get("author", {}).get("login") != owner
                     or existing.get("tag_name") != args.tag
                     or marker not in (existing.get("body") or "")
                     or existing.get("target_commitish") != args.target):
        raise Failure("Refusing to modify a published or unrelated release.")
    payload = {"tag_name": args.tag, "target_commitish": args.target, "name": args.tag,
               "body": notes + "\n\n" + marker, "draft": True}
    release = api.request("PATCH" if existing else "POST",
                          "/releases/" + str(existing["id"]) if existing else "/releases", payload)
    endpoint = "/releases/" + str(release["id"])
    remote_assets = api.request("GET", endpoint + "/assets?per_page=100")
    if len(remote_assets) >= 100 or any(a["name"] not in {p.name for p, _, _ in assets}
                                        for a in remote_assets):
        raise Failure("Draft contains unexpected assets; no assets removed or release published.")
    verified = []
    for path, size, digest in assets:
        found = next((a for a in remote_assets if a["name"] == path.name), None)
        if not found:
            data = path.read_bytes()
            if len(data) != size or "sha256:" + hashlib.sha256(data).hexdigest() != digest:
                raise Failure("Local ZIP changed after preflight; draft preserved.")
            url = api.base.replace("api.github.com", "uploads.github.com") + endpoint + "/assets?"
            found = api.request("POST", url + urllib.parse.urlencode({"name": path.name}), binary=data)
        if found.get("size") != size or found.get("digest") != digest or found.get("state") != "uploaded":
            raise Failure("Remote ZIP size/digest/state mismatch; draft preserved, no replacement attempted.")
        verified.append({"name": path.name, "size": size, "sha256": digest[7:]})
    # Re-read authoritative metadata after all uploads, including resumed drafts.
    current = api.request("GET", endpoint)
    final_assets = api.request("GET", endpoint + "/assets?per_page=100")
    expected = {p.name: (size, digest, "uploaded") for p, size, digest in assets}
    actual = {a["name"]: (a.get("size"), a.get("digest"), a.get("state")) for a in final_assets}
    if (not current.get("draft") or current.get("author", {}).get("login") != owner
            or current.get("tag_name") != args.tag
            or current.get("target_commitish") != args.target
            or marker not in (current.get("body") or "")
            or len(final_assets) != len(expected) or actual != expected):
        raise Failure("Draft changed or final asset verification failed; refusing publication.")
    if args.publish:
        tag = resolve_tag(api, args.tag)
        if tag and tag.get("sha") != args.target:
            raise Failure("Tag changed during upload; draft preserved.")
        api.request("PATCH", endpoint, {"draft": False})
    final = api.request("GET", endpoint)
    if args.publish:
        published_assets = api.request("GET", endpoint + "/assets?per_page=100")
        actual = {a["name"]: (a.get("size"), a.get("digest"), a.get("state"))
                  for a in published_assets}
        if (final.get("draft") is not False or final.get("tag_name") != args.tag
                or final.get("target_commitish") != args.target
                or final.get("author", {}).get("login") != owner
                or marker not in (final.get("body") or "")
                or len(published_assets) != len(expected) or actual != expected):
            raise Failure("Release is already public; post-publication audit mismatch requires manual inspection. No deletion attempted.")
        final["assets"] = published_assets
    result = release_summary(final)
    result["verified_uploads"] = verified
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("inspect", "enable-pages", "release", "actions"):
        sub = commands.add_parser(name)
        sub.add_argument("--repo", required=True, help="GitHub OWNER/REPOSITORY")
        sub.add_argument("--account", help="Select an existing GCM username and verify its GitHub API identity; never log in")
        if name == "release":
            sub.add_argument("--tag", required=True)
            sub.add_argument("--target", required=True)
            sub.add_argument("--notes-file", required=True)
            sub.add_argument("--asset", required=True, action="append")
            sub.add_argument("--draft-id", type=positive_int, help="Resume only this known owned draft; never create a fallback")
            sub.add_argument("--publish", action="store_true", help="Publish only after upload verification")
        if name == "actions":
            sub.add_argument("--run-id", type=int, help="Optional single workflow run status")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", args.repo):
        raise Failure("Repository must be OWNER/REPOSITORY, not a URL.")
    api = GitHub(args.repo, account=args.account)
    if args.command == "inspect":
        result = inspect(api)
    elif args.command == "enable-pages":
        result = enable_pages(api)
    elif args.command == "release":
        result = publish_release(api, args)
    else:
        path = "/actions/runs/" + str(args.run_id) if args.run_id else "/actions/runs?per_page=10"
        response = api.request("GET", path)
        runs = [response] if args.run_id else response.get("workflow_runs", [])
        result = {"runs": [picked(r, "id name head_sha status conclusion html_url") for r in runs]}
    print(json.dumps(result, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    try:
        main()
    except Failure as error:
        print("ERROR: " + str(error), file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("ERROR: Local input/process failure; details suppressed to protect credentials.", file=sys.stderr)
        sys.exit(1)

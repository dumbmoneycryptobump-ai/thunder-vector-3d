"""Offline publication regression tests: no credentials, network or real writes.

Run: python -B -m unittest tools.test_publication_tools
All Git/API/file mutation boundaries are mocked; fake credentials are generated
in memory and never represent real accounts or tokens.
"""
import hashlib
import io
import json
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import MagicMock, patch
import urllib.error

from tools import github_release as release
from tools import publish_snapshot as snapshot

SHA = "a" * 40
PUBLIC = "b" * 40
PAYLOAD = b"synthetic ZIP contents"
DIGEST = "sha256:" + hashlib.sha256(PAYLOAD).hexdigest()
MARKER = "<!-- thunder-vector-release target=" + SHA + " -->"


class MemoryFile:
    name = "release.zip"

    def stat(self):
        return SimpleNamespace(st_size=len(PAYLOAD))

    def open(self, mode):
        return io.BytesIO(PAYLOAD)

    def read_bytes(self):
        return PAYLOAD

    def read_text(self, **kwargs):
        return "Reviewed release notes"


class FakeGitHub:
    base = "https://api.github.com/repos/example/game"

    def __init__(self, *, existing=None, comparison="ahead", pre_change=None,
                 post_change=None, upload_digest=DIGEST, changed_tag=False):
        self.existing = existing
        self.comparison = comparison
        self.pre_change = pre_change
        self.post_change = post_change
        self.upload_digest = upload_digest
        self.changed_tag = changed_tag
        self.tag_reads = 0
        self.assets = []
        self.published = False
        self.calls = []

    def metadata(self):
        result = {"id": 7, "tag_name": "v2", "target_commitish": SHA,
                  "draft": not self.published, "author": {"login": "test-owner"},
                  "body": MARKER, "assets": list(self.assets)}
        change = self.post_change if self.published else self.pre_change if self.assets else None
        if change in ("tag_name", "target_commitish", "body"):
            result[change] = "changed"
        elif change == "author":
            result["author"] = {"login": "another-owner"}
        elif change == "draft":
            result["draft"] = True
        return result

    def request(self, method, path, payload=None, **kwargs):
        self.calls.append((method, path, payload))
        if path == "":
            return {"visibility": "public", "default_branch": "main"}
        if path.startswith("/compare/"):
            return {"status": self.comparison}
        if path.startswith("/commits/"):
            self.tag_reads += 1
            return {"sha": PUBLIC} if self.changed_tag and self.tag_reads > 1 else None
        if path.endswith("/user"):
            return {"login": "test-owner"}
        if path.startswith("/releases?"):
            return [self.existing] if self.existing else []
        if "/assets?" in path:
            if method == "POST":
                asset = {"name": "release.zip", "size": len(PAYLOAD),
                         "digest": self.upload_digest, "state": "uploaded"}
                self.assets.append(asset)
                return dict(asset)
            assets = [dict(a) for a in self.assets]
            if self.published and self.post_change in ("size", "digest", "state"):
                assets[0][self.post_change] = "changed"
            if self.assets and self.pre_change == "extra_asset":
                assets.append({"name": "unexpected.zip"})
            return assets
        if method == "PATCH" and payload == {"draft": False}:
            self.published = True
        return self.metadata()


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.enterContext(patch.object(release, "input_file", return_value=MemoryFile()))
        self.enterContext(patch.object(release.zipfile, "is_zipfile", return_value=True))
        self.args = SimpleNamespace(tag="v2", target=SHA, notes_file="mock-notes",
                                    asset=["mock-zip"], publish=False)

    def test_default_stays_draft(self):
        api = FakeGitHub()
        result = release.publish_release(api, self.args)
        self.assertTrue(result["draft"])
        self.assertFalse(api.published)
        self.assertEqual(result["verified_uploads"][0]["sha256"], DIGEST[7:])

    def test_explicit_publish_verifies_authoritative_assets(self):
        self.args.publish = True
        api = FakeGitHub()
        result = release.publish_release(api, self.args)
        self.assertFalse(result["draft"])
        self.assertEqual(result["assets"][0]["digest"], DIGEST)
        self.assertEqual(api.calls[-1][0], "GET")
        self.assertNotIn("DELETE", [c[0] for c in api.calls])

    def test_private_or_unrelated_commit_refused_before_writes(self):
        for status in ("behind", "diverged"):
            with self.subTest(status=status):
                api = FakeGitHub(comparison=status)
                with self.assertRaisesRegex(release.Failure, "not an ancestor"):
                    release.publish_release(api, self.args)
                self.assertTrue(all(c[0] == "GET" for c in api.calls))

    def test_published_and_unowned_releases_are_immutable(self):
        for change in ({"draft": False}, {"author": {"login": "another-owner"}},
                       {"body": "unrelated draft"}, {"target_commitish": PUBLIC}):
            with self.subTest(change=change):
                existing = FakeGitHub().metadata()
                existing.update(change)
                api = FakeGitHub(existing=existing)
                with self.assertRaisesRegex(release.Failure, "published or unrelated"):
                    release.publish_release(api, self.args)
                self.assertTrue(all(c[0] == "GET" for c in api.calls))

    def test_owned_draft_can_resume_without_reupload(self):
        api = FakeGitHub(existing=FakeGitHub().metadata())
        api.assets = [{"name": "release.zip", "size": len(PAYLOAD),
                       "digest": DIGEST, "state": "uploaded"}]
        release.publish_release(api, self.args)
        self.assertFalse(any(c[0] == "POST" for c in api.calls))

    def test_upload_digest_mismatch_never_publishes(self):
        self.args.publish = True
        api = FakeGitHub(upload_digest="sha256:incorrect")
        with self.assertRaisesRegex(release.Failure, "digest/state mismatch"):
            release.publish_release(api, self.args)
        self.assertFalse(api.published)

    def test_final_tag_race_and_other_draft_changes_never_publish(self):
        self.args.publish = True
        for field in ("tag_name", "target_commitish", "body", "author", "extra_asset"):
            with self.subTest(field=field):
                api = FakeGitHub(pre_change=field)
                with self.assertRaisesRegex(release.Failure, "Draft changed"):
                    release.publish_release(api, self.args)
                self.assertFalse(api.published)

    def test_tag_commit_changed_during_upload_never_publishes(self):
        self.args.publish = True
        api = FakeGitHub(changed_tag=True)
        with self.assertRaisesRegex(release.Failure, "Tag changed"):
            release.publish_release(api, self.args)
        self.assertFalse(api.published)

    def test_postpublication_mismatch_reports_public_state_without_deleting(self):
        self.args.publish = True
        for field in ("tag_name", "target_commitish", "body", "author", "draft",
                      "size", "digest", "state"):
            with self.subTest(field=field):
                api = FakeGitHub(post_change=field)
                with self.assertRaisesRegex(release.Failure, "already public"):
                    release.publish_release(api, self.args)
                self.assertTrue(api.published)
                self.assertNotIn("DELETE", [c[0] for c in api.calls])

    def test_short_commit_and_duplicate_asset_names_are_refused(self):
        self.args.target = "main"
        with self.assertRaisesRegex(release.Failure, "complete lowercase"):
            release.publish_release(FakeGitHub(), self.args)
        self.args.target = SHA
        self.args.asset.append("another-mock-zip")
        with self.assertRaisesRegex(release.Failure, "Duplicate"):
            release.publish_release(FakeGitHub(), self.args)


class AuthenticationTests(unittest.TestCase):
    def test_inspect_is_read_only_and_pages_requires_explicit_command(self):
        api = MagicMock(scopes=["repo"])
        api.request.side_effect = [{"visibility": "public"}, None, []]
        self.assertIsNone(release.inspect(api)["pages"])
        self.assertTrue(all(call.args[0] == "GET" for call in api.request.call_args_list))
        for initial, methods in ((None, ["GET", "POST", "GET"]),
                                 ({"build_type": "legacy"}, ["GET", "PUT", "GET"]),
                                 ({"build_type": "workflow"}, ["GET"])):
            with self.subTest(initial=initial):
                api = MagicMock()
                api.request.side_effect = [initial, {}, {"build_type": "workflow"}]
                release.enable_pages(api)
                self.assertEqual([call.args[0] for call in api.request.call_args_list], methods)

    def test_gcm_output_captured_and_trace_disabled(self):
        result = SimpleNamespace(returncode=0, stdout="username=test\npassword=synthetic-value\n",
                                 stderr="private details")
        with patch.object(release.subprocess, "run", return_value=result) as run:
            self.assertEqual(release.credential(), "synthetic-value")
        args = run.call_args
        self.assertNotIn("synthetic-value", repr(args))
        self.assertEqual(args.kwargs["stdout"], release.subprocess.PIPE)
        self.assertEqual(args.kwargs["stderr"], release.subprocess.PIPE)
        env = args.kwargs["env"]
        self.assertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        self.assertEqual(env["GCM_INTERACTIVE"], "Never")
        self.assertFalse(any(k.startswith(("GIT_TRACE", "GCM_TRACE")) for k in env))
        self.assertNotIn("GIT_CURL_VERBOSE", env)

    def test_allowlist_and_redirect_error_redaction(self):
        with patch.object(release, "credential", return_value="synthetic-value"):
            api = release.GitHub("example/game")
        with patch.object(api.opener, "open") as opener:
            for url in ("https://invalid.example/x", "https://api.github.com.invalid.example/x",
                        "https://u:p@api.github.com/x", "https://api.github.com:444/x",
                        "https://api.github.com/x#fragment"):
                with self.subTest(url=url), self.assertRaises(release.Failure):
                    api.request("GET", url)
            opener.assert_not_called()
        error = urllib.error.HTTPError("https://api.github.com/x", 302, "PRIVATE",
                                       {"Location": "https://invalid.example/PRIVATE"},
                                       io.BytesIO(b"PRIVATE"))
        with patch.object(api.opener, "open", side_effect=error):
            with self.assertRaises(release.Failure) as caught:
                api.request("GET", "/x")
        self.assertIn("302", str(caught.exception))
        self.assertNotIn("PRIVATE", str(caught.exception))
        self.assertIsNone(release.NoRedirect().redirect_request(None, None, 302, "", {}, "x"))


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        anchor = Path.cwd().anchor
        self.source = Path(anchor) / "publication-mock-source"
        self.destination = Path(anchor) / "publication-mock-destination"
        self.source_tree = {"README.md": {"mode": "100644", "oid": "new"},
                            "new.txt": {"mode": "100644", "oid": "new"},
                            "docs/X_HANDOFF.json": {"mode": "100644", "oid": "private"}}
        self.public_tree = {"README.md": {"mode": "100644", "oid": "old"},
                            "retained.txt": {"mode": "100644", "oid": "old"},
                            "logs/old.md": {"mode": "100644", "oid": "old"}}

    def plan(self, target_exists=False, data=PAYLOAD):
        with patch.object(snapshot, "validate_destination", return_value=(self.destination, PUBLIC)), \
                patch.object(snapshot, "tracked_tree", side_effect=[self.source_tree, self.public_tree]), \
                patch.object(snapshot, "destination_path", return_value=MagicMock(exists=lambda: target_exists)), \
                patch.object(snapshot, "git", return_value=data):
            return snapshot.plan_snapshot(self.source, self.destination, SHA)[1]

    def test_denylist_preserves_public_source_and_license(self):
        for name in ("docs/早期參考稿/a.png", "reference_images/title_card.jpg",
                     "reference_images/gameplay_visual_target.jpg", "docs/X_HANDOFF.json",
                     "MANIFEST_SHA256.txt", "logs/run.md", "build/export.zip", "game/.godot/cache",
                     ".codex/config.toml", ".env.prod", "credentials.json", "game/export_credentials.cfg",
                     "secret.key", "game.wasm", "tools/x.pyc"):
            with self.subTest(name=name):
                self.assertIsNotNone(snapshot.exclusion(name))
        for name in ("LICENSE", ".codex/config.toml.example", ".github/workflows/web-pages.yml",
                     "game/assets/a.png", "reference_images/asset_contact_sheet.png"):
            with self.subTest(name=name):
                self.assertIsNone(snapshot.exclusion(name))

    def test_traversal_and_windows_aliases_refused(self):
        for name in ("../x", "/abs", "a\\b", "a:b", "a//b", "CON.txt", "a/../b", "a.", "a\nfile"):
            with self.subTest(name=name), self.assertRaises(snapshot.Failure):
                snapshot.safe_relative(name)

    def test_tracked_commit_only_and_symlink_submodule_case_rejection(self):
        record = b"100644 blob " + SHA.encode() + b"\tREADME.md\0"
        with patch.object(snapshot, "git", return_value=record) as git:
            self.assertIn("README.md", snapshot.tracked_tree(self.source, SHA))
            git.assert_called_once_with(self.source, "ls-tree", "-rz", SHA)
        for invalid in (record.replace(b"100644", b"120000"),
                        record.replace(b"100644 blob", b"160000 commit"),
                        record + record.replace(b"README", b"readme")):
            with patch.object(snapshot, "git", return_value=invalid), self.assertRaises(snapshot.Failure):
                snapshot.tracked_tree(self.source, SHA)

    def test_plan_reports_retained_and_denied_public_paths_without_absolute_paths(self):
        plan = self.plan()
        self.assertEqual(plan["counts"], {"copy": 2, "excluded": 1, "manual_tracked_removal": 1,
                                          "retained_public_files": 1, "content_flags": 0})
        self.assertEqual(plan["manual_tracked_removal"][0]["path"], "logs/old.md")
        self.assertEqual(plan["retained_public_files"], ["retained.txt"])
        self.assertNotIn(str(self.destination), json.dumps(plan))
        self.assertFalse(plan["publication_ready"])

    def test_untracked_destination_collision_never_overwritten(self):
        with self.assertRaisesRegex(snapshot.Failure, "untracked/ignored"):
            self.plan(target_exists=True)

    def test_content_flags_and_unconfirmed_plan_prevent_all_writes(self):
        plan = self.plan(data=b"-----BEGIN " + b"PRIVATE KEY-----")
        self.assertEqual(plan["content_flags"][0]["reason"], "private_key")
        for confirmation in ("wrong", plan["plan_sha256"]):
            with patch.object(snapshot, "validate_destination") as validate, self.assertRaises(snapshot.Failure):
                snapshot.apply_snapshot(self.source, self.destination, plan, confirmation)
            validate.assert_not_called()

    def test_apply_uses_exact_blob_hashes_and_never_deletes_retained_paths(self):
        plan = self.plan()
        targets = {}

        class Writer(io.BytesIO):
            def __init__(self, target):
                super().__init__()
                self.target = target

            def __exit__(self, *args):
                self.target.read_bytes.return_value = self.getvalue()
                self.close()

        def target_for(destination, name):
            if name not in targets:
                target = MagicMock()
                target.open.side_effect = lambda mode: Writer(target)
                targets[name] = target
            return targets[name]

        with patch.object(snapshot, "validate_destination"), \
                patch.object(snapshot, "destination_path", side_effect=target_for), \
                patch.object(snapshot, "git", return_value=PAYLOAD) as git:
            snapshot.apply_snapshot(self.source, self.destination, plan, plan["plan_sha256"])
        self.assertEqual(set(targets), {"README.md", "new.txt"})
        targets["README.md"].open.assert_called_once_with("wb")
        targets["new.txt"].open.assert_called_once_with("xb")
        for target in targets.values():
            target.unlink.assert_not_called()
            self.assertEqual(target.read_bytes(), PAYLOAD)
        self.assertTrue(all(call.args[1:3] == ("cat-file", "blob") for call in git.call_args_list))

    def test_changed_blob_is_refused_before_opening_destination(self):
        plan = self.plan()
        target = MagicMock()
        with patch.object(snapshot, "validate_destination"), \
                patch.object(snapshot, "destination_path", return_value=target), \
                patch.object(snapshot, "git", return_value=b"changed blob"), \
                self.assertRaisesRegex(snapshot.Failure, "differs from the reviewed plan"):
            snapshot.apply_snapshot(self.source, self.destination, plan, plan["plan_sha256"])
        target.open.assert_not_called()

    def fake_git(self, status=b"", flags=b"H README.md\0", head=PUBLIC):
        def call(repository, *args):
            replies = {("rev-parse", "--show-toplevel"): str(self.destination).encode(),
                       ("rev-parse", "--is-inside-work-tree"): b"true",
                       ("rev-parse", "--verify", SHA + "^{commit}"): SHA.encode(),
                       ("rev-parse", "refs/remotes/origin/main"): PUBLIC.encode(),
                       ("rev-parse", "HEAD"): head.encode(),
                       ("status", "--porcelain=v1", "-z", "--untracked-files=all"): status,
                       ("ls-files", "-v", "-z"): flags}
            return replies[args]
        return call

    def test_destination_dirty_private_head_and_hidden_flags_refused(self):
        self.enterContext(patch.object(Path, "is_dir", return_value=True))
        self.enterContext(patch.object(snapshot, "no_links", side_effect=lambda p: p.resolve()))
        with patch.object(snapshot, "git", side_effect=self.fake_git()):
            self.assertEqual(snapshot.validate_destination(self.source, self.destination, SHA)[1], PUBLIC)
        for kwargs in ({"status": b" M README.md\0"}, {"flags": b"h README.md\0"},
                       {"flags": b"S README.md\0"}, {"head": SHA}):
            with self.subTest(kwargs=kwargs), patch.object(snapshot, "git", side_effect=self.fake_git(**kwargs)), \
                    self.assertRaises(snapshot.Failure):
                snapshot.validate_destination(self.source, self.destination, SHA)

    def test_overlapping_source_destination_refused_before_git(self):
        with patch.object(Path, "is_dir", return_value=True), \
                patch.object(snapshot, "no_links", side_effect=lambda p: p.resolve()), \
                patch.object(snapshot, "git") as git:
            for destination in (self.source, self.source / "nested", self.source.parent):
                with self.subTest(destination=destination), self.assertRaises(snapshot.Failure):
                    snapshot.validate_destination(self.source, destination, SHA)
            git.assert_not_called()

    def test_reparse_and_hardlink_targets_refused(self):
        with patch.object(Path, "lstat", return_value=SimpleNamespace(st_mode=0, st_file_attributes=0x400)):
            with self.assertRaisesRegex(snapshot.Failure, "reparse"):
                snapshot.no_links(self.destination)
        target = MagicMock()
        target.is_relative_to.return_value = True
        target.exists.return_value = True
        target.is_file.return_value = True
        target.stat.return_value = SimpleNamespace(st_nlink=2)
        with patch.object(snapshot, "no_links", return_value=target):
            with self.assertRaisesRegex(snapshot.Failure, "hard link"):
                snapshot.destination_path(self.destination, "README.md")


if __name__ == "__main__":
    unittest.main()

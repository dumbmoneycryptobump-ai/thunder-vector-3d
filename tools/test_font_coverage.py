"""Offline, dependency-free checks for the bundled Google Fonts Noto Sans TC.

This inspects Unicode cmap tables, not a renderer. Run from any directory:
    python tools/test_font_coverage.py
Real browser capture remains required to establish font integration/rendering.
"""
import hashlib
from pathlib import Path
import struct
import unittest


ROOT = Path(__file__).resolve().parents[1]
FONT = ROOT / "game/assets/fonts/NotoSansTC-Variable.ttf"
LICENSE = ROOT / "docs/licenses/OFL_NotoSansTC.txt"
FONT_BLOB = "82943579ad39c281212df8f14ac999824694a6ab"
LICENSE_BLOB = "1c9f43281b8f216c5461fe9ac729afbade7724e4"
FONT_SHA256 = "864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f"
LICENSE_SHA256 = "1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9"


def git_blob(data):
    return hashlib.sha1(b"blob " + str(len(data)).encode("ascii") + b"\0" + data).hexdigest()


def cmap_codepoints(data):
    """Read all Unicode format4/12 subtables, ignoring .notdef (glyph zero)."""
    def u16(offset):
        return struct.unpack_from(">H", data, offset)[0]

    def u32(offset):
        return struct.unpack_from(">I", data, offset)[0]

    tables = {}
    for index in range(u16(4)):
        record = 12 + index * 16
        tables[data[record:record + 4]] = u32(record + 8)
    base = tables[b"cmap"]
    codepoints = set()
    formats = set()
    for index in range(u16(base + 2)):
        record = base + 4 + index * 8
        platform, encoding = u16(record), u16(record + 2)
        if platform != 0 and not (platform == 3 and encoding in (1, 10)):
            continue
        start = base + u32(record + 4)
        kind = u16(start)
        formats.add(kind)
        if kind == 12:
            for group in range(u32(start + 12)):
                offset = start + 16 + group * 12
                first, last, glyph = struct.unpack_from(">III", data, offset)
                codepoints.update(range(first + (1 if glyph == 0 else 0), last + 1))
        elif kind == 4:
            count = u16(start + 6) // 2
            end_codes = start + 14
            start_codes = end_codes + count * 2 + 2
            deltas = start_codes + count * 2
            ranges = deltas + count * 2
            for segment in range(count):
                first, last = u16(start_codes + segment * 2), u16(end_codes + segment * 2)
                delta = u16(deltas + segment * 2)
                range_at = ranges + segment * 2
                relative = u16(range_at)
                for point in range(first, min(last, 0xFFFE) + 1):
                    glyph = u16(range_at + relative + 2 * (point - first)) if relative else point
                    glyph = ((glyph + delta) & 0xFFFF) if glyph or not relative else 0
                    if glyph:
                        codepoints.add(point)
    if not codepoints or not formats.intersection({4, 12}):
        raise ValueError("No usable Unicode cmap format4/12 subtable")
    return codepoints, formats


class FontCoverageTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.font_bytes = FONT.read_bytes()
        cls.points, cls.formats = cmap_codepoints(cls.font_bytes)

    def test_pinned_original_font(self):
        self.assertEqual(len(self.font_bytes), 11941968)
        self.assertEqual(git_blob(self.font_bytes), FONT_BLOB)
        self.assertEqual(hashlib.sha256(self.font_bytes).hexdigest(), FONT_SHA256)
        self.assertIn(12, self.formats)

    def test_official_license_copied_exactly(self):
        license_bytes = LICENSE.read_bytes()
        self.assertEqual(len(license_bytes), 4388)
        self.assertEqual(git_blob(license_bytes), LICENSE_BLOB)
        self.assertEqual(hashlib.sha256(license_bytes).hexdigest(), LICENSE_SHA256)
        self.assertIn(b"SIL OPEN FONT LICENSE Version 1.1", license_bytes)

    def test_runtime_source_printable_characters(self):
        source = "".join(path.read_text(encoding="utf-8-sig") for path in sorted((ROOT / "game/scripts").glob("*.gd")))
        required = {ord(char) for char in source if char.isprintable()}
        missing = sorted(required - self.points)
        self.assertFalse(missing, "Missing runtime-source glyphs: " + " ".join("U+%04X %s" % (point, chr(point)) for point in missing))
        cjk = sum(0x3400 <= point <= 0x9FFF for point in required)
        print("FONT_COVERAGE runtime_printable=%d runtime_cjk=%d cmap_total=%d formats=%s missing=%d" % (len(required), cjk, len(self.points), sorted(self.formats), len(missing)))

    def test_current_hud_symbols(self):
        required = "♥♡←→↑↓−＋×·／"
        self.assertFalse([char for char in required if ord(char) not in self.points], "HUD symbol is missing from bundled font")


if __name__ == "__main__":
    unittest.main(verbosity=2)

from __future__ import annotations

import struct
import tempfile
import unittest
from pathlib import Path

from tools.verify_project import read_png_dimensions


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class PngDimensionReaderTests(unittest.TestCase):
    def read_header(self, data: bytes) -> tuple[int, int]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.png"
            path.write_bytes(data)
            return read_png_dimensions(path)

    def test_reads_valid_ihdr_dimensions(self) -> None:
        header = PNG_SIGNATURE + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 512, 256)
        self.assertEqual(self.read_header(header), (512, 256))

    def test_rejects_truncated_header(self) -> None:
        with self.assertRaisesRegex(ValueError, "invalid PNG"):
            self.read_header(PNG_SIGNATURE + b"short")

    def test_rejects_chunk_before_ihdr(self) -> None:
        header = PNG_SIGNATURE + struct.pack(">I", 1) + b"sRGB" + b"\x00" * 8
        with self.assertRaisesRegex(ValueError, "invalid PNG"):
            self.read_header(header)

    def test_rejects_invalid_ihdr_length(self) -> None:
        header = PNG_SIGNATURE + struct.pack(">I", 12) + b"IHDR" + struct.pack(">II", 512, 256)
        with self.assertRaisesRegex(ValueError, "IHDR chunk length"):
            self.read_header(header)

    def test_rejects_zero_dimensions(self) -> None:
        header = PNG_SIGNATURE + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 0, 256)
        with self.assertRaisesRegex(ValueError, "positive"):
            self.read_header(header)


if __name__ == "__main__":
    unittest.main()

# Bundled Noto Sans TC — 2026-10-04

The game bundles the complete, unmodified Google Fonts distribution of Noto Sans TC so Godot's Chinese interface does not depend on an operating-system font fallback in Web exports. This is third-party font software under SIL Open Font License 1.1, not an original game-art asset and not relicensed under the game's MIT or original-asset grant.

## Pinned official source

- Repository: [google/fonts](https://github.com/google/fonts).
- Commit: [`3be1884c48c3e45b52ecc725676a08f87776373e`](https://github.com/google/fonts/commit/3be1884c48c3e45b52ecc725676a08f87776373e).
- Upstream file: [`ofl/notosanstc/NotoSansTC[wght].ttf`](https://github.com/google/fonts/blob/3be1884c48c3e45b52ecc725676a08f87776373e/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf).
- Direct pinned font download: [raw TTF](https://raw.githubusercontent.com/google/fonts/3be1884c48c3e45b52ecc725676a08f87776373e/ofl/notosanstc/NotoSansTC%5Bwght%5D.ttf).
- Direct pinned license download: [OFL.txt](https://raw.githubusercontent.com/google/fonts/3be1884c48c3e45b52ecc725676a08f87776373e/ofl/notosanstc/OFL.txt).
- Local font: `game/assets/fonts/NotoSansTC-Variable.ttf` (`res://assets/fonts/NotoSansTC-Variable.ttf`). Only the filename was simplified; the binary bytes and internal names are unchanged. No subsetting, conversion, glyph modification, proprietary Windows font extraction, or font-building dependency was used.
- Local complete copyright and license: `docs/licenses/OFL_NotoSansTC.txt`. Native/Web packages must distribute that notice with the font. The font remains under OFL 1.1.

| File | Bytes | SHA-256 | Git blob SHA-1 from pinned official repository |
|---|---:|---|---|
| NotoSansTC-Variable.ttf | 11,941,968 | `864727d210d54f2537bbe23b3a839436c3992af72de9322af5270897246bd44f` | `82943579ad39c281212df8f14ac999824694a6ab` |
| OFL_NotoSansTC.txt | 4,388 | `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9` | `1c9f43281b8f216c5461fe9ac729afbade7724e4` |

The local Git blob hashes match the entries returned by GitHub's official contents API at the pinned commit. The upstream copyright notice and reserved-name terms are retained verbatim in the license file.

## Offline validation

Run from the source repository:

```text
python tools/test_font_coverage.py
```

The dependency-free test parses Unicode cmap formats 4 and 12, excludes glyph-zero mappings, checks the exact binary/license hashes, and verifies every printable character currently present in `game/scripts/*.gd`. It also checks the HUD characters `♥♡←→↑↓−＋×·／` explicitly. This intentionally covers source comments as well as runtime strings, making additions conservative rather than silently missing a new Chinese label.

Actual initial result: 4 tests passed; 318 printable source characters, including 212 CJK characters, were covered. The font maps 20,745 Unicode code points; missing required characters: 0. The TTF advertises cmap formats 4, 12 and 14; variation-sequence format 14 is not needed for the checked plain-text labels. Both heart glyphs are covered, so an ASCII substitution is not required by glyph coverage.

This is a font-data coverage result, not proof that a theme is applied correctly or a browser has rendered the text. Actual native/Web captures must separately verify the integrated interface. No browser or device result is invented here.

# Thunder Vector 3D — Arcade Wingman Art Provenance

- Generated: 2026-10-04
- Mode: built-in OpenAI ImageGen, new-image generation, `transparent_background: true`.
- Project asset: `game/assets/generated/wingman_imagegen_v1.png`.
- Provider original: `$CODEX_HOME/generated_images/01a099f1-5138-7393-9c7f-f1444c8eacd4/exec-d128fc4a-9fd8-4401-816d-2a33d0626b19.png`.
- SHA-256 (original and project copy): `debb4e9f2189d17cc1da1e827404ed6fae9521a8cc749d051b236dfcda8d8177`.
- Dimensions and format: 1254 × 1254 pixels, RGBA PNG.

## Origin and inspection

Original white/gold/cyan escort-drone design generated for this project, after viewing the existing original `player_ship_imagegen_v1.png` for fleet style. The generation used a text prompt only, without an image edit target or external commercial reference. The provider original is retained; the project asset is a byte-for-byte copy, with no programmatic background removal, resizing, or recompression.

Visual inspection confirmed a centered orthographic top-down ship with nose upward, two rear engines, full uncut silhouette and contained cyan exhaust. There is no text, logo, floor, cast shadow, or baked checkerboard.

Read-only PowerShell/System.Drawing Bitmap.LockBits inspection scanned every pixel. Alpha spans 0..255; every outermost-border pixel is exactly alpha 0 (including all corners). Visible bounds at alpha > 2/255 are inclusive `(164, 164, 1091, 1042)`, giving at least 12.9% clear silhouette margin on every edge. There are 1,198,879 pixels with alpha <= 2/255 out of 1,572,516 total (approximately 76.24%). This exceeds the project's <= 0.01 transparent-border tolerance. The image was accepted on the first generation without an edit retry.

Runtime use is local PNG only; no network or AI service is required by the game.

## Final generation prompt

```text
Use case: stylized-concept
Asset type: one original transparent PNG wingman escort drone sprite for Thunder Vector 3D, a top-down 2.5D arcade space shooter.
Scene/backdrop: genuinely transparent alpha background, clean isolated sprite with nothing behind or around it.
Subject: a compact original unmanned dual-engine escort spacecraft, matching a polished heroic white-and-cyan player starfighter fleet but with a distinctly shorter and wider drone silhouette. Pearl-white ceramic armor, tasteful warm gold panel accents, cyan-blue luminous central energy lens and engine throats, dark gunmetal mechanical joints. Symmetrical compact arrowhead center, short swept wings, exactly two stout rear engine nacelles. Nose points straight UP toward the top of the image.
Style/medium: polished detailed 3D-rendered game sprite with crisp beveled hard-surface plating, readable big shapes and restrained highlights; small blue/cyan emissive accents, not photoreal photography, original non-franchise design.
Composition/framing: exact orthographic TOP-DOWN overhead camera, no perspective or angled view. Centered complete ship on square canvas. Every part of the hull, wing tips and short engine exhaust is contained within the central 76 percent of the image; leave at least 10 percent completely empty transparent padding on all four sides. No cropped tips. Short contained cyan engine glow only.
Lighting: clean soft studio-like highlights on the object only; no ground plane, no cast shadow, no vignette, no ambient cloud.
Constraints: genuine transparent RGBA PNG cutout with alpha zero in empty outer margins; no black/white/colored background, no checkerboard graphic, no floor, no horizon, no starfield, no dust, no smoke, no particles, no motion blur, no text, no letters, no numbers, no logos or watermark. ONE object only.
```

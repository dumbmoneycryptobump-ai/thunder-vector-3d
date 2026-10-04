# Thunder Vector 3D — Content Expansion Art Provenance

- Generated: 2026-09-13
- Mode: built-in OpenAI ImageGen, four independent new-image generations.
- Selected outputs are copied byte-for-byte from provider output into this directory; no programmatic editing, background removal, resizing, or recompression was applied.
- Original designs created for the project, using prompt-only direction informed by the existing original scout, heavy and power-pickup art. No commercial-franchise reference art was supplied.
- Runtime consumes local PNGs only; no AI service or network dependency ships in the game.
- Source root below: `$CODEX_HOME/generated_images/01a099f1-5138-7393-9c7f-f1444c8eacd4/` (provider-owned originals retained).

## Selected files

| Project file | Source basename | Dimensions / format | SHA-256 |
|---|---|---|---|
| `enemy_interceptor_imagegen_v1.png` | `exec-7a8cce2b-fe33-4299-a54a-684ec973cd4c.png` | 1254 × 1254 RGBA | `72bbc7d7c305e7c721c9a471370317181e9fc54f53456ae015ee60255877146c` |
| `enemy_bomber_imagegen_v1.png` | `exec-09ac52d7-5824-491f-9071-4fce84b10e45.png` | 1254 × 1254 RGBA | `8daa85727746507a13e6c00dc6afe25d6c61e54a5aafac250e609b10550debac` |
| `pickup_shield_imagegen_v1.png` | `exec-0c5eb218-3298-4400-b213-dfcd4183d404.png` | 1254 × 1254 RGBA | `741e387e156aa9cc1af85cd093d659329b6b5faef77baf8e508b52afdc8efaf5` |
| `sector_nebula_imagegen_v1.png` | `exec-28abb621-7290-48fd-a609-647f971d28db.png` | 1774 × 887 RGB, exactly 2:1 | `d565a21c68a9dfd28d173b51c48e8cb5dc2451a745f1011591b218a738f0407c` |

## Inspection and alpha evidence

All four selected outputs were visually inspected. The enemy noses point upward, full silhouettes are visible, and there is no text, watermark, floor, or baked checkerboard. The starfield has a low-contrast dark center and a subtle off-center planet. It is a sky panorama, not a mathematically guaranteed seamless texture.

Read-only inspection used System.Drawing Bitmap.LockBits in PowerShell. All pixels were scanned (not just sampled). Threshold `alpha > 2/255` approximates the existing project's visible-alpha cutoff `alpha > 0.01` for 8-bit PNGs. Bounding boxes below are inclusive `(left, top, right, bottom)` pixel coordinates.

| File role | Alpha range | Visible bounding box | Largest alpha on outermost border | Visible border pixels |
|---|---|---|---|---|
| Interceptor | 0..255 | (133, 114, 1120, 1140) | 1/255 | 0 |
| Bomber | 0..255 | (143, 65, 1110, 1160) | 0/255 | 0 |
| Shield | 0..255 | (210, 162, 1044, 1079) | 1/255 | 0 |
| Nebula | fully opaque | full canvas | 255/255 | intentionally opaque |

The interceptor has eight and shield has thirteen near-invisible outer-border pixels at alpha 1/255; these are preserved from ImageGen and are below the existing 0.01 transparency tolerance. All border pixels, including all four corners, pass that tolerance. No claim of exact-zero alpha at every empty pixel is made.

The bomber is entirely uncut, but its top safe margin is about 5.2% and bottom about 7.4%, less than the requested 8%; this benign framing deviation was accepted rather than degrading the genuine-alpha art. The interceptor and shield exceed the requested 8% visible-silhouette margins.

## Final accepted generation prompts

### interceptor

```text
Use case: stylized-concept
Asset type: original transparent PNG enemy sprite for a top-down 2.5D arcade space shooter.
Scene/backdrop: genuinely transparent alpha background, no background color or checkerboard.
Subject: one small sleek fast interceptor fighter with sharply forked wings and a compact central cockpit. Nose points exactly UP. Symmetrical graphite metallic hull, emerald and lime luminous energy accents, three clear major forms. No commercial game designs.
Style/medium: polished detailed 3D-rendered game sprite, clean hard-surface bevels and contained specular highlights, crisp silhouette legible at small size.
Composition/framing: exact orthographic TOP-DOWN overhead camera, no perspective, centered full object; square image, at least 8 percent completely empty transparent margin on every side; all wing tips and thrusters fully contained.
Lighting: contained pale highlights, minimal glow confined close to hull, no floor shadow.
Constraints: isolated single ship, true alpha PNG cutout; no text, no symbols, no letters, no watermark, no ground, no horizon, no motion blur, no additional objects.
```

### bomber

```text
Use case: stylized-concept
Asset type: original transparent PNG enemy sprite for a top-down 2.5D arcade space shooter.
Scene/backdrop: genuinely transparent alpha background, no background color or checkerboard.
Subject: one broad armored siege bomber spaceship, blunt central nose points exactly UP, two prominent long forward-facing launchers flanking the central nose; broad near-rectangular armored shoulders, powerful rear engines. Symmetric ivory ceramic armor over gunmetal structure with small amber energy strips. Clearly broad and compact rather than a long slender orange fighter.
Style/medium: polished detailed 3D-rendered game sprite, clean hard-surface panels and bevels, bold readable silhouette at small scale, original design.
Composition/framing: exact orthographic TOP-DOWN overhead camera, no perspective, centered full object; square image, at least 8 percent completely empty transparent margin on all four sides, no clipped launchers or engines.
Lighting: restrained highlights and minimal contained amber glow; no cast shadow.
Constraints: isolated single ship, true alpha PNG cutout, no text, no symbols, no letters, no watermark, no background scene, no floor, no horizon, no smoke, no debris, no motion blur.
```

### shield

```text
Use case: stylized-concept
Asset type: original transparent PNG power-up pickup icon for a top-down 2.5D arcade space shooter.
Scene/backdrop: genuinely transparent alpha background, no color or checkerboard behind object.
Subject: one cyan-white energized hexagonal shield module. Six-sided compact gunmetal and white ceramic rim enclosing a bright cyan forcefield and a simple raised luminous shield-shaped emblem at center. Readable defensive shield silhouette, no words or letters.
Style/medium: polished 3D-rendered game loot icon, crisp beveled sci-fi metal, clear large shapes readable when small, original design.
Composition/framing: straight-on orthographic view, symmetrical, centered, square canvas; entire icon and contained glow visible, at least 8 percent fully transparent padding on every side.
Lighting: luminous icy cyan center with controlled highlights, glow close to object only.
Constraints: true alpha transparent PNG, isolated single icon, no floor or shadows, no text, no watermark, no circular badge outside the hexagon, no extra objects, no checkerboard.
```

### nebula

```text
Use case: stylized-concept
Asset type: original opaque deep-space panorama texture for Godot equirectangular sky in a fast arcade shooter.
Primary request: very wide 2:1 aspect ratio deep navy-black space panorama, seamless-ish matching dark left/right edges, faint flowing teal, amber, and violet nebula wisps framing an emptier dark central area. Tiny sparse stars, only one subtle small distant planet far off-center. Keep most of the image dark to preserve bright bullet visibility.
Style/medium: polished cinematic space illustration with soft atmospheric volumetric wisps, restrained low-contrast details, not a photo of an existing nebula.
Composition/framing: equirectangular 360 degree sky texture, exact 2:1 wide format if possible, no horizon or directional ground, diffuse edges suitable for wrapping, quiet and uncluttered center.
Constraints: opaque RGB image, no transparency; no ships, no text, no watermark, no grid, no large bright central star, no lens flare, no bright foreground objects, no artificial border.
```

## Rejected targeted edits

One built-in edit attempt per sprite requested cleaner empty edge bands and, for the bomber, more padding. All three edits visibly introduced baked checkerboard backgrounds and were independently confirmed RGB / alpha 255 everywhere. They were rejected and are not copied into the project. Original true-RGBA generations above are selected.

Rejected source basenames: `exec-ac7819a6-74dd-4137-a8e3-cc415bb34c8b.png`, `exec-e4512688-fde5-4262-a64d-81f304ae14fd.png`, `exec-0779fc65-fdfd-45d3-b49f-214a8a85a9ee.png`.

### Rejected interceptor edit

Input image: `exec-7a8cce2b-fe33-4299-a54a-684ec973cd4c.png` (edit target).

```text
Preserve the entire graphite-and-lime top-down interceptor design exactly. Change only the empty transparent background: remove every stray or near-invisible nonzero-alpha pixel outside the actual spaceship silhouette. The outer 8 percent of all four edges must be completely empty with alpha=0 at every pixel. Keep ship fully contained, nose UP, same shape, same colors, same framing and detail. True RGBA alpha transparency, no color matte, no checkerboard, no text. No new glow, noise, dust, shadows, grain, stars or objects. Crisp cutout.
```

### Rejected bomber edit

Input image: `exec-09ac52d7-5824-491f-9071-4fce84b10e45.png` (edit target).

```text
Preserve the ivory-and-gunmetal top-down bomber design exactly. Change only framing and background: scale the complete ship uniformly down a little to create at least 12 percent perfectly empty transparent margin on EVERY side; all cannon tips and engine ends fully inside this safe central area. Center the object. Every pixel in the outer 12 percent edge bands must be exactly alpha=0; no stray faint pixels or dust. Nose UP. Same shape, colors, details, no distortion or additional objects. True transparent RGBA PNG, no matte color or checkerboard, no shadow, no text.
```

### Rejected shield edit

Input image: `exec-0c5eb218-3298-4400-b213-dfcd4183d404.png` (edit target).

```text
Preserve the entire cyan-white hexagonal shield module icon design exactly. Change only the empty transparent background: remove every stray or near-invisible nonzero-alpha pixel outside the actual icon silhouette. All outer 10 percent edge bands must be perfectly empty, exactly alpha=0 everywhere. Keep full icon centered, identical size, shape, colors and details. True RGBA alpha transparency, no color matte, no checkerboard. No extra glow, noise, dust, shadows, grain, stars, or objects. No text. Crisp isolated cutout.
```


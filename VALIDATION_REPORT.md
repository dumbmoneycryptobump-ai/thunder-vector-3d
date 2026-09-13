# Thunder Vector 3D validation report

Date: 2026-08-29

Target: Godot 4.7.2 stable, GDScript, GL Compatibility, Windows x86_64

## Verified source and gameplay

- Official WinGet Godot reported `4.7.2.stable.official.ed1daf0bf`.
- `scripts/verify.ps1`: PASS. It requires the exact stable engine line and runs required-file/specification checks, five Python verifier tests, Godot import/parser validation, settings persistence, keyboard settings UI, seven-asset alpha/integration validation, the complete gameplay-flow test, and a fixed-60-FPS 15-second main-scene smoke.
- `GAMEPLAY_FLOW_TEST_PASS`: player-bullet combat and scoring, health/bomb/power collection, lethal-damage-before-pickup ordering, bomb clearing, boss spawn/defeat/rewards, five-shot boss-bullet pool restoration, Game Over/restart, fixed pool capacities, and `idle == created` restoration all passed.
- `ART_INTEGRATION_TEST_PASS`: seven original 1254x1254 ImageGen RGBA assets passed true-alpha, transparent-corner/border, role binding, orientation, fallback visibility, Node3D-parent and GL Compatibility assertions.
- Real windowed OpenGL 3.3 Compatibility capture passed on an AMD Radeon RX 7600 at 1280x720. `docs/screenshots/gameplay_preview.png` was visually inspected with no black boxes, clipping, wrong enemy orientation, or procedural-hull bleed-through.
- `scripts/stress_pool.ps1`: PASS after 36,000 fixed-60-FPS frames (600 simulated seconds). Pool capacities remained 96 player bullets, 128 enemy bullets, 32 scouts and 16 heavies; no exhaustion occurred and restart restored the initial node count.

## Windows export evidence

- Downloaded the official standard Godot 4.7.2 export-template TPZ (1,281,349,702 bytes).
- TPZ SHA-256 matched the official release digest: `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.
- TPZ SHA-512 matched the official release list: `ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079`.
- Installed `windows_debug_x86_64.exe`, `windows_release_x86_64.exe`, and `version.txt` under the engine's `4.7.2.stable` template directory.
- Godot successfully exported a fresh embedded-PCK Windows executable. PE parsing confirmed machine `0x8664` (x86_64), and the build script rejects missing, stale, undersized, wrong-architecture or error-text outputs.
- The release packager verifies an exact entry whitelist, includes offline Godot MIT/third-party notices and asset provenance, and recomputes the embedded EXE SHA-256 directly from the ZIP.

## Remaining platform gate

This Windows 11 host has Smart App Control in enforcement mode (`VerifiedAndReputablePolicyState=1`). The exported development EXE is unsigned, so Windows blocked it before process creation. Code Integrity recorded events 3077 and 3033 from both the Codex PowerShell runtime and signed Windows PowerShell. There is no per-file exception; Microsoft documents that unknown unsigned binaries are blocked unless they have trusted reputation or a certificate from a CA in the Trusted Root Program.

Therefore `windows_build` is deliberately **not** marked done. The exact remaining acceptance test is one of:

1. Run the exported EXE on a clean Windows VM/device where Smart App Control is not enforcing, then complete the scripted headless and windowed launch smoke; or
2. Sign the EXE with a trusted CA code-signing certificate and rerun `scripts/build_windows.ps1`.

Smart App Control was not disabled because that weakens host security and switching it off is effectively one-way without a Windows reset/reinstall. `-SkipLaunchValidation` can create an integrity-checked archive when policy blocks execution, but writes `launch_validation=skipped-by-explicit-switch` into `BUILD_INFO.txt` and never claims launch success.

## Release artifact fields

- Product: Thunder Vector 3D 1.0.0
- Runtime network dependency: none
- Code signing: unsigned
- Build provenance: the packaged `BUILD_INFO.txt` records the exact clean Git commit and Godot version used for the final rebuild.
- Final EXE and ZIP SHA-256 values: recorded in the separately delivered `SHA256SUMS.txt` and handoff capsule so this source report does not create a self-referential rebuild cycle.

## Independent peer audit

The required two-round Codex × Qwen adversarial review is distilled in `docs/PEER_AUDIT.md`. Qwen withdrew the speculative Boss-pool, art-orientation and silent-export findings; confirmed that the same-frame lethal-damage issue was real and resolved by commit `089a846`; and reported no unresolved Critical/High defect. The remaining Medium item is the explicitly disclosed Smart App Control launch gate.

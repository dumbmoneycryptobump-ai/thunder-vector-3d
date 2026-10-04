Thunder Vector 3D 1.2.0
========================

An original, offline 3D vertical shooter for Windows x86_64.

Tactical missions and world events (2026-10-04)
---------------------------------------------
- Nine cyclic timed objectives: kills, combo, supplies, overdrive, elite kills,
  continuous no-health-loss survival, actual special-weapon shots, rescue and Boss.
- Each completed mission grants points and overdrive charge exactly once.
  A timeout changes the objective without ending the run or subtracting health.
- Amber lanes warn for 2.2 seconds before a 1.6-second red pulse. Change lanes
  to avoid it; each pulse can damage the player at most once.
- Three rotating, hovering cyan rescue beacons offer additional points/charge
  and a choice between safe positioning and collecting the full rescue batch.
- Mission, overdrive and Boss notices slide/fade in with scan-line effects.
  Mobile browser status includes actual mission progress and lane warnings.
- Pause freezes new events and mission clocks. Boss combat suspends world events
  and the active rescue deadline; other mission deadlines continue normally.
- Existing four weapons, 100-shot overdrive, wingmen, maps and controls remain.
- M still toggles camera shake; it does not disable all new beacon/notice motion.

Cross-device edition (2026-10-04)
-------------------------------
- Windows keyboard/mouse controls remain unchanged.
- Gamepad: left stick / D-pad moves, A / right trigger fires, B bombs,
  X cycles weapons, Y overdrive, Start pauses, Back opens settings.
  After Game Over, A restarts. D-pad and A navigate/confirm settings.
- Browser edition has touch movement, fire and action buttons, a readable
  mobile status bar, proportional portrait/landscape layout and focus-loss pause.
- Modern browsers need WebGL 2 and WebAssembly. Browser compatibility is not
  a guarantee of every phone's performance; physical iOS/Android testing is pending.
- Browser first download requires a network; cached HTTPS PWA can reopen offline.

Expanded maps and special weapons (2026-10-04)
---------------------------------------------
- A wider combat view and approximately 89% more player movement area.
- Three distinct 3D backdrops: orbital shipyard, debris refinery and crystal citadel.
  Fixed reusable scenery stays clear of the combat corridor; an original transparent
  planet adds a distant landmark. Route and Boss progress reflect actual gameplay.
- Select the original barrage with 1, four homing explosive missiles with 2,
  lightning chaining through up to five distinct targets with 3, or dual piercing
  lasers with 4. Space / left mouse button fires the selected weapon.
- All four modes retain wingman guns and share a cooldown; switching is not a free shot.
- E temporarily overrides the selected mode with six seconds of automatic 100-shot
  volleys, including wingmen. The selected mode resumes when overdrive ends.
- Restart restores the first sector and original barrage, and clears active weapons.

Arcade overdrive expansion (2026-10-04)
--------------------------------------
- Start with two original-art wingmen; weapon rank 3 unlocks four.
- Five weapon ranks: 10 / 14 / 24 / 32 / 40 projectiles per normal barrage-mode volley.
- E activates six seconds of automatic 100-projectile volleys, including wingmen.
  Starts fully charged; kills and pickups recharge it outside overdrive.
- One-hit fodder squads, a three-second kill combo and localized impact rings/sparks.
- Cyan main shots and gold wingman shots share one batched render mesh.
- M toggles subtle camera shake for motion comfort (session-only setting).

Content expansion (2026-09-13)
------------------------------
- Four enemy types: Scout, Heavy, fast sweeping Interceptor and fan-shot Bomber.
- Four formations: patrol, paired interception, V attack and heavy escort.
- Three sector themes: Neon Front, Amber Debris and Violet Core.
  Boss defeats advance the theme; restart returns to the first sector.
- Four pickups: power, health, bomb and shield.
- Shield lasts up to 12 active-play seconds and absorbs one complete hit.
  Re-collecting refreshes the duration, without stacking; pause freezes it.
  The first destroyed Interceptor each run guarantees a shield drop.

System requirements
-------------------
- Windows 10 or Windows 11, 64-bit
- A graphics driver supporting OpenGL 3.3
- No network connection or Godot installation is required to play

Controls
--------
- WASD or arrow keys: Move
- Space or left mouse button: Fire
- 1: Original barrage
- 2: Four homing explosive missiles
- 3: Chain lightning (up to five distinct targets)
- 4: Dual piercing lasers
- B: Bomb
- E: Activate charged 100-shot overdrive
- M: Toggle camera shake
- P or Esc: Pause / resume
- O: Settings
- F3: Toggle pool diagnostics
- R or Enter: Restart after Game Over

Settings
--------
New installations default to a 1600x900 window. Existing saved display preferences
are retained; use O to change resolution or fullscreen mode.

The game stores settings under the current Windows user's Godot app-data folder:
%APPDATA%\Godot\app_userdata\Thunder Vector 3D\settings.cfg

Distribution notes
------------------
- This build is unsigned. Windows SmartScreen may show an unknown-publisher warning,
  and Windows 11 Smart App Control in enforcement mode can block unsigned apps entirely.
- Original game-asset terms are in LICENSES\LICENSE_ASSETS.txt.
- The game's MIT license is in LICENSES\THUNDER_VECTOR_LICENSE.txt.
- Godot Engine's MIT license and complete 4.7.2 third-party copyright inventory
  are included offline in the LICENSES folder.
- ImageGen prompts, asset hashes, and transparency checks are recorded in
  ART_PROVENANCE.md, CONTENT_ART_PROVENANCE.md, ARCADE_ART_PROVENANCE.md
  and MAP_ART_PROVENANCE.md.

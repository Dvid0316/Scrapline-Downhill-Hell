# Changelog

All notable changes to this project. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]: playtest tuning

### Changed
- **Turret has weight:** it accelerates, has a top speed (160°/s yaw, 90°/s pitch) and eases into the aim point instead of snapping to it. Feed-forward keeps steady tracking tight (under 1° while passing close targets). New Inspector knobs: `yaw_accel_degrees`, `pitch_accel_degrees`, `settle_rate`.
- **Barrel reticle:** an amber ring shows where the gun *actually* points (shots go there). While the turret swings it lags the cursor, with a faint line between them, and it merges with the crosshair once the gun is on target.
- **Metal impact sound** rebuilt as a short dull clank. The old one rang at 2–6 kHz and sounded like a bell at 11 rounds per second. Impacts are also quieter (−11 dB), more varied, and rate-limited to one every 70 ms.

### Tests
- New check: a big swing takes visible time, then settles on target. The tracking check now starts with the gun already on target. 39 checks in total.

## [0.2.0] - 2026-11-05: Milestone 2: Turret Combat

### Added
- **Heavy MG turret** (`scenes/weapons/heavy_mg_turret.tscn`, `MountedTurret`) mounted on the railcar's `TurretMount`, with a rotating base, an elevating gun, a recoiling barrel assembly, and a muzzle. It traverses toward the aim point at configurable speeds. Pitch limits stop it depressing into the locomotive over the front arc.
- **Mouse aiming** (`TurretInput`): the camera ray hits terrain or targets, giving a real 3D aim point that works at any elevation. The ray ignores the train. Holding LMB fires.
- **Hitscan weapon** (`HitscanWeapon`): 11 rounds per second with a frame-rate-independent cooldown accumulator, so the first shot is instant. 12 damage, 320 m range, 0.6° spread, and a tracer every 2nd round. It emits signals only and has no knowledge of effects, audio, or the HUD.
- **Damage model:** `Damageable` → `DestructibleTarget` → `ExplosiveBarrel`. Health, points awarded once, a hit flash and jolt, a scorch overlay below 50% health, a swap to wreck visuals, and area damage with chain reactions. Future enemies can implement `apply_damage()` or extend `Damageable`.
- **Target course** (`TargetCourse`): 64 targets in 13 themed clusters (barrel yards, ridge plates, bunker posts, valley depots) at varied distances and elevations. They reset on run restart.
- **Effects** (`EffectsManager`): pooled tracers, metal sparks, dirt puffs, wood splinters, and explosions (fireball, light, fire, debris, smoke). There is no per-shot node creation. Muzzle flash plus a light, and barrel recoil.
- **Audio** (`CombatAudio`): original synthesized SFX (`tools/gen_sfx.py`) for the gunshot, metal, dirt and wood impacts, explosions, and crate break. Three buses (Weapons, Impacts, Explosions), per-sound volume, gun polyphony cap, random pitch, and an impact rate limit.
- **HUD** (`CombatHud`): crosshair, hit and kill markers, score / destroyed / hits / accuracy panel, and floating kill popups.
- **Camera shake** (`FollowCamera.add_trauma`): small, lens-offset-only shake on destructions. It never comes from firing and never rotates the camera.
- Collision: terrain trimesh collider (WORLD layer), train hull boxes (TRAIN layer), target hit boxes (TARGETS layer). The layers are named in Project Settings.
- `tests/test_milestone2.gd` (38 checks) and `tests/run_all.sh`.
- Dev flags `--demo-fire` and `--bench=SECONDS`, which reports FPS and GPU/CPU frame cost.

### Changed
- `TerrainBuilder.sample_height()` now samples the built mesh grid, using the same triangle split as the mesh. Previously it used the analytic shape, which could differ by about 1 m and left props and targets floating or buried. The old function is still available as `analytic_height()`.
- On window focus, the mouse cursor is hidden and confined to the window. `Esc` releases it and a click grabs it again.
- Quitting stops the weapon and audio first, then waits a few frames, so no audio playbacks leak at exit.
- The debug overlay help now includes aim and fire.

### Fixed
- Screenshots under `captures/` are no longer imported as project assets (a `.gdignore` is created).

## [0.1.0] - 2026-11-05: Milestone 1: Moving Train Prototype

### Added
- Godot 4.7 project (`project.godot`), 1920×1080 base resolution (windowed at 1600×900 for development), Forward+.
- `RailRoute`: control-point route (about 1 km, about 64 m descent, gentle S-curves) with auto-smoothed handles.
- `TrackBuilder`: procedural ballast bed, two extruded rails, MultiMesh sleepers.
- `TerrainBuilder`: procedural heightfield with a mountain wall on the left, a valley drop on the right, and slope-based colouring.
- `PropScatter` and reusable props: rocks, cliff spires, shipping containers (2 variants), storage tank, signal post, ore-loader gantry over the track.
- Train: `TrainController` (path-following movement, configurable speed and acceleration, loop on finish) plus geometry-only `locomotive`, `armored_railcar`, and `bogie` scenes. The locomotive has a working headlight.
- `FollowCamera`: angled-overhead chase camera with track look-ahead, curve-anticipating yaw, exponential smoothing, and runtime-adjustable pitch, distance, and look-ahead.
- Debug overlay (F1) and debug keys for speed, pause, restart, and camera tuning. Esc releases the mouse.
- Lighting: procedural sky, shadowed sun, fog, SSAO, ACES tonemapping.
- Headless smoke test `tests/test_milestone1.gd`.
- Dev command-line flags: `--start-at=`, `--capture=`, `--capture-delay=`.
- README, PROJECT_SPEC, CHANGELOG.

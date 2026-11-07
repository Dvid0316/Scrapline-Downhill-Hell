# Changelog

All notable changes to this project. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## [0.7.0] - 2026-11-06: Between-wave upgrades

### Added
- **Upgrade cards.** Clearing a wave pauses the countdown and offers 3 cards. Click one, or press `1`/`2`/`3`. The guns hold fire while the cards are up, and the cursor shows. Picks stack up to each card's max level and reset with `R`. The first offer of a run always includes a new weapon. Emergency Patch is weighted up when the hull is low, and once every other card is maxed it's the only one left.
- **Tesla Coil** (new weapon, `TeslaCoil`): a procedural coil on the locomotive's hood that arcs to the nearest enemy, with chain lightning at higher levels. `LightningBolt` draws it as camera-facing additive ribbons that re-jag every frame.
- **Rocket Pod** (new weapon, `RocketPod`): a four-tube launcher on the gun car's rear deck. Its homing rockets have puff smoke trails, a proximity fuse that checks the whole step each frame, and splash damage.
- **Ricochet Rounds** (`HitscanWeapon.ricochet_bounces`), plus MG fire-rate/damage, turret-servo, cannon reload/blast, max-hull, damage-reduction (`TrainHull.damage_mult`) and full-repair cards.
- New synthesized sounds: `tesla_zap.wav`, `rocket_launch.wav`, `upgrade_pick.wav`. The existing sounds are byte-identical.
- `--upgrades=id[:n],...` dev flag, `tools/upgrade_shot.gd` screenshots, and `tests/test_upgrades.gd` (53 checks).

### Fixed
- Cannon test flake: it aimed straight through the locomotive's line of fire. Since 0.6.1 the gun lifts over the locomotive, so the shell could sail out of range. The test now aims beside the track.

## [0.6.1] - 2026-11-06: Close-range aiming fix

### Fixed
- **Shots flew over raiders right beside the train**, even with the crosshair on them (playtest report). The gun could only tip down 22°. A buggy 4–8 m from the car needs 20–40°, and enemies under the coaster trestles need 50–77°. The limit is now 85°.
- The front "don't shoot through the locomotive" rule was a fixed cone (no depression within 28° of straight ahead). It's now a real check against the locomotive's hull: the gun only lifts when the line of fire would actually pass through the cab. Targets beside or below the locomotive can be hit.

### Added
- `tools/aim_probe.gd`: parks a buggy at 30 spots around the railcar, at 3 places on the route, and reports which spots the gun can hit (90/90 now; 47/90 before).
- M3 test: raiders hugging the car on either side, and below the trestles, are hittable.

## [0.6.0] - 2026-11-06: Rollercoaster track

### Added
- **Rollercoaster section** after the original ~1 km descent. The route is now about 2.5 km: a lift hill, a 40% first drop, a second crest, camelback humps, and a final plunge into the canyon.
- **Train physics:** arcade gravity along the slope (`gravity_scale` 3×), air drag, an engine that pulls toward the set speed, and brakes that hold up to 2.8 m/s². The gentle section plays exactly as before (it holds the set speed), while the steep drops overpower the brakes. You reach about 225 km/h at the default setting and 255 km/h at full throttle, with a hard cap of 306 km/h. Climbs bleed momentum. `Space` still brakes to a stop, even on the steepest drop.
- **Trestles** (`TrestleBuilder`): wooden rollercoaster bents with splayed legs, ties, and X-bracing wherever the track flies over the ground. They're drawn as two MultiMeshes.
- **Coaster ground:** on the coaster the terrain follows the valleys, not the track. Crests stand up to ~17 m above the ground, low runs sit on embankments, and dips cut into the hills. Trackside props skip anywhere the track isn't at ground level.
- **Speed feel** (`SpeedHud`): a chunky speedometer (km/h, set-speed tick, grade arrow ▲/▼ %) that goes white → orange → red, speed lines streaming in from the screen edges, and a camera FOV kick (up to +16°) with rumble above 180 km/h.
- `--speed=KMH` dev flag. `tools/speed_profile.gd` prints a headless speed-vs-distance sim of the whole route. `tools/train_preview.gd --at=0.84 --wide` takes side views of the track.
- `tests/test_coaster.gd` (22 checks): track shape, physics (holds speed on the gentle part, drops build speed, climbs bleed it, terminal cap, braking), trestles and ground, camera and HUD at speed.

### Changed
- The camera leads by speed / smoothing, so it doesn't trail the train at high speed.
- Vegetation attempt counts scale with terrain area, which keeps the density on the longer map.
- Tests place the train at absolute distances (`TrainController.set_head_distance`) instead of route ratios, so extending the route doesn't move them. A cannon check had become flaky at the old 30% spot, which is now a steeper part of the line.
- Startup is about 3.6 s (bigger terrain). In combat on the coaster, the GPU takes about 4.6 ms per frame at 1080p.

## [0.5.2] - 2026-11-06: Readable crosshair

Playtest feedback: the crosshair blended into the bright terrain.

### Changed
- The crosshair is bigger and bolder, and **every stroke has a solid black outline**, so it shows on sand, grass, shadow, and smoke. The barrel ring and the cannon reload ring follow the crosshair colour instead of orange, which vanished on the orange dirt.
- Hot pink is the default, because nothing in the world is that colour.

### Added
- `C` cycles the crosshair colour (pink, green, cyan, yellow, white). The choice is saved to `user://settings.cfg`.
- `tools/crosshair_preview.gd` draws every colour preset over different backgrounds for a readability check.

## [0.5.1] - 2026-11-06: Detailed train cars

### Added
- `CarKit` (`scripts/train/car_kit.gd`): a small procedural modelling kit with chamfered boxes, extruded armour profiles, cylinders, rivets, and chevron stripes. It merges each car into one mesh with a surface per material, so a detailed car costs only a few draw calls.
- `CarBody`: procedural bodies for both cars.
  - **Locomotive:** sloped armoured hood and cab, louvre grilles, radiator fans, exhaust stacks, walkway railings, a visored cab with windows, beacon, horn, and antenna, twin headlights, a spiked hazard-striped V plow, a fuel tank, steps, buffers, and a scrap plate welded on.
  - **Gun car:** sloped hull, outward-leaning parapets with gun slits, hanging spaced-armour slats, an octagonal turret barbette, sandbag walls, ammo crates, jerry cans, a spare wheel, and end ladders.
- `BogieModel`: cast side frames, axle boxes, coil springs, brake shoes, and flanged, ribbed wheelsets that **spin with the train's speed**.
- `tools/train_preview.gd`: close-up beauty shots of the train from four angles.
- `sandbag` and `lamp_amber` materials.

### Changed
- Train scenes are now just bogies, a `Body`, lights, smoke emitters, and collision. Collision shapes and the turret mount are unchanged. Loco smoke emitters moved onto the new stacks.

## [0.5.0] - 2026-11-06: Stylized graphics overhaul

Art direction is now "stylized & punchy": bold saturated colours, chunky shapes,
readable silhouettes, and juicy effects.

### Added
- **Sky and lighting:** gradient sky shader with sun glow and cartoon clouds, ACES tonemapping, SSAO/SSIL, glow, aerial perspective, and a warmer, stronger sun.
- **Terrain shader** (`stylized_terrain.gdshader`): grass, dirt shoulder, gravel, and triplanar rock cliffs with strata bands. CC0 textures are remapped onto a hand-picked palette.
- **Procedural rocks** (`RockMeshes`, `ProcRock`): faceted low-poly boulders and cliff spires with a grassy cap.
- **Vegetation** (`VegetationScatter`): MultiMesh pines, bushes, and about 100k grass tufts, with wind sway.
- **Painted-metal material** (`stylized_surface.gdshader`): punchy paint with grunge, rust streaks, detail normals, and rim light. Applied to the train, enemies, and props.
- **Outline post-process** on the camera (depth and normal edges, fading out with distance). Grass opts out.
- **Toon FX** (`PuffFx`, `PuffEmitter`, `stylized_puff.gdshader`): chunky fireballs that cool from white-hot through orange to soot, lingering smoke columns, locomotive exhaust, raider dust trails, and burning wrecks.
- `CREDITS.md` for the Poly Haven CC0 textures.

### Changed
- The debug HUD is hidden by default (F1 toggles it).
- Terrain cell size 3 m, with vertex-colour masks for the shader.
- Measured cost: about 3.8 ms of GPU per frame at 1080p in combat (was about 1.9 ms).

## [0.4.0] - 2026-11-06: Heavy cannon

### Added
- **Heavy cannon** on the right mouse button (or `E`), mounted beside the MG on the same turret, so both aim together and can fire at once. 2 shells per second, 40 direct damage plus an explosive burst (up to 45 damage, 5.5 m radius, falloff toward the edge). The direct target doesn't also take the splash. Range 360 m.
- Cannon barrel, breech, and muzzle brake on the turret, with its own big recoil, muzzle flash, and light.
- Fat, short shell tracers. An explosion and sound where every shell lands. A synthesized `cannon_shot.wav` (deep boom).
- Crosshair reload ring (fills while loading, four ticks when ready). HUD hits and accuracy include cannon shells.
- `HitscanWeapon` gains `muzzle_slot`, `splash_radius`, `splash_damage`, a `splashed` signal, and `get_ready_ratio()`. `MountedTurret` muzzle, direction, and FX calls take a slot (`&"mg"` / `&"cannon"`).
- `tests/test_cannon.gd` (24 checks).

### Changed
- Explosion effect pool 5 → 8 and explosion voices 3 → 4, to make room for shell bursts.

## [0.3.0] - 2026-11-06: Milestone 3: Enemies and Waves

### Added
- **Enemies** (`scripts/enemies/`, `scenes/enemies/`), all extending `Damageable` via `EnemyBase`, so scoring, effects, and chain reactions work on them:
  - **Raider buggy** and **gun truck** (`RaiderVehicle`): chase from behind on the shoulder, hold shifting attack slots beside the train, follow the terrain, and fire bursts.
  - **Strafe drone** and **kamikaze drone** (`DroneEnemy`): fly in from ahead. Strafers dart around firing. Kamikazes arm (blink, beep, HUD bracket) and then dive for 45 hull damage. A kamikaze that's shot down explodes and damages nearby drones.
  - Movement in a train-relative track frame, hit flash and scorch, and wrecks that fall or coast in world space before being recycled.
- **Train hull** (`TrainHull`, 400 HP). Enemy rounds are hitscan against `WORLD | TRAIN`.
- **Waves** (`WaveDirector`): 5 hand-made waves, then endless scaling (+25% enemies, +10% health per wave), breathers with a countdown, +15% hull repair per cleared wave, and per-kind pooling.
- **Game over** when the hull is wrecked: a ripple of explosions, the train brakes, the gun locks, and a stats panel says "Press R". `R` starts a fresh run.
- **HUD:** wave panel (top centre), hull bar, red damage vignette and low-hull pulse, wave banners, off-screen threat arrows, kamikaze warning bracket, game-over panel. The score panel splits enemy kills from range targets.
- **Audio:** synthesized enemy gunshot, wave horn, wave-clear chime, and kamikaze beep (`tools/gen_sfx.py`). Existing sounds are unchanged.
- Red hostile tracers (`fx_tracer_hostile.tres`), enemy paint material, and physics layer 4 `enemies`.
- `tests/test_milestone3.gd` (65 checks). Dev flags `--wave=N`, `--god`, `--no-enemies`. The benchmark report includes wave, kills, and hull.

### Changed
- Reaching the end of the route now **loops without restarting the run** (`TrainController.route_looped`). Score, waves, and hull carry on, and the range targets come back.
- `RailRoute.sample_world_extended()` extrapolates past the route ends (enemies just behind the start or past the end).
- Tracer pool raised to 40 (shared by player and enemy tracers).
- `--demo-fire` prefers enemies over range targets.
- The Milestone 2 tests switch waves off (they test the range in isolation).

## [0.2.1] - 2026-11-06: Playtest tuning

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

# Scrapline: Downhill Hell: Project Spec

## Concept

A single-player, fast-paced arcade train-defense game. The player operates a
mounted weapon on an armored train that descends through dangerous industrial
and mountain environments while enemy vehicles and drones attack. The
priorities are simple controls, fast action, big enemy waves, explosive
visuals, and replayability.

## Locked design decisions

| Area | Decision |
|---|---|
| Camera | Angled overhead, **45–60° downward**, following from above and behind. Locomotive, railcar, and upcoming track stay in view. Angle and distance are adjustable during development. |
| Visual style | Realistic industrial materials, a rugged armored train, believable scale, environmental depth, restrained cinematic lighting. |
| Shooting (M2+) | Mouse-aimed turret. Left mouse button fires continuously while held. |
| Movement | The train moves automatically. The player never steers it. |
| Structure | Short, repeatable survival runs. No open world. |

## Platform and tech

- Godot 4.7, GDScript, Forward+ renderer
- Developed on CachyOS Linux
- Performance target (future, **not yet verified**): 1920×1080 at 60 FPS
- No third-party code dependencies. Geometry is original primitive/procedural work. CC0 textures (Poly Haven) are allowed and listed in `CREDITS.md`.

## Architecture (as of Milestone 1)

- **RailRoute** (`Path3D`) is the single source of truth for the line. It's
  authored as control points, with smooth handles generated automatically.
  Every other system samples it.
- **Train movement is path following**, not a physics simulation.
  `TrainController` keeps `head_distance` (metres along the route) and places
  each `TrainCar` by sampling the curve at its two bogie pivots, so the cars
  yaw on curves and pitch on grades.
- **Geometry is separate from logic.** Car scenes (`locomotive.tscn`,
  `armored_railcar.tscn`, `bogie.tscn`) contain only meshes, plus a small
  metadata script (`car_length`, `bogie_spacing`). Swapping in real models
  later won't touch the movement code.
- **TrackBuilder** extrudes the ballast and rails along the route and places
  sleepers with a MultiMesh.
- **TerrainBuilder** generates a heightfield around the route: a flat bed, a
  shoulder, a mountain wall on the left, and a valley drop on the right. Its
  `sample_height()` is analytic, so props sit on the ground without raycasts.
- **PropScatter** places reusable prop scenes along the route
  deterministically (fixed seed), with a track-clearance check.
- **FollowCamera** aims at a point ahead of the train *on the track*. Yaw
  follows the track heading sampled further ahead, so it anticipates curves.
  It uses frame-rate-independent exponential smoothing and no shake.
  Camera height = distance × sin(pitch).
- **Model convention:** front faces −Z, origin at rail-top height, metres.
- A `TurretMount` marker sits on the railcar's turret ring, and the M2 turret is instanced on it.

## Combat architecture (as of Milestone 2)

The systems are separated so each one can change without touching the others:

| Concern | Node / script | Knows about |
|---|---|---|
| Train movement | `TrainController` | the route only |
| Turret aim and visuals | `MountedTurret` | its own child nodes |
| Fire logic and damage | `HitscanWeapon` | the turret (muzzle and barrel direction) and physics |
| Player control | `TurretInput` | camera, turret, weapon |
| Damage receivers | `Damageable` (+ subclasses) | nothing; broadcasts deaths to the `combat_listeners` group |
| Scoring | `ScoreTracker` | `combat_listeners` events |
| Presentation glue | `CombatFeedback` | weapon signals + `combat_listeners` → effects, audio, HUD, camera shake |
| Effects / audio / HUD | `EffectsManager`, `CombatAudio`, `CombatHud` | nothing gameplay-related |

Decisions:
- **Hitscan** for damage (instant raycast), with **visual-only tracers**
  that travel at about 520 m/s. That keeps it responsive and deterministic
  for tests.
- **Shots go where the barrel points.** The turret slews quickly
  (300°/s yaw), and the barrel aims at the exact 3D point under the
  crosshair, so shots land under the crosshair once the turret has caught up.
- **No self-hits:** player shots and the aim ray use the mask
  `WORLD | TARGETS`. The train sits on its own `TRAIN` layer, which enemy
  weapons can target later.
- **Damage interface is duck-typed:** a weapon walks up from the collider to
  the first node with `apply_damage(amount, point, normal, source)`. Enemy
  vehicles can extend `Damageable` and get scoring and effects for free.
- **Object reuse:** tracers, impacts, explosions, audio voices, and HUD
  popups are pooled. Destroyed targets are hidden and reset, never freed or
  respawned.
- **Camera independence:** the weapon never references the camera. Shake
  is triggered only by destructions (via `CombatFeedback`) and uses lens
  offset (`h_offset`/`v_offset`), so the framing and aim maths don't change.
- **Readability over strict realism for targets:** targets are slightly
  oversized and use hazard yellow and red so they read from the 50 m camera.
  Plates lean back 30° to face the camera.
- **Audio** is synthesized placeholder audio from `tools/gen_sfx.py`. It's
  original, so there are no licensing concerns. Replace the files and keep the names.

Physics layers: 1 `world` (terrain), 2 `train`, 3 `targets`, 4 `enemies`.

## Enemy architecture (as of Milestone 3)

| Concern | Node / script | Knows about |
|---|---|---|
| Enemy base | `EnemyBase` (extends `Damageable`) | train, route, terrain, hull (handed over on spawn) |
| Ground raiders | `RaiderVehicle` | terrain height for driving |
| Drones | `DroneEnemy` (strafer or kamikaze) | nothing extra |
| Waves and pooling | `WaveDirector` | enemy scenes, hull (repairs between waves) |
| Train health | `TrainHull` | the train's cars (aim points); nothing else |
| Presentation | `CombatFeedback`, `CombatHud`, `ThreatIndicators` | events only |

Decisions:
- **Enemies live in the track frame.** Each one stores `rel_offset` (metres
  along the route from the train front), `lateral`, and `height`, and is
  placed from those every physics frame. It keeps pace with the train,
  follows curves, and survives the route loop with no special cases. Wrecks
  switch to world space so they fall or coast to a stop behind you.
- **Same damage path as targets.** Enemies are `Damageable`s, so player
  hitscan, scoring, explosions, popups, hit markers, and barrel chain
  reactions all work on them unchanged.
- **Enemy fire is hitscan** against `WORLD | TRAIN` (terrain blocks it; it
  never hits other enemies or range targets). Each round is reported to the
  `enemy_fire_listeners` group, and the presentation layer draws red
  tracers and plays sounds from that.
- **The hull is not a Damageable.** The train isn't scored or targetable by
  the player, so `TrainHull` is a small separate health pool in the
  `train_hull` group.
- **Kamikazes telegraph.** Arm (hover, fast blink, beep, red HUD bracket)
  for about 1.3 s before diving, so there's always a fair window to shoot them.
- **Pooling:** each enemy kind is instanced the first time it's needed,
  then reused. Despawned enemies are hidden, collision-free, and count as
  destroyed, so area damage and aim helpers ignore them.
- **Route loop ≠ restart.** `TrainController` now emits `route_looped`
  (keep the run, bring the range targets back) separately from
  `run_restarted` (new run).
- **Run end condition** (open question from M2, now decided): survive as
  many waves as you can. Game over when the hull hits zero.

## Milestones

### Milestone 1: Moving Train Prototype ✅
- Project setup, git, `.gitignore`
- Locomotive + armored railcar (placeholder geometry), configurable speed, path following
- About 1 km downhill route with gentle curves (about 64 m drop)
- Terrain, cliffs, rocks, and industrial props (containers, tanks, signals, ore gantries)
- Angled-overhead follow camera, adjustable at runtime
- Debug controls and overlay (speed, progress, grade, camera, FPS)
- Headless smoke test

**Non-goals for M1:** enemies, turret combat and projectiles, explosions and
destruction, inventory and crafting, multiplayer, procedural worlds, upgrades,
elaborate menus, full asset production.

### Milestone 2: Turret combat ✅
- Mouse-aimed heavy MG turret on the railcar, with hold-LMB continuous hitscan fire (11 rounds per second)
- Muzzle flash, tracers, sparks, dust, splinters, explosions, recoil, hit markers, small destruction shake
- Synthesized audio on three adjustable buses, with overlap capped
- Destructible target course (plates, bunkers, explosive barrels with chain reactions, crates, generators)
- Score, destroyed count, hits, and accuracy HUD, plus kill popups. Everything resets on run restart.
- 38 headless checks. Measured performance is below.

**Non-goals for M2 (deferred):** enemy AI, moving enemies, waves, upgrades,
multiple weapons, reloading or ammo, large-scale destruction.

**Measured performance** (2026-11-05, Radeon 8060S, RADV, Forward+,
about 2069×1080 viewport, vsync off, 30 s of continuous auto-fire with 37
targets destroyed): **avg 617 FPS, 1% low 588 FPS, worst frame 4.5 ms**.
GPU cost is 1.6 ms per frame and CPU render cost 0.4 ms. The first second
after load is slower (shader warm-up) and isn't included.

### Milestone 3: Enemies and waves ✅
- Four enemy types: raider buggy, gun truck, strafe drone, kamikaze drone (placeholder primitive models, oversized and hostile-red for readability)
- Ground raiders chase from behind on the shoulder, hold attack slots beside the train, tilt with the terrain, and spin their wheels
- Drones fly in from ahead and dart between orbit points. Kamikazes arm (with a warning) and then dive.
- Enemy hitscan bursts with red tracers and their own gun sound. Train hull (400) with a HUD bar, red edge flash, and low-hull pulse.
- `WaveDirector`: 5 hand-made waves, then endless scaling. Breathers with a countdown, a horn and a chime, and +15% hull per cleared wave.
- Game over when the hull is wrecked (explosions, the train brakes, a stats panel). `R` restarts.
- Off-screen threat arrows and a kamikaze warning bracket
- 65 headless checks. Dev flags `--wave=N`, `--god`, `--no-enemies`.

**Non-goals for M3 (deferred):** pathfinding around props (raiders drive
through scenery on the shoulder), enemy-specific models and animation,
upgrades and economy, multiple player weapons, ammo and overheat, boss
enemies, difficulty settings, menus.

**Measured performance** (2026-11-06, Radeon 8060S, Forward+, about
2069×1080, 90 s of auto-play through waves 1–5 with 36 enemy kills): the
frame rate held at the 145 Hz display cap (1% low 144 FPS, worst frame 6.9 ms).
Render cost was GPU 2.1 ms and CPU 0.4 ms per frame.

### Heavy cannon ✅ (requested after M3)
Second player weapon on the same turret: right mouse button, 2 shells per second, 40 direct plus 45 splash in 5.5 m. It reuses `HitscanWeapon` (with a muzzle slot and explosive-round options) and the same feedback paths. 24 headless checks.

### Milestone 4+ (needs approval)

## Open questions for later milestones
- Whether the route will be one hand-authored line or a set of chained segments
- Mouse handling during combat: cursor confined to the window vs. visible free cursor

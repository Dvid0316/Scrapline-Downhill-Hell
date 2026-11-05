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
- No third-party dependencies. Original primitive/procedural assets only.

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
- A `TurretMount` marker sits on the railcar's turret ring, ready for M2.

## Milestones

### Milestone 1: Moving Train Prototype ✅ (this build)
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

### Milestone 2: Turret combat (needs approval before starting)
Mouse-aimed turret on `TurretMount`, hold-LMB continuous fire. Scope to be agreed.

## Open questions for later milestones
- Run length and end condition (reach the bottom? survive N waves?)
- Whether the route will be one hand-authored line or a set of chained segments
- Mouse handling during combat: cursor confined to the window vs. visible free cursor

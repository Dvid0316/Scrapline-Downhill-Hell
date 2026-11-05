# Scrapline: Downhill Hell

Single-player arcade train-defense game (Godot 4 / GDScript).
You ride a mounted gun on an armored train screaming down a mountain line.

**Current state: Milestone 1, the moving train prototype.** The train rolls
downhill on its own along a curving railway. The camera follows from above and
behind. There's no combat yet.

## Requirements

- Godot **4.7** (standard build, not .NET). On CachyOS/Arch: `sudo pacman -S godot`
- No third-party addons or downloaded assets. All geometry is primitive or procedural.

## Launch

```bash
cd ~/Projects/Scrapline-Downhill-Hell

# Play the main scene directly
godot --path .

# Or open the editor, then press F5
godot --path . --editor
```

The first launch imports the project (a few seconds). It also builds the terrain
and props at startup, which takes about a second.

## Controls (Milestone 1 debug)

| Key | Action |
|---|---|
| `W` / `S` or `↑` / `↓` (also `+` / `-`) | Raise / lower train target speed (2 m/s steps, hold to repeat) |
| `Space` | Pause / resume the train (it brakes smoothly) |
| `R` | Restart the run from the top |
| `[` / `]` | Camera pitch down / up (clamped 45–60°) |
| `,` / `.` or mouse wheel | Camera distance out / in |
| `;` / `'` | Camera look-ahead less / more |
| `Home` | Reset camera framing |
| `F1` | Toggle debug overlay |
| `Esc` | Release the mouse cursor |

The overlay shows speed (m/s and km/h), route progress, grade, camera values, and FPS.

## Tuning without code

Everything adjustable is an exported property, so you can edit it in the
Inspector on these nodes in `scenes/main.tscn`:

- **Train** (`TrainController`): `target_speed`, `max_speed`, `acceleration`, `loop_route`
- **FollowCamera**: `pitch_degrees`, `distance`, `look_ahead`, `aim_height`,
  `yaw_offset_degrees`, `position_smoothing`, `yaw_smoothing`, limits
- **Track** (`RailRoute`): `control_points` for the route shape. Edit the
  positions; the curve handles are generated automatically.
- **Terrain**: mountain and valley size, noise, colours
- **Props/\***: one `PropScatter` per layer, with count, side, lateral range, scale, and seed

## Tests

```bash
# Import + parse everything (shows script errors)
godot --headless --path . --import

# Milestone 1 smoke test (exit code 0 = pass)
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone1.gd
```

## Dev helpers

```bash
# Start halfway down the route
godot --path . -- --start-at=0.5

# Take a screenshot after 3 s, then quit (saved under captures/, which is git-ignored)
godot --path . -- --capture=captures/shot.png --capture-delay=3
```

## Layout

```
scenes/
  main.tscn                 playable scene (world, lighting, all layers)
  train/                    train.tscn (controller) + locomotive, armored_railcar, bogie (visual only)
  camera/follow_camera.tscn
  track/track.tscn          RailRoute path + generated rails
  environment/props/        reusable rocks, cliffs, containers, tank, signal, ore gantry
  ui/debug_hud.tscn
scripts/
  core/      main.gd (debug controls), input_actions.gd
  train/     train_controller.gd (movement), train_car.gd (car metadata)
  camera/    follow_camera.gd
  track/     rail_route.gd, track_builder.gd
  environment/ terrain_builder.gd, prop_scatter.gd
  ui/        debug_hud.gd
materials/   StandardMaterial3D .tres files
tests/       headless smoke test
```

See `PROJECT_SPEC.md` for the design, and `CHANGELOG.md` for history.

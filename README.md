# Scrapline: Downhill Hell

Single-player arcade train-defense game (Godot 4 / GDScript).
You ride a mounted gun on an armored train screaming down a mountain line.

**Current state: Milestone 2, turret combat.** The train rolls downhill on its
own. You aim a heavy machine gun with the mouse and hold left-click to shred a
course of destructible targets (steel plates, bunkers, explosive barrels,
crates, generators) for points. No enemies yet.

## Requirements

- Godot **4.7** (standard build, not .NET). On CachyOS/Arch: `sudo pacman -S godot`
- No third-party addons or downloaded assets. All geometry is primitive or
  procedural, and all sounds are synthesized by `tools/gen_sfx.py`.

## Launch

```bash
cd ~/Projects/Scrapline-Downhill-Hell
godot --path .              # play
godot --path . --editor     # open the editor (F5 to play)
```

The world (terrain, track, props, and target course) is generated at startup,
which takes about a second.

## Controls

| Input | Action |
|---|---|
| **Mouse** | Aim the turret (a crosshair follows the cursor) |
| **Hold left mouse button** | Continuous fire. Release to stop. |
| `W` / `S` or `↑` / `↓` (also `+` / `-`) | Raise / lower train target speed |
| `Space` | Pause / resume the train |
| `R` | Restart the run. Targets come back and the score resets. |
| `[` / `]` | Camera pitch (clamped 45–60°) |
| `,` / `.` or mouse wheel | Camera distance |
| `;` / `'` | Camera look-ahead |
| `Home` | Reset the camera |
| `F1` | Toggle the debug overlay |
| `Esc` | Release the mouse cursor. Click the window to grab it again. |

While the window has focus, the cursor is hidden and kept inside the window,
and the HUD draws the crosshair. The **amber ring** is where the barrel is
actually pointing, and that's where bullets go. The turret is heavy, so the ring
swings after your cursor and locks on once it catches up.

**HUD:** the score panel (top right) shows score, targets destroyed, hits, and
accuracy. The crosshair flashes a white ✕ on a hit and an orange ✕ on a kill,
and a "+points NAME" popup floats over each destroyed target.

## Scoring

| Target | HP | Points | Notes |
|---|---|---|---|
| Steel plate | 80 | 100 | Some sit high up the mountainside |
| Bunker | 260 | 250 | Usually has barrels beside it |
| Explosive barrel | 20 | 50 | Blast radius 8 m, damages everything nearby, chain-reacts |
| Crate | 30 | 25 | Splinters (no fireball) |
| Generator | 90 | 120 | Down on the valley side |

The gun does 12 damage per round at 11 rounds per second, with a 320 m range
and 0.6° spread. Every second round is a tracer. There's no reloading.

## Tuning (Inspector, `scenes/main.tscn`)

- **Combat/Weapon** (`HitscanWeapon`): `fire_rate`, `damage`, `max_range`, `spread_degrees`, `tracer_every`
- **Train/ArmoredRailcar/TurretMount/HeavyMGTurret** (`MountedTurret`): yaw/pitch speed and acceleration, `settle_rate`, pitch limits, front-arc limit, recoil, flash
- **Combat/Audio** (`CombatAudio`): per-sound volume, polyphony, impact rate limit. Also adjustable in the editor's **Audio** panel with three buses: *Weapons*, *Impacts*, *Explosions*.
- **Combat/Effects** (`EffectsManager`): pool sizes, tracer speed and length, explosion size
- **Combat/Feedback**: camera shake per destruction (`shake_per_destruction`, 0 = off)
- **FollowCamera**: framing, smoothing, `shake_enabled`, `max_shake_offset`
- **TargetCourse**: cluster spacing, seed, and which scenes it uses
- Target scenes (`scenes/targets/*.tscn`): `max_health`, `points`, barrel `blast_radius` / `blast_damage`
- Plus everything from Milestone 1: train speed, route shape, terrain, and props

## Tests

```bash
tests/run_all.sh     # import/parse + Milestone 1 (20 checks) + Milestone 2 (39 checks)
```

Or run them individually:

```bash
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone1.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone2.gd
```

Headless runs can't simulate the mouse or play sound. The M2 tests drive the
turret and weapon through the same calls the input code uses, and check that
sounds were *requested*.

## Dev helpers

Pass these after `--`:

```bash
godot --path . -- --start-at=0.5                       # start halfway down
godot --path . -- --capture=captures/shot.png --capture-delay=3   # screenshot, then quit
godot --path . -- --demo-fire                          # auto-aim at nearby targets and fire (demo only)
godot --path . --resolution 1920x1080 -- --demo-fire --bench=30   # FPS + GPU/CPU frame cost report
python3 tools/gen_sfx.py                               # regenerate the placeholder sounds
```

## Layout

```
scenes/
  main.tscn             playable scene
  train/                train (controller), locomotive, armored_railcar, bogie
  weapons/              heavy_mg_turret.tscn (mounted on the railcar's TurretMount)
  targets/              armored_plate, armored_bunker, explosive_barrel, wooden_crate, power_generator
  camera/ track/ environment/props/ ui/ (debug_hud, combat_hud)
scripts/
  core/       main.gd, input_actions.gd, physics_layers.gd
  train/      train_controller.gd, train_car.gd
  weapons/    mounted_turret.gd (aim + visuals), hitscan_weapon.gd (fire logic), turret_input.gd (mouse)
  combat/     damageable.gd → destructible_target.gd → explosive_barrel.gd,
              target_course.gd, score_tracker.gd, combat_feedback.gd (glue)
  effects/    effects_manager.gd (pooled tracers, impacts, explosions)
  audio/      combat_audio.gd
  camera/ track/ environment/ ui/
audio/sfx/    synthesized WAVs (see tools/gen_sfx.py)
materials/    StandardMaterial3D .tres files
tests/        run_all.sh, test_milestone1.gd, test_milestone2.gd
tools/        gen_sfx.py
```

See `PROJECT_SPEC.md` for the design and architecture, and `CHANGELOG.md` for history.

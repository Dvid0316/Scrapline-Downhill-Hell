# Scrapline: Downhill Hell

Single-player arcade train-defense game (Godot 4 / GDScript).
You ride a mounted gun on an armored train screaming down a mountain line.

**Current state: Milestone 3, enemies and waves.** The train rolls downhill on
its own. You aim a heavy machine gun with the mouse and hold left-click. Raider
buggies, gun trucks, strafing drones and kamikaze drones come at you in waves
and chip away at the train's hull. Survive as many waves as you can. The range
targets from Milestone 2 (plates, bunkers, barrels, crates, generators) are
still there for bonus points.

## Requirements

- Godot **4.7** (standard build, not .NET). On CachyOS/Arch: `sudo pacman -S godot`
- No third-party addons. The only downloaded assets are a few CC0 Poly Haven
  textures (see `CREDITS.md`), which are recoloured by the stylized shaders. All
  geometry is primitive or procedural, and all sounds are synthesized by
  `tools/gen_sfx.py`.

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
| **Hold left mouse button** | Machine gun: continuous fire. Release to stop. |
| **Right mouse button** (or `E`) | Heavy cannon: about 2 explosive shells a second. Hold it to keep firing. Works at the same time as the MG. |
| `W` / `S` or `↑` / `↓` (also `+` / `-`) | Raise / lower the speed the driver holds. On the rollercoaster drops gravity takes over and you go much faster (250+ km/h at full throttle). |
| `Space` | Pause / resume the train |
| `R` | Restart the run: full hull, wave 1, score resets. (Also how you continue after the train is wrecked.) |
| `[` / `]` | Camera pitch (clamped 45–60°) |
| `,` / `.` or mouse wheel | Camera distance |
| `;` / `'` | Camera look-ahead |
| `Home` | Reset the camera |
| `1` / `2` / `3` (or click) | Pick an upgrade card after a wave |
| `C` | Change the crosshair colour (pink, green, cyan, yellow, white). Remembered next time. |
| `F1` | Toggle the debug overlay |
| `Esc` | Release the mouse cursor. Click the window to grab it again. |

While the window has focus, the cursor is hidden and kept inside the window,
and the HUD draws the crosshair (black-outlined so it shows on any background;
`C` changes its colour). The **light ring** is where the barrel is
actually pointing, and that's where bullets go. The turret is heavy, so the ring
swings after your cursor and locks on once it catches up.

**HUD:**
- **Top centre:** current wave, plus how many hostiles are left (or a countdown to the next wave).
- **Top right:** score, enemies destroyed, range targets destroyed, hits, and accuracy.
- **Bottom centre:** hull bar (green → amber → red). The screen edges flash red when you're hit and pulse when the hull is under 25%.
- **Red arrows** on the screen edge point at enemies you can't see. An armed or diving **kamikaze** gets a big pulsing arrow, or a red bracket when it's on screen. Shoot that one first.
- The crosshair flashes a white ✕ on a hit and an orange ✕ on a kill, and a "+points NAME" popup floats over each kill.

## Enemies and waves

| Enemy | HP | Points | What it does |
|---|---|---|---|
| Raider buggy (red) | 60 | 150 | Chases up from behind on the shoulder, holds beside the train, fires 5-round bursts |
| Gun truck | 240 | 400 | Slow, armoured, twin gun, 10-round bursts. Shows up from wave 4. |
| Strafe drone (dark red) | 24 | 100 | Flies in from ahead and darts around the train firing short bursts |
| Kamikaze drone (yellow, red warhead) | 20 | 125 | Hovers and **beeps** for about a second (arming), then dives at the gun car for 45 hull. Shot down, it explodes and takes nearby drones with it. |

- The hull has 400 points. Enemy rounds do 1.5–3 each, and a kamikaze that gets through does 45.
- **Wave flow:** a few seconds' breather (with a countdown), then a horn and the wave spawns over a few seconds. Kill everything and you get a chime plus **+15% hull**, then the next breather.
- Waves 1–5 introduce one thing at a time (drones → raiders → kamikazes → gun truck → everything). After wave 5 they keep growing (+25% enemies and +10% enemy health per wave), so every run ends eventually.
- At the bottom of the line the train loops back to the top **without** ending the run. The range targets come back, and enemies keep chasing.
- When the hull hits zero the train blows up and brakes, and the game-over panel shows your wave and score. Press `R` to go again.

## Upgrades

Every time you clear a wave, the countdown stops and **three upgrade cards**
come up. Click one (or press `1`, `2` or `3`). The next wave doesn't start
until you choose. Upgrades stack up to their max level and last for the
whole run. `R` starts over without them. The first offer of a run always
includes a new weapon.

| Card | Type | Max | What it does |
|---|---|---|---|
| **Tesla Coil** | New weapon | 3 | A coil on the engine roof zaps the nearest enemy (34 damage, 34 m reach) about once a second. Each level zaps faster and chains the lightning to one more enemy. |
| **Rocket Pod** | New weapon | 3 | A launcher on the gun car's rear deck fires homing rockets (60 splash damage) every few seconds: 2 per volley, then 3, then 4. |
| Ricochet Rounds | Machine gun | 2 | Bullets that hit an enemy bounce into the nearest other enemy for 60% damage (one bounce, then two) |
| Hot Barrel | Machine gun | 3 | +30% fire rate per level |
| AP Rounds | Machine gun | 3 | +35% damage per level |
| Turbo Servos | Machine gun | 2 | The turret swings 50% faster per level |
| Autoloader | Cannon | 3 | +40% fire rate per level |
| Big Bang Shells | Cannon | 3 | +30% blast radius and +25% blast damage per level |
| Scrap Armor | Armor | 4 | +100 max hull and +100 hull right away |
| Reactive Plating | Armor | 3 | 15% less damage taken per level |
| Emergency Patch | Armor | no limit | Hull back to full. It shows up more often when you're badly hurt. |

## Scoring

| Target | HP | Points | Notes |
|---|---|---|---|
| Steel plate | 80 | 100 | Some sit high up the mountainside |
| Bunker | 260 | 250 | Usually has barrels beside it |
| Explosive barrel | 20 | 50 | Blast radius 8 m, damages everything nearby, chain-reacts |
| Crate | 30 | 25 | Splinters (no fireball) |
| Generator | 90 | 120 | Down on the valley side |

The **machine gun** does 12 damage per round at 11 rounds per second, with a 320 m
range and 0.6° spread. Every second round is a tracer. There's no reloading.

The **heavy cannon** is mounted beside the MG on the same turret, so it aims
wherever the MG aims. Each shell does 40 damage on a direct hit, then bursts
for up to 45 more to everything within 5.5 m (less toward the edge). That's
one shell per drone, often two drones per shell, about 6 shells for a gun
truck, and great for chain-reacting barrel yards. It fires 2 shells a second
with a 360 m range. An orange ring around the crosshair fills as it reloads,
and four ticks show when it's loaded. Shells never hurt your own train.

## Tuning (Inspector, `scenes/main.tscn`)

- **Combat/Weapon** (`HitscanWeapon`, the MG): `fire_rate`, `damage`, `max_range`, `spread_degrees`, `tracer_every`
- **Combat/Cannon** (`HitscanWeapon` with `muzzle_slot = cannon`): the same knobs plus `splash_radius` and `splash_damage`. Recoil and flash are on the turret (`cannon_recoil_*`, `cannon_flash_*`).
- **Train/ArmoredRailcar/TurretMount/HeavyMGTurret** (`MountedTurret`): yaw/pitch speed and acceleration, `settle_rate`, pitch limits, front-arc limit, recoil, flash
- **Combat/Audio** (`CombatAudio`): per-sound volume, polyphony, impact rate limit. Also adjustable in the editor's **Audio** panel with three buses: *Weapons*, *Impacts*, *Explosions*.
- **Combat/Effects** (`EffectsManager`): pool sizes, tracer speed and length, explosion size
- **Combat/Feedback**: camera shake per destruction (`shake_per_destruction`, 0 = off)
- **FollowCamera**: framing, smoothing, `shake_enabled`, `max_shake_offset`
- **TargetCourse**: cluster spacing, seed, and which scenes it uses
- Target scenes (`scenes/targets/*.tscn`): `max_health`, `points`, barrel `blast_radius` / `blast_damage`
- **Combat/WaveDirector** (`WaveDirector`): breather lengths, `max_alive`, `repair_per_wave`, seed. Wave contents are the `WAVES` table at the top of `scripts/enemies/wave_director.gd`.
- **Combat/TrainHull** (`TrainHull`): `max_hull`, `invulnerable`
- Enemy scenes (`scenes/enemies/*.tscn`): HP and points, gun (`fire_rate`, `burst_rounds`, `round_damage`, `spread_degrees`, `fire_range`), driving or flight settings, and kamikaze `impact_damage` / `arm_time` / `dive_speed`
- Plus everything from Milestone 1: train speed, route shape, terrain, and props

## Tests

```bash
tests/run_all.sh     # import/parse + Milestone 1-3, cannon, coaster and upgrade suites
```

Or run them individually:

```bash
godot --headless --path . --import
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone1.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone2.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_milestone3.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_cannon.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_coaster.gd
godot --headless --path . --fixed-fps 60 -s res://tests/test_upgrades.gd
```

Headless runs can't simulate the mouse or play sound. The M2 tests drive the
turret and weapon through the same calls the input code uses, and check that
sounds were *requested*.

## Dev helpers

Pass these after `--`:

```bash
godot --path . -- --start-at=0.5                       # start halfway down
godot --path . -- --capture=captures/shot.png --capture-delay=3   # screenshot, then quit
godot --path . -- --demo-fire                          # auto-aim (enemies first) and fire (demo only)
godot --path . -- --wave=4                             # start at wave 4
godot --path . -- --god                                # hull takes no damage
godot --path . -- --upgrades=tesla:2,rockets           # start with upgrades (id[:levels]; ids in the Upgrades table, e.g. mg_rate, cannon_blast)
godot --path . -s res://tools/aim_probe.gd             # hit grid: can the gun reach raiders all round the car?
godot --path . -s res://tools/upgrade_shot.gd          # screenshots of the upgrade cards and new weapons
godot --path . -- --no-enemies                         # Milestone 2 free-fire range, no waves
godot --path . --resolution 1920x1080 -- --demo-fire --bench=30   # FPS + GPU/CPU frame cost report
python3 tools/gen_sfx.py                               # regenerate the placeholder sounds
```

## Layout

```
scenes/
  main.tscn             playable scene
  train/                train (controller), locomotive, armored_railcar, bogie
  weapons/              heavy_mg_turret.tscn (MG + cannon, mounted on the railcar's TurretMount)
  targets/              armored_plate, armored_bunker, explosive_barrel, wooden_crate, power_generator
  enemies/              raider_buggy, gun_truck, strafe_drone, kamikaze_drone
  camera/ track/ environment/props/ ui/ (debug_hud, combat_hud)
scripts/
  core/       main.gd, input_actions.gd, physics_layers.gd
  train/      train_controller.gd, train_car.gd
  weapons/    mounted_turret.gd (aim + visuals), hitscan_weapon.gd (fire logic), turret_input.gd (mouse)
  combat/     damageable.gd → destructible_target.gd → explosive_barrel.gd,
              target_course.gd, score_tracker.gd, train_hull.gd, combat_feedback.gd (glue)
  enemies/    enemy_base.gd (extends Damageable) → raider_vehicle.gd, drone_enemy.gd;
              wave_director.gd (waves + pooling)
  effects/    effects_manager.gd (pooled tracers, impacts, explosions)
  audio/      combat_audio.gd
  camera/ track/ environment/ ui/ (combat_hud, crosshair, threat_indicators)
audio/sfx/    synthesized WAVs (see tools/gen_sfx.py)
materials/    StandardMaterial3D .tres files
tests/        run_all.sh, test_milestone1.gd, test_milestone2.gd, test_milestone3.gd, test_cannon.gd
tools/        gen_sfx.py
```

See `PROJECT_SPEC.md` for the design and architecture, and `CHANGELOG.md` for history.

## License

Code, scenes and the generated sound effects: [MIT](LICENSE).
Third-party textures are CC0 (public domain). Sources are in [CREDITS.md](CREDITS.md).

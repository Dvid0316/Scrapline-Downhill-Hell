# Changelog

All notable changes to this project. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

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

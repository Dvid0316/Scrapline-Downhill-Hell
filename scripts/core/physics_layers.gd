class_name PhysicsLayers
extends RefCounted
## Collision layer bit values (names are also set in Project Settings).

const WORLD := 1      ## Layer 1: terrain and static scenery.
const TRAIN := 2      ## Layer 2: the player's train. Never hit by player shots.
const TARGETS := 4    ## Layer 3: anything that can take damage.

## What player bullets and the aim ray can hit.
const PLAYER_SHOT_MASK := WORLD | TARGETS

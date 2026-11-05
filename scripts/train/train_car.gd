class_name TrainCar
extends Node3D
## Metadata for one rail vehicle's geometry. The car scene is visual only;
## [TrainController] reads these numbers to place it on the track.
##
## Model convention: front of the car faces -Z, origin is centred
## lengthwise and sits at rail-top height (wheel bottoms at y = 0).

## Coupler-to-coupler length in metres.
@export var car_length: float = 14.0
## Distance between the two bogie pivots in metres.
@export var bogie_spacing: float = 9.0

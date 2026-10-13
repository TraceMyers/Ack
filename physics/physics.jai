INV_PHYSICS_DELTA_TIME :: 1.0 / PHYSICS_DELTA_TIME;

Collision_Channels :: #type,isa user_types.collision_channels;
Raycast_Channels   :: #type,isa user_types.raycast_channels;

#load "properties.jai";
#load "world.jai";
#load "collision.jai";
#load "collider.jai";
#load "raycast.jai";
#load "raycast_simple.jai";
#load "shape.jai";
#load "body.jai";
#load "update.jai";
#load "derive.jai";
#load "overlap.jai";
#load "convex.jai";
#load "config.jai";
#load "friction.jai";
#load "collision_broad_phase.jai";
#load "collision_narrow_phase.jai";

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

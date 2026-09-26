// todo: debug proc to validate that templates aren't being altered
Physical_World :: struct {
    body_templates: Table(string, Physics_Body_Template);
    unique_properties: Pool(Physics_Properties);
    unique_colliders: Pool(Physics_Collider);
    body_data: Physics_Body_SOA;

    step_state: Physics_Step_State;
    collision_iteration_count := 5;

    start_time: float64;
    update_timestamp: float64;
    time_scale: float32;
    step_count: int;

    delta_time: float32;

    #if PHYSICS_VALIDATION_LEVEL > 0 {
        debug_template_properties: [..]Physics_Properties;
    }

    gravity := 9.8;

    allocator: Allocator;

    contact_grid: Table(u32, Contact_Cell, (key: u32) -> u32 { return key; });
    contact_grid_cell_allocator: Super_Allocator;

    color_groups: [..]Color_Group;

    // grid settings for size, origin, broad phase resolution (scale)
    grid_origin := Vector2.{-512.0, -512.0};
    grid_width : s32 = 1024;
    grid_scale := 1.0;

    grid_in_use: bool;
}

// optional params can be left 0 if you want them to stay the same
set_physics_grid_origin:: (origin: Vector2) {
    using context;
    physics_check(.LOW, !physical_world.grid_in_use);
    physical_world.grid_origin = origin;
}

// optional params can be left 0 if you want them to stay the same
set_physics_grid_center :: (center: Vector2) {
    using context;
    physics_check(.LOW, !physical_world.grid_in_use);
    half_world_width := (physical_world.grid_width / physical_world.grid_scale) * 0.5;
    physical_world.grid_origin = center - splat(half_world_width, 2);
}

set_physics_grid_scale :: (scale: float, recenter := true) {
    using context;
    physics_check(.LOW, !physical_world.grid_in_use);
    physics_check(.LOW, scale > 0);
    physical_world.grid_scale = scale;
}

set_physics_grid_width :: (width: s32) {
    using context;
    physics_check(.LOW, !physical_world.grid_in_use);
    physics_check(.LOW, width > 0);
    physical_world.grid_width = width;
}

create_physical_world :: (bodies_max := 32768, body_templates_max := 128, unique_properties_max := 4096, unique_colliders_max := 32768) -> Physical_World {
    out_world: Physical_World;

    physics_check(.LOW, bodies_max < U16_MAX); // using u16's as body indexes internally

    // ceil(max * 101/70) is to avoid the table reallocating.
    init(*out_world.body_templates, xx ceil(body_templates_max * (101.0 / 70.0)));
    pool_init(*out_world.unique_properties, unique_properties_max, true);
    pool_init(*out_world.unique_colliders, unique_colliders_max, true);

    if bodies_max > 0 {
        soa_reserve(*out_world.body_data, bodies_max);
    }
    soa_set_allocator(*out_world.body_data, no_allocator);

    // note: contact grid allocation is not locked, in case a bug comes of it
    init(*out_world.contact_grid, 65536);
    initialize_super_allocator(*out_world.contact_grid_cell_allocator, add_chunk_lists=16);

    out_world.allocator = context.allocator;
    return out_world;
}

destroy_physical_world :: (in_world: *Physical_World) {
    // does not destroy shared properties. that allocation (probably static) is managed by the user.
    save_allocator := context.allocator;
    context.allocator = in_world.allocator;
    defer context.allocator = save_allocator;

    in_world.body_templates.allocator = in_world.allocator;
    table_reset(*in_world.body_templates);
    deinit(*in_world.body_templates);

    pool_set_allocator(*in_world.unique_properties, in_world.allocator);
    pool_reset(*in_world.unique_properties);

    soa_set_allocator(*in_world.body_data, in_world.allocator);
    soa_reset(*in_world.body_data);
    
    in_world.* = {};
}

set_physical_world :: (in_world: *Physical_World) {
    context.physical_world = in_world;
}

Physics_Step_State :: enum {
    RUN_PHYSICS;
    STEP_ONCE;
    PAUSED;
    PAUSE_ON_COLLISION;
}

Physics_Body_Iteration :: struct {
    body: *Physics_Body;
    entity_id: user_types.entity_id_type;
}

Physics_Body_SOA :: SOA(struct{
    flags:              Physics_Body_Flags;
    collision_channels: user_types.collision_channels;
    entity_id:          user_types.entity_id_type;
    axes:               [3]u64;
    using body:         Physics_Body_Internal;
});

for_expansion :: (physics_soa: *Physics_Body_SOA, body: Code, flags: For_Flags) #expand {
    for i : 0..physics_soa.body.count - 1 {
        `it := Physics_Body_Iteration.{xx *physics_soa.body[i], physics_soa.entity_id[i]};
        `it_index := i;

        #insert body;
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

// external type made to avoid changing shared properties on accident.
Physics_Body :: Physics_Body_Base(void);
// cast to this type for easy access to physics properties.
Physics_Body_Internal :: Physics_Body_Base(Physics_Properties);

Physics_Body_Base :: struct($properties_type: Type) {
    using transform: Physics_Body_Transform;

    axes: [3]u64;
    properties: *properties_type;

    collider: Physics_Collider;
    contact_grid_min_x: s16;
    contact_grid_min_y: s16;
    contact_grid_max_x: s16;
    contact_grid_max_y: s16;
}

Physics_Body_Transform :: struct {
    linear_velocity: Vector3;
    angular_velocity: Vector3;
    prev_position: Vector3;
    next_position: Vector3;
    prev_orientation: Quaternion;
    next_orientation: Quaternion;
}

// a template which will be used to spawn bodies. templates are used in order
// to encourage reusing physics properties. that is, if you create a body
// from a template, its properties pointer is pointing to the properties instance
// owned by the template. so, for all bodies with identical properties, you
// get more cache-efficient reads for free during physics. note that
// if properties are to be changed and you don't want to alter the template,
// you need to call the 'change_property' procedure.
// the body.properties pointer should be kept null, as it isn't used for anything.
Physics_Body_Template :: struct {
    flags:              Physics_Body_Flags;
    collision_channels: user_types.collision_channels;
    properties:         Physics_Properties;
    collider:           Physics_Collider;
}

Physics_Body_Flags :: enum_flags u32 {
    AWAKE;
    LOCK_TRANSLATION;
    LOCK_YAW;
    LOCK_PITCH;
    LOCK_ROLL;
    UPRIGHT;
    SKIP_UPDATE;
    APPLY_GRAVITY;
    PLACED_INTO_CONTACT_GRID;
}

add_physics :: (entity: *Entity, template_name: string) -> *Physics_Body {
    template := table_find_pointer(*engine.physical_world.body_templates, template_name);
    engine_check(template != null);
    return create_physics_body(entity, template);
}

add_physics :: (entity: *Entity, template: *Physics_Body_Template) -> *Physics_Body {
    using engine.physical_world;

    flags := add_component(entity, Physics_Body_Flags);
    body  := add_component(entity, Physics_Body);

    // physics components must be aligned
    flags_inst := get_component_instance(entity, Physics_Body_Flags);
    body_inst  := get_component_instance(entity, Physics_Body);
    engine_check(flags_inst.ref.id.index == body_inst.ref.id.index);

    flags.* = template.flags | .AWAKE;
    body.properties = *template.properties;
    body.collider = template.collider;
    body.collider.collision_channels = template.collision_channels;

    // todo: only if the template calls for it
    place_into_contact_grid(body);

    return xx body;
}

remove_physics :: (entity: *Entity) {
    using engine.physical_world;

    body := get_component(entity, Physics_Body);

    props_are_unique, unique_index := is_unique(body.properties);
    if props_are_unique {
        pool_return(*unique_properties, unique_index);
    }

    remove_component(entity, Physics_Body_Flags);
    remove_component(entity, Physics_Body);
}

create_physics_body_template :: (name: string, template: Physics_Body_Template) {
    using engine.physical_world;

    template_copy := template;
    physics_check(template_copy.properties.mass > 0);
    template_copy.properties.inv_mass = 1.0 / template_copy.properties.mass;

    set_collider_data_for_fast_aabb_calculation(*template_copy.collider);

    physics_check(!table_contains(*body_templates, name), "table failed to add template % either because of a hash collision or because a template has already been added under that name", name);

    table_add(*body_templates, name, template_copy);

    #if do_physics_validation(.HIGH)
        array_add(*debug_template_properties, template_copy.properties);
    }
}

get_physics_body_template :: (name: string) -> *Physics_Body_Template {
    return table_find_pointer(*engine.physical_world.body_templates, name);
}

accelerate :: inline (body: *Physics_Body_Base, accel: Vector3) {
    if engine.physical_world.step_state != .PAUSED {
        body.linear_velocity += accel * PHYSICS_DELTA_TIME;
    }
}

push :: inline (_body: *Physics_Body_Base, force: Vector3) {
    // todo: inv mass and probably that matrix thing I can't remember
    body := cast(*Physics_Body_Internal) _body;
    if engine.physical_world.step_state != .PAUSED {
        accel := force * body.properties.inv_mass;
        body.linear_velocity += accel * PHYSICS_DELTA_TIME;
    }
}

get_flags :: inline (body: *Physics_Body_Base) -> Physics_Body_Flags {
    using engine.physical_world;
    return body_data.get_flags_component(*body_data, body.index).*;
}

set_flags :: inline (body: *Physics_Body_Base, flags: Physics_Body_Flags) {
    using engine.physical_world;
    body_data.get_flags_component(*body_data, body.index).* = flags;
}

add_flags :: inline (body: *Physics_Body_Base, flags: Physics_Body_Flags) {
    using engine.physical_world;
    body_data.get_flags_component(*body_data, body.index).* |= flags;
}

has_any_flags :: inline (body: *Physics_Body_Base, flags: Physics_Body_Flags) -> bool {
    using engine.physical_world;
    return (body_data.get_flags_component(*body_data, body.index).* & flags) != 0;
}

has_all_flags :: inline (body: *Physics_Body_Base, flags: Physics_Body_Flags) -> bool {
    using engine.physical_world;
    return (body_data.get_flags_component(*body_data, body.index).* & flags) == flags;
}

has_flags :: has_all_flags;

remove_flags :: inline (body: *Physics_Body_Base, flags: Physics_Body_Flags) {
    using engine.physical_world;
    body_data.get_flags_component(*body_data, body.index).* &= ~flags;
}

can_translate :: inline (body: *Physics_Body_Base) -> bool {
    using engine.physical_world;
    return (body_data.get_flags_component(*body_data, body.index).* & .LOCK_TRANSLATION) == 0;
}

x_axis :: inline (body: *Physics_Body_Base) -> Vector3 {
    return get_right_direction(body.next_orientation);
}

y_axis :: inline (body: *Physics_Body_Base) -> Vector3 {
    return get_fore_direction(body.next_orientation);
}

z_axis :: inline (body: *Physics_Body_Base) -> Vector3 {
    return get_up_direction(body.next_orientation);
}

calc_axes :: inline (body: *Physics_Body_Base) -> Vector3, Vector3, Vector3 {
    x := x_axis(body);
    y := y_axis(body);
    z := z_axis(body);
    return x, y, z;
}

// teleport a body to a location
set_position :: (_body: *Physics_Body_Base, position: Vector3) {
    using body := cast(*Physics_Body_Internal) _body;
    next_position = position;
    prev_position = position;
    on_move_or_accelerate(body);
}

// teleport a body to an orientation
set_orientation :: (_body: *Physics_Body_Base, orientation: Quaternion) {
    using body := cast(*Physics_Body_Internal) _body;
    next_orientation = orientation;
    prev_orientation = orientation;
    on_move_or_accelerate(body);
}

get_position :: (_body: *Physics_Body_Base) -> Vector3 {
    body := cast(*Physics_Body_Internal) _body;
    alpha := get_physical_entity_transform_alpha();
    return lerp(body.prev_position, body.next_position, alpha);
}

calculate_aabb :: inline (_body: *Physics_Body_Base, $use_compressed_axes := false) -> AABB {
    body := cast(*Physics_Body_Internal) _body;
    using body.collider;

    aabb := AABB.{center = body.next_position};

    if shape == .SPHERE {
        aabb.extent = splat(shape_data.array[0], 3);
    } else {
        #if use_compressed_axes {
            using engine.physical_world;
            axes := body_data.get_axes_component(*body_data, body.index);
            x := linear_decompress_vector3(axes.*[0], -1, 1);
            y := linear_decompress_vector3(axes.*[1], -1, 1);
            z := linear_decompress_vector3(axes.*[2], -1, 1);
            aabb.extent = 
                  abs(z * shape_data.array[0]) 
                + abs(x * shape_data.array[1]) 
                + abs(y * shape_data.array[2]);
        } else {
            x, y, z := calc_axes(body);
            aabb.extent = 
                  abs(z * shape_data.array[0]) 
                + abs(x * shape_data.array[1]) 
                + abs(y * shape_data.array[2]);
        }
    }

    return aabb;
}

on_move_or_accelerate :: (_body: *Physics_Body_Base) {
    body := cast(*Physics_Body_Internal) _body;
    diff_place_into_contact_grid(body);
}

#scope_module

is_data_from_template :: (data: *u8) -> bool {
    using engine.physical_world;
    shared_byte_diff := data - cast(*u8) body_templates.entries.data;
    shared_byte_end  := size_of(type_of(body_templates.entries[0])) * body_templates.entries.count;
    return shared_byte_diff >= 0 && shared_byte_diff < shared_byte_end;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

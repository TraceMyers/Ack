// todo: detecting common bugs like double-put or forgetting to remove
// todo: optimization, instead of doing a full remove, re-place, do a diff placement.

Contact_Cell   :: Hybrid_Storage_Array(u16);
Contact_Island :: Hybrid_Storage_Array([2]u16);
Color_Group    :: Contact_Island;

run_contacts_broad_phase :: () {
    using context.physical_world;

    for *color_groups {
        array_reset(it);
    }
    array_reset_keeping_memory(*color_groups);

    seen_body       := make_bit_array(body_data.body.count,, temp);

    // todo: rotation being ignored because it's annoying. don't do that.
    SHOULD_VISIT_QUESTION : Physics_Body_Flags : .PLACED_INTO_CONTACT_GRID | .AWAKE | .LOCK_TRANSLATION; 
    SHOULD_VISIT_ANSWER   : Physics_Body_Flags : .PLACED_INTO_CONTACT_GRID | .AWAKE;

    start_index: int;
    body_color_group_flags := make_static_array(u64, body_data.body.count,, temp);

    array_resize(*color_groups, 8);

    for *body, bi : body_data.body {
        flags := body_data.flags[bi];

        if (flags & SHOULD_VISIT_QUESTION) != SHOULD_VISIT_ANSWER {
            continue;
        }

        // seen self = easy way to never pair with self
        seen_body[bi] = true;
        body_aabb := calculate_aabb(body, true);

        for_cells_in_overlap(body, false, true, #code {
            for obi : cell {
                // only visit bodies with indexes higher than this one...
                if obi < bi {
                    other_flags := body_data.flags[obi];
                    // ... but only as long as the other body already iterated
                    if (other_flags & SHOULD_VISIT_QUESTION) == SHOULD_VISIT_ANSWER {
                        continue;
                    }
                }

                if seen_body[obi] {
                    continue;
                }
                seen_body[obi] = true;

                other_body_aabb := calculate_aabb(*body_data.body[obi], true);

                if is_overlap_aabb_aabb(body_aabb, other_body_aabb) {
                    place_pair_in_group(body_color_group_flags, *start_index, .[xx bi, xx obi]);
                }
            }
        });

        clear_all_bits(*seen_body);
    }
}

place_pair_in_group :: inline (body_color_group_flags: []u64, start_index: *int, contact: [2]u16) {
    using context.physical_world;

    flags_a := *body_color_group_flags[contact[0]];
    flags_b := *body_color_group_flags[contact[1]];

    group_index: int;

    cannot_be_in_group: u64;
    cannot_be_in_group |= flags_a.*;
    cannot_be_in_group |= flags_b.*;
    can_be_in_group := ~cannot_be_in_group;

    can_be_in_group >>= start_index.*;
    group_index = bit_scan_forward(can_be_in_group) - 1;

    group_index_offset := start_index.*;
    start_index.* = increment_wrap(start_index.*, 0, color_groups.count - 1);

    if group_index < 0 {
        // color group i=64 is for linearly-solved overflow
        if color_groups.count < 65 {
            array_resize(*color_groups, 65);
        } else physics_check(.LOW, color_groups.count == 65);
        group_index = 64;
    } else {
        group_index += group_index_offset;
        if group_index >= color_groups.count {
            array_resize(*color_groups, group_index + 1);
        }
    }

    group := *color_groups[group_index];
    array_add(group, contact);

    mask := (cast(u64) 1) << group_index;

    flags_a.* |= mask;
    flags_b.* |= mask;
}


calculate_grid_overlap :: (_body: *Physics_Body_Base) -> Vector2i, Vector2i {
    body       := cast(*Physics_Body_Internal) _body;
    aabb       := calculate_aabb(body, true);
    aabb_swept := sweep_aabb(aabb, body.linear_velocity * context.physical_world.delta_time);
    aabb_swept.extent *= 1.25;

    min := world_to_grid(aabb_swept.center - aabb_swept.extent);
    max := world_to_grid(aabb_swept.center + aabb_swept.extent);

    physics_check(.LOW, min.x <= max.x);
    physics_check(.LOW, min.y <= max.y);

    return min, max;
}

world_to_grid :: inline (v: Vector3) -> Vector2i {
    transformed := v.xy;
    transformed -= context.physical_world.grid_origin;
    transformed *= context.physical_world.grid_scale;
    transformed = clamp(transformed, {0, 0}, {xx (context.physical_world.grid_width - 1), xx (context.physical_world.grid_width - 1)});
    return to_vector2i(transformed);
}

Grid_To_World_Placement :: enum { UPPER_LEFT; CENTER; LOWER_RIGHT; }

grid_to_world :: inline (v: Vector2i, $placement := Grid_To_World_Placement.UPPER_LEFT) -> Vector3 {
    transformed := Vector2.{xx v.x, xx v.y};
    inv_grid_scale := splat(1 / context.physical_world.grid_scale, 2);
    transformed *= inv_grid_scale;

    #if placement == {
    case .UPPER_LEFT;
        transformed += context.physical_world.grid_origin;
    case .CENTER;
        transformed += context.physical_world.grid_origin + inv_grid_scale * 0.5;
    case .LOWER_RIGHT;
        transformed += context.physical_world.grid_origin + inv_grid_scale;
    }

    return Vector3.{xy=transformed};
}

for_cells_in_overlap :: (_body: *Physics_Body_Base, $allocate_cell_if_empty: bool, $use_coords_on_body: bool, $code: Code) -> bool #expand {
    body := cast(*Physics_Body_Internal) _body;
    if !has_extent(body.collider.shape) {
        return false;
    }

    #if use_coords_on_body {
        `min := Vector2i.{body.contact_grid_min_x, body.contact_grid_min_y};
        `max := Vector2i.{body.contact_grid_max_x, body.contact_grid_max_y};
    } else {
        `min, `max := calculate_grid_overlap(_body);
    }

    for `y : min.y..max.y {
        for `x : min.x..max.x {
            `cell := get_contact_cell({_s16=.[xx x, xx y]}, allocate_cell_if_empty);
            #insert code;
        }
    }
    return true;
}

place_into_contact_grid :: (_body: *Physics_Body_Base) {
    using context.physical_world;

    // modification of grid is only allowed until the first body is placed into it.
    // todo: make reset feature?
    grid_in_use = true;

    physics_check(.LOW, !has_flags(_body, .PLACED_INTO_CONTACT_GRID));

    body_index: u16 = xx get_index(_body);

    if !for_cells_in_overlap(_body, true, false, #code array_add(cell, body_index)) {
        return;
    }

    _body.contact_grid_min_x = xx min.x;
    _body.contact_grid_min_y = xx min.y;
    _body.contact_grid_max_x = xx max.x;
    _body.contact_grid_max_y = xx max.y;

    add_flags(_body, .PLACED_INTO_CONTACT_GRID);
}

remove_from_contact_grid :: (_body: *Physics_Body_Base) {
    using context.physical_world;

    if !has_flags(_body, .PLACED_INTO_CONTACT_GRID) {
        return;
    }

    body_index: u16 = xx get_index(_body);

    for_cells_in_overlap(_body, false, true, #code array_unordered_remove_by_value(cell, body_index));

    // intentionally invalid (max < min)
    _body.contact_grid_min_x = 0;
    _body.contact_grid_min_y = 0;
    _body.contact_grid_max_x = -1;
    _body.contact_grid_max_y = -1;

    remove_flags(_body, .PLACED_INTO_CONTACT_GRID);
}

diff_place_into_contact_grid :: (_body: *Physics_Body_Base) {
    using context.physical_world;

    body := cast(*Physics_Body_Internal) _body;

    if !has_extent(body.collider.shape) {
        remove_from_contact_grid(body);
        return;
    }

    new_min, new_max := calculate_grid_overlap(_body);

    if new_min.x == body.contact_grid_min_x
    && new_min.y == body.contact_grid_min_y
    && new_max.x == body.contact_grid_max_x
    && new_max.y == body.contact_grid_max_y {
        return;
    }

    body_index: u16 = xx get_index(body);

    for y : new_min.y..new_max.y {
        for x : new_min.x..new_max.x {
            if is_point_in_box_2d(x, y, body.contact_grid_min_x, body.contact_grid_min_y, body.contact_grid_max_x, body.contact_grid_max_y) {
                continue;
            }
            cell := get_contact_cell({_s16=.[xx x, xx y]}, true);
            array_add(cell, body_index);
        }
    }

    for y : body.contact_grid_min_y..body.contact_grid_max_y {
        for x : body.contact_grid_min_x..body.contact_grid_max_x {
            if is_point_in_box_2d(x, y, new_min.x, new_min.y, new_max.x, new_max.y) {
                continue;
            }
            cell := get_contact_cell({_s16=.[xx x, xx y]}, true);
            array_unordered_remove_by_value(cell, body_index);
        }
    }

    body.contact_grid_min_x = xx new_min.x;
    body.contact_grid_min_y = xx new_min.y;
    body.contact_grid_max_x = xx new_max.x;
    body.contact_grid_max_y = xx new_max.y;

    add_flags(_body, .PLACED_INTO_CONTACT_GRID);
}

get_contact_cell :: inline (coords: Vector2i) -> *Contact_Cell {
    return get_contact_cell({_u16=.[xx coords.x, xx coords.y]});
}

get_contact_cell :: inline (key: num32, allocate_if_empty := false) -> *Contact_Cell {
    cell := table_find_pointer(*context.physical_world.contact_grid, key._u32);
    if cell == null && allocate_if_empty {
        table_set(*context.physical_world.contact_grid, key._u32, {external.allocator = context.physical_world.contact_grid_cell_allocator});
        cell = table_find_pointer(*context.physical_world.contact_grid, key._u32);
    }
    return cell;
}

physics_delta_time :: () -> float #expand {
    return PHYSICS_DELTA_TIME * engine.physical_world.time_scale;
}

// returns how many steps ran
update_physics :: () {
    using engine.physical_world;
    defer update_entity_transforms();

    last_step_delta = 0;

    if start_time == 0 {
        start_time = seconds_since_init();
    }

    update_timestamp        = seconds_since_init();
    total_simulation_time  := update_timestamp - start_time;
    total_simulation_steps := cast(int) (total_simulation_time * INV_PHYSICS_DELTA_TIME);
    run_steps_this_frame   := total_simulation_steps - step_count;

    if run_steps_this_frame <= 0 {
        return;
    }

    if step_state == .STEP_ONCE {
        step_state = .PAUSED;
    }

    // only updating time scale right before stepping, because this is exactly when it is used.
    time_scale = xx engine.clock.delta_time_scale;
    step_count = total_simulation_steps;

    if step_state == .PAUSED {
        return;
    }

    for 0..run_steps_this_frame-1 {
        run_physics_step(it);
    }

    last_step_delta = run_steps_this_frame;
}

// if consecutive_step_index is 0, some extra initialization is done, as well
// as (todo) warm starting
run_physics_step :: (consecutive_step_index: int) {
    using engine.physical_world;

    auto_release_temp();

    delta_time = physics_delta_time();
    run_physics_step_pre_contact(consecutive_step_index);
    run_contacts_broad_phase();
    run_contacts_narrow_phase();
    run_physics_step_post_contact();
}

run_physics_step_pre_contact :: (consecutive_step_index: int) {
    using engine.physical_world;
    // todo: warm starting

    for component_loop(Physics_Body, false) {

        body := cast(*Physics_Body_Internal) it.data;
        flags := body.flags;

        if (flags & .SKIP_UPDATE) != 0 {
            continue;
        }

        if consecutive_step_index == 0 {
            body.prev_position = body.next_position;
            body.prev_orientation = body.next_orientation;
        }

        if body.collider.shape != .SPHERE {
            x, y, z := calc_axes(body);
            axes := *body.axes;
            axes.*[0] = linear_compress_vector3(x, -1, 1);
            axes.*[1] = linear_compress_vector3(y, -1, 1);
            axes.*[2] = linear_compress_vector3(z, -1, 1);
        }

        moved_or_accelerated: bool;
        defer if moved_or_accelerated {
            on_move_or_accelerate(body);
        }

        if (flags & .APPLY_GRAVITY) != 0 {
            body.linear_velocity.z -= gravity * delta_time;
            moved_or_accelerated = true;
        }
        
        // if body.move_input != {} {
        //     input_accel := body.move_input * body.properties.move_input_acceleration;
        //     body.linear_velocity.xy += input_accel * delta_time;
        //     body.move_input = {};
        //     moved_or_accelerated = true;
        // }

        if body.properties.call_per_step != null {
            old_tform := body.transform;
            body.properties.call_per_step(xx body);
            if memcmp(*body.transform, *old_tform, size_of(Physics_Body_Transform)) != 0 {
                moved_or_accelerated = true;
            }
        }
    }
}

run_physics_step_post_contact :: () {

}

update_entity_transforms :: () {
    LOCK_TRANSLATE_AND_ROTATE : Physics_Body_Flags : .LOCK_TRANSLATION | .LOCK_YAW | .LOCK_PITCH |.LOCK_ROLL;

    physics_transform_alpha := get_physical_entity_transform_alpha();

    for component_loop(Physics_Body, false) {
        body := it.data;

        if (body.flags & .AWAKE) == 0 {
            continue;
        }

        if (body.flags & LOCK_TRANSLATE_AND_ROTATE) == LOCK_TRANSLATE_AND_ROTATE {
            continue;
        }

        t := get_component(it.entity, Transform);
        t.orientation = interp_rotate_with_alpha(body.prev_orientation, body.next_orientation, physics_transform_alpha);
        t.position = get_position(body) - body.collider.half_height * get_up_direction(t.orientation);
    }
}

get_physical_entity_transform_alpha :: () -> float32 {
    using engine.physical_world;
    total_simulation_time  := start_time - update_timestamp;
    simulated_time         := engine.physical_world.step_count * PHYSICS_DELTA_TIME;
    remainder              := total_simulation_time - simulated_time;
    return xx clamp(remainder * INV_PHYSICS_DELTA_TIME, 0, 1);
}

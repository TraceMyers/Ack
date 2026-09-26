// example physics update:
// my_physics_update :: () {
    // update_physics(game_config.time_scale);
    // physical_entity_transform_update(#code {
    //     e := get_entity(entity_id);
    //     e.orientation = interp_rotate_with_alpha(body.prev_orientation, body.next_orientation, physics_transform_alpha);
    //     // setting position at the entity's feet
    //     e.position = get_position(body) - get_collider(body).half_height * get_up_direction(e.orientation);
    // });
// }

physics_delta_time :: () -> float #expand {
    return PHYSICS_DELTA_TIME * context.physical_world.time_scale;
}

// returns how many steps ran
update_physics :: (in_time_scale: float) -> int {
    using context.physical_world;

    if start_time == 0 {
        start_time = seconds_since_init();
    }

    update_timestamp        = seconds_since_init();
    total_simulation_time  := update_timestamp - start_time;
    total_simulation_steps := cast(int) (total_simulation_time * INV_PHYSICS_DELTA_TIME);
    run_steps_this_frame   := total_simulation_steps - step_count;

    if run_steps_this_frame <= 0 {
        return 0;
    }

    if step_state == .STEP_ONCE {
        step_state = .PAUSED;
    }

    // only updating time scale right before stepping, because this is exactly when it is used.
    time_scale = in_time_scale;
    step_count = total_simulation_steps;

    if step_state == .PAUSED {
        return 0;
    }

    for 0..run_steps_this_frame-1 {
        run_physics_step(it);
    }

    return run_steps_this_frame;
}

// if consecutive_step_index is 0, some extra initialization is done, as well
// as (todo) warm starting
run_physics_step :: (consecutive_step_index: int) {
    using context.physical_world;

    auto_release_temp();

    delta_time = physics_delta_time();
    run_physics_step_pre_contact(consecutive_step_index);
    run_contacts_broad_phase();
    run_contacts_narrow_phase();
    run_physics_step_post_contact();
}

run_physics_step_pre_contact :: (consecutive_step_index: int) {
    using context.physical_world;
    // todo: warm starting

    for *body, bi : body_data.body {
        flags := body_data.flags[bi];

        if (flags & .SKIP_UPDATE) != 0 {
            continue;
        }

        if consecutive_step_index == 0 {
            body.prev_position = body.next_position;
            body.prev_orientation = body.next_orientation;
        }

        if body.collider.shape != .SPHERE {
            x, y, z := axes(body);
            body_data.axes[bi][0] = linear_compress_vector3(x, -1, 1);
            body_data.axes[bi][1] = linear_compress_vector3(y, -1, 1);
            body_data.axes[bi][2] = linear_compress_vector3(z, -1, 1);
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

physical_entity_transform_update :: (loop_body: Code) #expand {
    LOCK_TRANSLATE_AND_ROTATE : Physics_Body_Flags : .LOCK_TRANSLATION | .LOCK_YAW | .LOCK_PITCH |.LOCK_ROLL;

    `physics_transform_alpha := get_physical_entity_transform_alpha();

    for *b, bi : context.physical_world.body_data.body {
        `flags := get_flags(cast(*Physics_Body) b);
        // if (`flags & .AWAKE) == 0 {
        //     continue;
        // }
        if (`flags & LOCK_TRANSLATE_AND_ROTATE) == LOCK_TRANSLATE_AND_ROTATE {
            continue;
        }
        `body      := cast(*Physics_Body) b;
        `it_index  := bi;
        `entity_id := context.physical_world.body_data.entity_id[bi];

        #insert loop_body;
    }
}

get_physical_entity_transform_alpha :: () -> float32 {
    using context.physical_world;
    total_simulation_time  := start_time - update_timestamp;
    simulated_time         := context.physical_world.step_count * PHYSICS_DELTA_TIME;
    remainder              := total_simulation_time - simulated_time;
    return xx clamp(remainder * INV_PHYSICS_DELTA_TIME, 0, 1);
}

// todo: precalculate axes for collisions only. one long buffer.

Physics_Contact :: struct {
    // offset & normals are in world space. rotate them with the conjugate of the
    // body's orientation go get them in local space.
    a_contact_offset:  Vector3;
    b_contact_offset:  Vector3;
    a_surface_normal: Vector3;
    b_surface_normal: Vector3;
    contact_normal: Vector3;
    // time until the bodies make contact. if >= 0 and < delta_time, it is a contact.
    contact_time: float;
    // only if contact_time is 0
    overlap: float;
}

solve_contact :: (body_a: *Physics_Body_Internal, body_b: *Physics_Body_Internal) {
    contact: Physics_Contact;
    is_contact: bool;

    if body_a.collider.shape == {
    case .SPHERE;
        if body_b.collider.shape == {
        case .SPHERE;
            is_contact = solve_contact_sphere_sphere(body_a, body_b, *contact);
        case .PLANE;
            is_contact = solve_contact_sphere_plane(body_a, body_b, *contact);
        case .RECTANGLE;
            is_contact = solve_contact_sphere_rectangle(body_a, body_b, *contact);
        }
    case .PLANE;
        if body_b.collider.shape == {
        case .SPHERE;
            is_contact = solve_contact_sphere_plane(body_b, body_a, *contact);
            flip(*contact);
        }
    case .RECTANGLE;
        if body_b.collider.shape == {
        case .SPHERE;
            is_contact = solve_contact_sphere_rectangle(body_b, body_a, *contact);
            flip(*contact);
        }
    }

    // todo: just to remember for later that movement has a time budget,
    // because we move forward in time in sorted order from earliest to latest.
    // note this also means that we can't just do 1. resolve collisions 2. move
    // because collision resolution and movement are integrated.
    if is_contact {
        a_moves := (get_flags(body_a) & .LOCK_TRANSLATION) == 0;
        b_moves := (get_flags(body_b) & .LOCK_TRANSLATION) == 0;
        // for now, just basic position resolution and velocity killing
        if !b_moves {
            if a_moves {
                if contact.contact_time == 0 {
                    body_a.next_position -= contact.contact_normal * contact.overlap;
                } else {
                    body_a.next_position += body_a.linear_velocity * contact.contact_time;
                }
            }
        } else if !a_moves {
            if contact.contact_time == 0 {
                body_b.next_position += contact.contact_normal * contact.overlap;
            } else {
                body_b.next_position += body_b.linear_velocity * contact.contact_time;
            }
        } else {
            if contact.contact_time == 0 {
                body_a.next_position -= contact.contact_normal * (contact.overlap * 0.5);
                body_b.next_position += contact.contact_normal * (contact.overlap * 0.5);
            } else {
                body_a.next_position += body_a.linear_velocity * contact.contact_time;
                body_b.next_position += body_b.linear_velocity * contact.contact_time;
            }
        }

        // todo: you know, stuff
        body_a.linear_velocity -= contact.contact_normal * dot(body_a.linear_velocity, contact.contact_normal);
        body_b.linear_velocity -= -contact.contact_normal * dot(body_b.linear_velocity, -contact.contact_normal);

        moving_body: *Physics_Body_Internal;
        static_body: *Physics_Body_Internal;
        surface_normal: Vector3;

        if a_moves && !b_moves {
            moving_body = body_a;
            static_body = body_b;
            surface_normal = contact.b_surface_normal;
        } else if !a_moves && b_moves {
            moving_body = body_b;
            static_body = body_a;
            surface_normal = contact.a_surface_normal;
        }
        surface_tangent_x := cross(moving_body.linear_velocity, surface_normal);
        surface_speed     := length(surface_tangent_x);
        surface_tangent_x /= surface_speed;
        surface_tangent_y := cross(surface_normal, surface_tangent_x);
        
        time_in_contact := context.physical_world.delta_time - contact.contact_time;

        // NOTE: time in contact for friction is wrong
        // the normal force is implicit in whatever force was required to make
        // the relative velocity zero.

        if surface_speed > 0 {
            // might be other forces at work...
            normal_force := context.physical_world.gravity * dot(surface_normal, {z=1}) * moving_body.properties.mass;
            
            friction := calculate_stribeck_friction(FRICTION_DEFAULT, normal_force, surface_speed);
            friction_accel := friction * moving_body.properties.inv_mass;
            // friction_velocity_delta := friction_accel * world.delta_time;
            friction_velocity_delta := friction_accel * time_in_contact;

            new_surface_speed := max(surface_speed - friction_velocity_delta, 0);
            moving_body.linear_velocity -= surface_tangent_y * dot(moving_body.linear_velocity, surface_tangent_y);
            if new_surface_speed > 0 {
                moving_body.linear_velocity += surface_tangent_y * new_surface_speed;
            }

            // todo: at end of step
            if abs(moving_body.linear_velocity.x) < MIN_PHYSICS_BODY_SPEED_ALONG_AXIS {
                moving_body.linear_velocity.x = 0;
            }
            if abs(moving_body.linear_velocity.y) < MIN_PHYSICS_BODY_SPEED_ALONG_AXIS {
                moving_body.linear_velocity.y = 0;
            }
            if abs(moving_body.linear_velocity.z) < MIN_PHYSICS_BODY_SPEED_ALONG_AXIS {
                moving_body.linear_velocity.z = 0;
            }

            // physics_check(.LOW, moving_body.collider.shape == .SPHERE);
            // moving_body.angular_velocity += axis_of_acceleration / moving_body.collider.sphere.radius * world.delta_time;
            // moving_body.linear_velocity = {};
        }
    }
}

solve_contact_sphere_sphere :: (body_a: *Physics_Body_Internal, body_b: *Physics_Body_Internal, contact: *Physics_Contact) -> bool {
    physics_check(.HIGH, body_a.collider.shape == .SPHERE && body_b.collider.shape == .SPHERE);
    using context.physical_world;

    radius_sum        := body_a.collider.sphere.radius + body_b.collider.sphere.radius;

    cur_position_diff := body_b.next_position - body_a.next_position;
    cur_distance_sq   := length_squared(cur_position_diff);

    if cur_distance_sq <= VERY_SMALL_NUMBER {
        contact.a_contact_offset = {z= body_a.collider.sphere.radius};
        contact.b_contact_offset = {z=-body_b.collider.sphere.radius};
        contact.a_surface_normal = {z= 1};
        contact.b_surface_normal = {z=-1};
        contact.contact_normal   = {z= 1};
        contact.contact_time     = 0;
        contact.overlap          = radius_sum;
        return true;
    }

    cur_distance          := sqrt(cur_distance_sq);
    contact.contact_normal = cur_position_diff / cur_distance;

    if cur_distance > radius_sum {
        contact.contact_time = calculate_contact_time(contact.contact_normal, body_a.next_position, body_b.next_position, body_a.linear_velocity, body_b.linear_velocity, cur_distance, radius_sum);
        contact.overlap      = 0;
    } else {
        contact.contact_time = 0;
        contact.overlap      = radius_sum - cur_distance;
    }

    contact.a_contact_offset =  contact.contact_normal * body_a.collider.sphere.radius;
    contact.b_contact_offset = -contact.contact_normal * body_b.collider.sphere.radius;
    contact.a_surface_normal =  contact.contact_normal;
    contact.b_surface_normal = -contact.contact_normal;

    return_is_contact();
}

solve_contact_sphere_plane :: (body_a: *Physics_Body_Internal, body_b: *Physics_Body_Internal, contact: *Physics_Contact) -> bool {
    physics_check(.HIGH, body_a.collider.shape == .SPHERE && body_b.collider.shape == .PLANE);
    using context.physical_world;

    contact.contact_normal = -y_axis(body_b);
    sphere_center_projection_onto_plane, distance_from_plane := project_point_onto_plane(body_a.next_position, body_b.next_position, y_axis(body_b));

    // todo: negative side
    if distance_from_plane <= body_a.collider.sphere.radius {
        if distance_from_plane < -body_a.collider.sphere.radius {
            return false;
        }
        contact.a_contact_offset = contact.contact_normal * body_a.collider.sphere.radius;
        contact.b_contact_offset = sphere_center_projection_onto_plane - body_b.next_position;
        contact.a_surface_normal = contact.contact_normal;
        contact.b_surface_normal = -contact.contact_normal;
        contact.contact_time     = 0;
        contact.overlap          = body_a.collider.sphere.radius - distance_from_plane;
        return true;
    }

    // assuming side

    contact.contact_time = calculate_contact_time(contact.contact_normal, body_a.next_position, body_b.next_position, body_a.linear_velocity, body_b.linear_velocity, distance_from_plane, body_a.collider.sphere.radius);

    contact_point := body_a.next_position + body_a.linear_velocity * contact.contact_time + contact.contact_normal * body_a.collider.sphere.radius;
    plane_position_at_contact_time := body_b.next_position + body_b.linear_velocity * contact.contact_time;

    contact.a_contact_offset =  contact.contact_normal * body_a.collider.sphere.radius;
    contact.b_contact_offset =  contact_point - plane_position_at_contact_time;
    contact.a_surface_normal =  contact.contact_normal;
    contact.b_surface_normal = -contact.contact_normal;
    contact.overlap          = 0;

    return_is_contact();
}

solve_contact_sphere_rectangle :: (body_a: *Physics_Body_Internal, body_b: *Physics_Body_Internal, contact: *Physics_Contact) -> bool {
    physics_check(.HIGH, body_a.collider.shape == .SPHERE && body_b.collider.shape == .RECTANGLE);
    
    contact.contact_normal = -y_axis(body_b);
    sphere_center_projection_onto_plane, distance_from_plane := project_point_onto_plane(body_a.next_position, body_b.next_position, y_axis(body_b));

    // todo: negative side
    if distance_from_plane <= body_a.collider.sphere.radius {
        if distance_from_plane < -body_a.collider.sphere.radius {
            return false;
        }

        clamped_projection := clamp_point_to_rect(sphere_center_projection_onto_plane, body_b.next_position, z_axis(body_b), x_axis(body_b), body_b.collider.rectangle.half_height, body_b.collider.rectangle.half_width);
        diff    := clamped_projection - body_a.next_position;
        dist_sq := length_squared(diff);

        if dist_sq < square(body_a.collider.sphere.radius) {
            dist := 0.0;
            if dist_sq > VERY_SMALL_NUMBER {
                dist                   = sqrt(dist_sq);
                contact.contact_normal = diff / dist;
            }
            contact.a_contact_offset = contact.contact_normal * body_a.collider.sphere.radius;
            contact.b_contact_offset = clamped_projection - body_b.next_position;
            contact.a_surface_normal = contact.contact_normal;
            contact.b_surface_normal = -contact.contact_normal;
            contact.contact_time     = 0;
            contact.overlap          = body_a.collider.sphere.radius - dist;
            return true;
        }
        // else, could still be a side hit
    }

    contact.contact_time = calculate_contact_time(contact.contact_normal, body_a.next_position, body_b.next_position, body_a.linear_velocity, body_b.linear_velocity, distance_from_plane, body_a.collider.sphere.radius);

    plane_contact_point := body_a.next_position + body_a.linear_velocity * contact.contact_time + contact.contact_normal * body_a.collider.sphere.radius;

    if contact.contact_time < 0 || contact.contact_time > context.physical_world.delta_time {
        return false;
    }

    b_position_at_toc     := body_b.next_position + body_b.linear_velocity * contact.contact_time;
    clamped_contact_point := clamp_point_to_rect(plane_contact_point, b_position_at_toc, z_axis(body_b), x_axis(body_b), body_b.collider.rectangle.half_height, body_b.collider.rectangle.half_width);

    toward_clamped_contact_diff   := clamped_contact_point - body_a.next_position;
    distance_from_clamped_contact := length(toward_clamped_contact_diff);

    contact.contact_normal = toward_clamped_contact_diff / distance_from_clamped_contact;
    contact.contact_time   = calculate_contact_time(contact.contact_normal, body_a.next_position, clamped_contact_point, body_a.linear_velocity, body_b.linear_velocity, distance_from_clamped_contact, body_a.collider.sphere.radius);

    rectangle_contact_point            := body_a.next_position + body_a.linear_velocity * contact.contact_time + contact.contact_normal * body_a.collider.sphere.radius;
    rectangle_position_at_contact_time := body_b.next_position + body_b.linear_velocity * contact.contact_time;

    contact.a_contact_offset =  contact.contact_normal * body_a.collider.sphere.radius;
    contact.b_contact_offset =  rectangle_contact_point - rectangle_position_at_contact_time;
    contact.a_surface_normal =  contact.contact_normal;
    contact.b_surface_normal = -contact.contact_normal;
    contact.overlap          = 0;

    return_is_contact();
}

#scope_module

// worked out on paper but I'm usually wrong the first time
// if spheres, buffer distance is r1 + r2, giving
// t = (r1 + r2 - len(d) - dhat * px1 + dhat * px2) / (dhat * vx1 - dhat * vx2)
calculate_contact_time :: (contact_normal: Vector3, a_position: Vector3, b_position: Vector3, a_velocity: Vector3, b_velocity: Vector3, cur_distance: float, buffer_distance: float) -> float {
    dhat_px1 := dot(a_position, contact_normal);
    dhat_px2 := dot(b_position, contact_normal);
    dhat_vx1 := dot(a_velocity, contact_normal);
    dhat_vx2 := dot(b_velocity, contact_normal);
    return (buffer_distance - cur_distance - dhat_px1 + dhat_px2) / (dhat_vx1 - dhat_vx2);
}

return_is_contact :: () #expand {
    `return `contact.contact_time >= 0 && `contact.contact_time < context.physical_world.delta_time;
}

flip :: inline (using contact: *Physics_Contact) {
    a_contact_offset, b_contact_offset = b_contact_offset, a_contact_offset;
    a_surface_normal, b_surface_normal = b_surface_normal, a_surface_normal;
    contact_normal *= -1;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

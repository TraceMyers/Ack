Raycast_Request :: struct {
    ray_origin: Vector3;
    ray_destination: Vector3;
    // can hit back face regardless of whether started inside or not. useful for rectangles (or volumes with holes?)
    can_hit_back_face: bool;
    // if the ray hits a back face and this is true, returns the negated/inside normal.
    return_back_face_normal: bool;
    // these are for repeat usage, so the direction + len is only calculated once
    ray_direction: Vector3;
    ray_length: float;
    ray_direction_and_length_calculated: bool;
}

Raycast_Result :: struct {
    ray_origin: Vector3;
    ray_destination: Vector3;
    using clear_if_miss: struct {
        hit_distance := FLOAT32_MAX;
        hit_location: Vector3;
        hit_normal: Vector3;
        is_hit: bool;
        hit_back_face: bool;
        origin_inside_collider: bool;
        normal_is_degenerate: bool;
        normal_is_inside: bool;
    }
}

make_raycast_request :: inline (ray_begin: Vector3, ray_end: Vector3) -> Raycast_Request {
    return Raycast_Request.{ray_origin=ray_begin, ray_destination=ray_end};
}

// if you already have direction & length, saves a little calculation time.
make_raycast_request :: inline (ray_origin: Vector3, ray_direction: Vector3, ray_length: float) -> Raycast_Request {
    physics_check(.HIGH, is_normalized(ray_direction));
    return Raycast_Request.{
        ray_origin = ray_origin, 
        ray_destination = ray_origin + ray_direction * ray_length, 
        ray_direction = ray_direction,
        ray_length = ray_length,
        ray_direction_and_length_calculated = true
    };
}

// convenience procedure for raycasting to a collider
raycast :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, orientation: Quaternion, collider: Physics_Collider) -> bool {
    if #complete collider.shape == {
    case .PLANE;
        return raycast_plane(request, result, center, get_fore_direction(orientation));
    case .CIRCLE;
        return raycast_circle(request, result, center, collider.circle, get_fore_direction(orientation));
    case .RECTANGLE;
        return raycast_rectangle(request, result, center, collider.rectangle, get_up_direction(orientation), get_right_direction(orientation), get_fore_direction(orientation));
    case .CYLINDER;
        return raycast_cylinder(request, result, center, collider.cylinder, get_up_direction(orientation));
    case .BOX;
        return raycast_box(request, result, center, collider.box, get_up_direction(orientation), get_fore_direction(orientation), get_right_direction(orientation));
    case .SPHERE;
        return raycast_sphere(request, result, center, collider.sphere);
    case .CAPSULE;
        return raycast_capsule(request, result, center, collider.capsule, get_up_direction(orientation));
    case .CONVEX;
        // todo: raycast_convex. true/false I think mostly done but not hit location, normal
        return false;
    case .TRIANGLE_U16;
        #through;
    case .TRIANGLE_U32;
        physics_check(.LOW, false, "triangles aren't stored on physics colliders, so this request can't be handled.");
        return false;
    }
}

raycast_plane :: (request: *Raycast_Request, result: *Raycast_Result, point_on_plane: Vector3, plane_normal: Vector3) -> bool {
    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    diff_to_plane := point_on_plane - request.ray_origin ;
    dist_sq_to_plane := length_squared(diff_to_plane);
    signed_distance_to_plane := dot(diff_to_plane, plane_normal);

    if dist_sq_to_plane <= VERY_SMALL_NUMBER {
        result.origin_inside_collider = true;
        result.hit_distance = 0;
        result.hit_location = request.ray_origin;
        result.hit_normal = plane_normal;
        result.is_hit = true;
        if request.return_back_face_normal {
            result.hit_back_face = true;
            result.hit_normal = -result.hit_normal;
        }
    } else  {
        pointing_cos_t := dot(plane_normal, request.ray_direction);
        impact_dist := signed_distance_to_plane / pointing_cos_t;

        // pointing wrong direction or too far?
        if impact_dist >= 0 && impact_dist <= request.ray_length {
            on_front_side := signed_distance_to_plane <= 0;
            on_back_side_and_can_hit_back_face := signed_distance_to_plane > 0 && request.can_hit_back_face;

            set_hit :: () #expand {
                `result.is_hit = true;
                `result.hit_distance = `impact_dist;
                `result.hit_location = `request.ray_origin + `request.ray_direction * `impact_dist;
            }

            if on_front_side {
                set_hit();
                result.hit_normal = plane_normal;
                result.hit_back_face = false;
            } else if on_back_side_and_can_hit_back_face {
                set_hit();
                if request.return_back_face_normal {
                    result.hit_normal = -plane_normal;
                    result.normal_is_inside = true;
                } else {
                    result.hit_normal = plane_normal;
                }
                result.hit_back_face = true;
            }
        }
    }

    result.normal_is_degenerate = !is_normalized(result.hit_normal, SMALL_NUMBER);
    return result.is_hit;
}

raycast_circle :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, circle: Shape_Circle, plane_normal: Vector3) -> bool {
    return raycast_circle(request, result, center, circle.radius, plane_normal);
}

raycast_circle :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, radius: float, plane_normal: Vector3) -> bool {
    // initialization stuff is done in this proc call
    raycast_plane(request, result, center, plane_normal);
    if result.is_hit {
        if distance_squared(center, result.hit_location) > square(radius) {
            result.clear_if_miss = {};
        }
    }

    return result.is_hit;
}

raycast_rectangle :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, rectangle: Shape_Rectangle, height_direction: Vector3, width_direction: Vector3, plane_normal: Vector3) -> bool {
    return raycast_rectangle(request, result, center, rectangle.half_height, rectangle.half_width, height_direction, width_direction, plane_normal); 
}

raycast_rectangle :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, half_height: float, half_width: float, height_direction: Vector3, width_direction: Vector3, plane_normal: Vector3) -> bool {
    // initialization stuff is done in this proc call
    raycast_plane(request, result, center, plane_normal);
    if result.is_hit {
        toward_hit_diff := result.hit_location - center;
        width_dist := dot(width_direction, toward_hit_diff);
        if abs(width_dist) > half_width {
            result.clear_if_miss = {};
        }
        height_dist := dot(height_direction, toward_hit_diff);
        if abs(height_dist) > half_height {
            result.clear_if_miss = {};
        }
    }

    return result.is_hit;
}

raycast_cylinder :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, cylinder: Shape_Cylinder, height_direction: Vector3) -> bool {
    return raycast_cylinder(request, result, center, cylinder.half_height, cylinder.radius, height_direction);
}

raycast_cylinder :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, half_height: float, radius: float, height_direction: Vector3) -> bool {
    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    result.origin_inside_collider = is_point_inside_cylinder(request.ray_origin, center, radius, half_height, height_direction);
    can_hit_back_face := request.can_hit_back_face & result.origin_inside_collider;

    if !result.origin_inside_collider || can_hit_back_face {
        top_center := center + half_height * height_direction;
        bot_center := center - half_height * height_direction;

        top_plane_result: Raycast_Result_Simple = ---;
        bot_plane_result: Raycast_Result_Simple = ---;
        raycast_plane(*top_plane_result, request.ray_origin, request.ray_direction, top_center, height_direction);
        raycast_plane(*bot_plane_result, request.ray_origin, request.ray_direction, bot_center, -height_direction);

        hit_top_plane := top_plane_result.is_hit && top_plane_result.hit_distance <= request.ray_length;
        hit_bot_plane := bot_plane_result.is_hit && bot_plane_result.hit_distance <= request.ray_length;

        try_hit_circle :: inline (result: *Raycast_Result, plane_intersection: Vector3, circle_center: Vector3, radius: float, distance: float, normal: Vector3) -> bool {
            dist_sq_to_intersection := distance_squared(plane_intersection, circle_center);
            if dist_sq_to_intersection <= radius * radius {
                result.is_hit = true;
                result.hit_distance = distance;
                result.hit_location = plane_intersection;
                result.hit_normal = normal;
                return true;
            } else return false;
        }

        try_hit_back_of_circle :: inline (result: *Raycast_Result, plane_intersection: Vector3, circle_center: Vector3, radius: float, distance: float, normal: Vector3, can_hit_back_face: bool, return_back_face_normal: bool) {
            if can_hit_back_face && try_hit_circle(result, plane_intersection, circle_center, radius, distance, normal) {
                result.origin_inside_collider = true;
                result.hit_back_face = true;
                if return_back_face_normal {
                    result.hit_normal *= -1;
                    result.normal_is_inside = true;
                }
            }
        }

        if hit_top_plane && hit_bot_plane {
            if top_plane_result.hit_distance < bot_plane_result.hit_distance {
                try_hit_circle(result, top_plane_result.hit_location, top_center, radius, top_plane_result.hit_distance, height_direction);
            } else {
                try_hit_circle(result, bot_plane_result.hit_location, bot_center, radius, bot_plane_result.hit_distance, -height_direction);
            }
        } else if hit_top_plane {
            if top_plane_result.hit_back_face {
                try_hit_back_of_circle(result, top_plane_result.hit_location, top_center, radius, top_plane_result.hit_distance, height_direction, can_hit_back_face, request.return_back_face_normal);
            } else {
                try_hit_circle(result, top_plane_result.hit_location, top_center, radius, top_plane_result.hit_distance, height_direction);
            }
        } else if hit_bot_plane {
            if bot_plane_result.hit_back_face {
                try_hit_back_of_circle(result, bot_plane_result.hit_location, bot_center, radius, bot_plane_result.hit_distance, -height_direction, can_hit_back_face, request.return_back_face_normal);
            } else {
                try_hit_circle(result, bot_plane_result.hit_location, bot_center, radius, bot_plane_result.hit_distance, -height_direction);
            }
        }

        // if already hit, then it hit the top or bottom
        if !result.is_hit {
            try_raycast_cylinder_side(request, result, center, half_height, radius, height_direction, can_hit_back_face);
        }
    }

    result.normal_is_degenerate = !is_normalized(result.hit_normal);
    return result.is_hit;
}

raycast_box :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, box: Shape_Box, height_direction: Vector3, length_direction: Vector3, width_direction: Vector3) -> bool {
    return raycast_box(request, result, center, box.half_height, box.half_length, box.half_width, height_direction, length_direction, width_direction);
}

raycast_box :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, half_height: float, half_length: float, half_width: float, height_direction: Vector3, length_direction: Vector3, width_direction: Vector3) -> bool {
    // ------

    Dist_And_Norm :: struct {
        dist: float;
        normal: Vector3;
    }

    first_dist_is_lesser :: (a: Dist_And_Norm, b: Dist_And_Norm) -> bool {
        return a.dist < b.dist;
    }

    get_slab_intersection_distances :: (face_center: Vector3, face_normal: Vector3, extent: float, inv_cos_t: float) -> Dist_And_Norm, Dist_And_Norm #expand {
        diff_to_plane := face_center - `request.ray_origin;
        signed_distance_to_plane := dot(diff_to_plane, face_normal);

        intersection_a_dist := signed_distance_to_plane * inv_cos_t;
        _isnan, _isinf := is_nan_is_inf(intersection_a_dist);
        if _isinf {
            return {-1, face_normal}, {request.ray_length+1, -face_normal};
        }
        // scaling 2 * extent by cos(t) gives distance along the ray across
        // the solid, since the two faces share the same normal.
        intersection_b_dist := intersection_a_dist + (2 * extent) * -inv_cos_t;

        return {intersection_a_dist, face_normal}, {intersection_b_dist, -face_normal};
    }

    // ------

    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    result.origin_inside_collider = is_point_inside_box(request.ray_origin, center, {half_width, half_length, half_height}, width_direction, length_direction, height_direction);

    box_right_center := center + (half_width  * width_direction);
    box_left_center  := center - (half_width  * width_direction);
    box_front_center := center + (half_length * length_direction);
    box_rear_center  := center - (half_length * length_direction);
    box_top_center   := center + (half_height * height_direction);
    box_bot_center   := center - (half_height * height_direction);

    inv_width_cos_t  := 1.0 / dot(width_direction,  request.ray_direction);
    inv_length_cos_t := 1.0 / dot(length_direction, request.ray_direction);
    inv_height_cos_t := 1.0 / dot(height_direction, request.ray_direction);

    can_hit_back_face := request.can_hit_back_face & result.origin_inside_collider;

    if !result.origin_inside_collider || can_hit_back_face {
        right_intersection_dist, left_intersection_dist := get_slab_intersection_distances(box_right_center, width_direction, half_width, inv_width_cos_t);
        front_intersection_dist, rear_intersection_dist := get_slab_intersection_distances(box_front_center, length_direction, half_length, inv_length_cos_t);
        top_intersection_dist, bot_intersection_dist := get_slab_intersection_distances(box_top_center, height_direction, half_height, inv_height_cos_t);

        width_min_idist, width_max_idist   := min_and_max(right_intersection_dist, left_intersection_dist, first_dist_is_lesser);
        length_min_idist, length_max_idist := min_and_max(front_intersection_dist, rear_intersection_dist, first_dist_is_lesser);
        height_min_idist, height_max_idist := min_and_max(top_intersection_dist, bot_intersection_dist, first_dist_is_lesser);

        min_idist := max(width_min_idist, max(length_min_idist, height_min_idist, first_dist_is_lesser), first_dist_is_lesser);
        // may end up with inf here, which is fine, since all real values
        // give x < inf -> true.
        max_idist := min(width_max_idist, min(length_max_idist, height_max_idist, first_dist_is_lesser), first_dist_is_lesser);

        if !result.origin_inside_collider {
            if min_idist.dist <= request.ray_length && min_idist.dist < max_idist.dist && max_idist.dist > 0 {
                result.is_hit = true;
                result.hit_location = request.ray_origin + min_idist.dist * request.ray_direction;
                result.hit_distance = min_idist.dist;
                result.hit_normal = min_idist.normal;
            }
        } else {
            if max_idist.dist <= request.ray_length && max_idist.dist > min_idist.dist && min_idist.dist < 0 {
                result.is_hit = true;
                result.hit_back_face = true;
                result.hit_location = request.ray_origin + max_idist.dist * request.ray_direction;
                result.hit_distance = max_idist.dist;
                if request.return_back_face_normal {
                    result.hit_normal = -max_idist.normal;
                    result.normal_is_inside = true;
                } else {
                    result.hit_normal = max_idist.normal;
                }
            }
        }
    }

    result.normal_is_degenerate = !is_normalized(result.hit_normal);
    return result.is_hit;
}

raycast_sphere :: inline (request: *Raycast_Request, result: *Raycast_Result, sphere_center: Vector3, sphere: Shape_Sphere) -> bool {
    return raycast_sphere(request, result, sphere_center, sphere.radius);
}

raycast_sphere :: (request: *Raycast_Request, result: *Raycast_Result, sphere_center: Vector3, sphere_radius: float) -> bool {
    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    sphere_radius_sq := square(sphere_radius);

    toward_sphere_diff    := request.ray_origin - sphere_center;
    toward_sphere_dist_sq := length_squared(toward_sphere_diff);

    if toward_sphere_dist_sq < sphere_radius_sq {
        // origin inside volume
        result.origin_inside_collider = true;

        if request.can_hit_back_face {
            // hit is true only if ray intersects an inside face of the volume
            ray_end_diff := request.ray_destination - sphere_center;
            ray_end_dist_sq := length_squared(ray_end_diff);
            if ray_end_dist_sq >= sphere_radius_sq {
                result.is_hit = true;
                result.hit_back_face = true;

                line_pt := closest_point_on_line(sphere_center, request.ray_origin, request.ray_destination);
                line_pt_dist_sq := distance_squared(line_pt, sphere_center);

                raycast_sphere_hit_calculation(sphere_center, sphere_radius, request.ray_origin, -request.ray_direction, line_pt, line_pt_dist_sq, result);

                if request.return_back_face_normal {
                    result.normal_is_inside = true;
                } else {
                    result.hit_normal *= -1;
                }
            }
        }
    } else {
        // if we can get the t of the projection, we can know if it's normal-forward or normal-backward
        line_pt, segment_pt: Vector3;
        closest_point_on_line_and_segment(sphere_center, request.ray_origin, request.ray_destination, *line_pt, *segment_pt);
        segment_pt_dist_sq := distance_squared(segment_pt, sphere_center);
        if segment_pt_dist_sq < sphere_radius_sq {
            result.is_hit = true;
            line_pt_dist_sq := distance_squared(line_pt, sphere_center);
            raycast_sphere_hit_calculation(sphere_center, sphere_radius, request.ray_origin, request.ray_direction, line_pt, line_pt_dist_sq, result);
        }
    }

    result.normal_is_degenerate = !is_normalized(result.hit_normal);
    return result.is_hit;
}

raycast_capsule :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, capsule: Shape_Capsule, height_direction: Vector3) -> bool {
    return raycast_capsule(request, result, center, capsule.half_height, capsule.radius, height_direction);
}

raycast_capsule :: (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, half_height: float32, radius: float32, height_direction: Vector3) -> bool {
    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    // 'cyl' here means 'cylinder' or 'cylinder inner line segment'
    cyl_top := center + height_direction * (half_height - radius);
    cyl_bot := center - height_direction * (half_height - radius);

    closest_point_on_cyl := closest_point_on_line_segment(request.ray_origin, cyl_bot, cyl_top);
    dist_sq := distance_squared(closest_point_on_cyl, request.ray_origin);

    dummy_request := request.*;
    dummy_request.can_hit_back_face = false;

    origin_inside_collider: bool;

    if dist_sq <= square(radius) {
        origin_inside_collider = true;
        // raycasting inward from the outside avoids annoying inner shape collision issues (casting to inner spheres at endcaps, but only want to hit the outside)
        // cheat distance is the longest possible distance it could take to get outside the capsule. fails for very large numbers, ofc.
        ERROR :: 1.0;
        cheat_distance := sqrt(square(radius) + square(2 * half_height)) + ERROR;
        dummy_request.ray_origin += dummy_request.ray_direction * cheat_distance;
        dummy_request.ray_length += cheat_distance;
        dummy_request.ray_direction *= -1;
        dummy_request.ray_destination = dummy_request.ray_origin + dummy_request.ray_direction * dummy_request.ray_length;
    }

    hit_top_or_bottom: bool;

    if raycast_sphere(*dummy_request, result, cyl_top, radius) {
        if dot(result.hit_location - cyl_top, height_direction) > 0 {
            hit_top_or_bottom = true;
        } else {
            result.clear_if_miss = {};
        }
    }
    if !hit_top_or_bottom && raycast_sphere(*dummy_request, result, cyl_bot, radius) {
        if dot(result.hit_location - cyl_bot, -height_direction) > 0 {
            hit_top_or_bottom = true;
        } else {
            result.clear_if_miss = {};
        }
    }
    if !hit_top_or_bottom {
        try_raycast_cylinder_side(*dummy_request, result, center, half_height - radius, radius, height_direction, false);
    }

    result.origin_inside_collider = origin_inside_collider;

    if result.is_hit && result.origin_inside_collider {
        if distance_squared(request.ray_origin, result.hit_location) > square(request.ray_length) {
            result.clear_if_miss = {};
        } else {
            result.hit_distance = dot(result.hit_location - request.ray_origin, request.ray_direction);
            result.hit_back_face = true;
            if request.return_back_face_normal {
                result.hit_normal *= -1;
                result.normal_is_inside = true;
            }
        }
    }
    
    result.normal_is_degenerate = !is_normalized(result.hit_normal);
    return result.is_hit;
}

// assuming clockwise normal for a -> b -> c
raycast_triangle :: (request: *Raycast_Request, result: *Raycast_Result, a: Vector3, b: Vector3, c: Vector3) -> bool {
    calculate_ray_direction_and_length(request);
    result.* = {ray_origin=request.ray_origin, ray_destination=request.ray_destination};

    normal: Vector3 = ---;
    simple_result: Raycast_Result_Simple = ---;

    if raycast_triangle(*simple_result, request.ray_origin, request.ray_direction, a, b, c, *normal) && simple_result.hit_distance <= request.ray_length {
        if simple_result.hit_back_face {
            if request.can_hit_back_face {
                result.is_hit = true;
                result.hit_location = simple_result.hit_location;
                result.hit_distance = simple_result.hit_distance;
                result.hit_back_face = true;
                if request.return_back_face_normal {
                    result.hit_normal = -normal;
                }
            }
        } else {
            result.is_hit = true;
            result.hit_normal = normal;
            result.hit_location = simple_result.hit_location;
            result.hit_distance = simple_result.hit_distance;
        }
    }

    result.normal_is_degenerate = !is_normalized(result.hit_normal);
    return result.is_hit;
}

#scope_module

calculate_ray_direction_and_length :: inline (request: *Raycast_Request) {
    if !request.ray_direction_and_length_calculated {
        ray_diff := request.ray_destination - request.ray_origin;
        ray_length_sq := length_squared(ray_diff);
        if ray_length_sq <= VERY_SMALL_NUMBER {
            request.ray_length = 0;
            request.ray_direction = {};
        } else {
            request.ray_length = sqrt(ray_length_sq);
            request.ray_direction = ray_diff / request.ray_length;
        }
        request.ray_direction_and_length_calculated = true;
    }
}

raycast_sphere_hit_calculation :: inline (sphere_center: Vector3, sphere_radius: float, ray_origin: Vector3, ray_direction: Vector3, line_pt: Vector3, line_pt_dist_sq: float, result: *Raycast_Result) {
    projection_tri_edge_dist_sq := square(sphere_radius) - line_pt_dist_sq;
    if projection_tri_edge_dist_sq < VERY_SMALL_NUMBER {
        result.hit_location = sphere_center - ray_direction * sphere_radius;
        result.hit_normal = -ray_direction;
    } else {
        projection_tri_edge_dist := sqrt(projection_tri_edge_dist_sq);
        result.hit_location = line_pt - ray_direction * projection_tri_edge_dist;
        result.hit_normal = normalize(result.hit_location - sphere_center);
    }
    result.hit_distance = distance(ray_origin, result.hit_location);
}

try_raycast_cylinder_side :: inline (request: *Raycast_Request, result: *Raycast_Result, center: Vector3, half_height: float, radius: float, height_direction: Vector3, can_hit_back_face: bool) -> bool {
    // analytic ray-cylinder side intersection: project the ray and origin offset onto the
    // // plane perpendicular to the axis, then solve |X_perp + t*D_perp|^2 = r^2 for t.

    toward_ray_origin   := request.ray_origin - center;
    origin_projected    := toward_ray_origin - dot(toward_ray_origin, height_direction) * height_direction;
    direction_projected := request.ray_direction - dot(request.ray_direction, height_direction) * height_direction;

    a := length_squared(direction_projected);
    b := 2.0 * dot(origin_projected, direction_projected);
    c := length_squared(origin_projected) - square(radius);

    // a is sin^2(angle between ray and axis); near zero means ray is parallel to the axis,
    // in which case the side cannot be entered
    if a > VERY_SMALL_NUMBER {
        discriminant := square(b) - 4.0 * a * c;
        if discriminant >= 0 {
            sqrt_disc := sqrt(discriminant);

            // citardauq form: pick the addition that doesn't cancel, derive the other root via Vieta's.
            q      := -0.5 * (b + (ifx b >= 0 then sqrt_disc else -sqrt_disc));
            t1     := q / a;
            t2     := ifx q != 0 then c / q else t1;
            t_near := min(t1, t2);
            t_far  := max(t1, t2);

            try_register_side_hit :: (result: *Raycast_Result, request: *Raycast_Request, t: float, center: Vector3, axis: Vector3, half_height: float, radius: float, is_back_face: bool) -> bool {
                if t < 0 || t > request.ray_length return false;
                hit_location := request.ray_origin + request.ray_direction * t;
                height_offset := dot(hit_location - center, axis);
                if abs(height_offset) > half_height return false;

                axis_point := center + height_offset * axis;
                normal := (hit_location - axis_point) / radius;

                result.is_hit = true;
                result.hit_distance = t;
                result.hit_location = hit_location;
                if is_back_face {
                    result.hit_back_face = true;
                    if request.return_back_face_normal {
                        result.hit_normal = -normal;
                        result.normal_is_inside = true;
                    } else {
                        result.hit_normal = normal;
                    }
                } else {
                    result.hit_normal = normal;
                }
                return true;
            }

            if try_register_side_hit(result, request, t_near, center, height_direction, half_height, radius, false) {
                return true;
            } else if can_hit_back_face {
                if try_register_side_hit(result, request, t_far, center, height_direction, half_height, radius, true) {
                    return true;
                }
            }
        }
    }

    return false;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

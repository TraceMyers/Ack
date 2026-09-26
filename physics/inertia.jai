calculate_centered_inverse_inertia :: (body: *Physics_Body_Base) -> Vector3 {
    body := cast(*Physics_Body_Internal) _body;
    mass := body.properties.mass;
    using body.collider;

    if shape == {
    case .CIRCLE;
        ix := 2.0 / (mass * square(cylinder.radius));
        iz := (mass * square(cylinder.radius));
        return {ix, ix, iz};
    case .RECTANGLE;
        // todo: handle rectangle inertia
    case .CYLINDER;
        ix := 12 / (mass * (3 * square(cylinder.radius) + square(2 * cylinder.half_height)));
        iz := 2  / (mass * square(cylinder.radius));
        return {ix, ix, iz};
    case .BOX;
        ix := 12 / (mass * (square(2 * box.half_length) + square(2 * box.half_height)));
        iy := 12 / (mass * (square(2 * box.half_width)  + square(2 * box.half_height)));
        iz := 12 / (mass * (square(2 * box.half_length) + square(2 * box.half_width)));
        return {ix, iy, iz};
    case .PILLBOX;
        // just using box inertia here. close enough
        ix := 12 / (mass * (square(2 * (pillbox.half_box_length + pillbox.radius)) + square(2 * pillbox.half_height)));
        iy := 12 / (mass * (square(2 * pillbox.radius) + square(2 * pillbox.half_height)));
        iz := 12 / (mass * (square(2 * (pillbox.half_box_length + pillbox.radius)) + square(2 * pillbox.radius)));
        return {ix, iy, iz};
    case .SPHERE;
        ix := 5 / (2 * mass * square(sphere.radius));
        return splat(ix, 3);
    case .CAPSULE;
        // just using cylinder inertia here because close enough. todo: change later
        // if half height == radius, then this will be a little off...
        ix := 12 / (mass * (3 * square(capsule.radius) + square(2 * capsule.half_height)));
        iz := 2  / (mass * square(capsule.radius));
        return {ix, ix, iz};
    }
    return {};
}

#scope_module

// line_dist_sq :: (point: Vector3, line_point: Vector3, norm_line_direction: Vector3) -> float #expand {
//     toward_point := point - line_point;
//     t            := dot(norm_line_direction, toward_point);
//     return distance_squared(point, line_point + t * norm_line_direction);
// }

// calculate the inertia of a shape along a specific axis by estimating it with point masses distributed throughout
// acceleration axis does not need to be normalized
// calculate_point_mass_inertia :: (_body: *Physics_Body_Base, local_pivot_offset: Vector3, local_axis_of_acceleration: Vector3) -> float {
//     body := cast(*Physics_Body_Internal) _body;
//     axis := normalize(local_axis_of_acceleration);

//     if body.collider.shape == {
//     case .CIRCLE;
//         return calculate_circle_point_mass_inertia(body, local_pivot_offset, axis);
//     case .RECTANGLE;
//     case .CYLINDER;
//     case .BOX;
//     case .PILLBOX;
//     case .SPHERE;
//     case .CAPSULE;
//     case .CONVEX;
//     }

//     return 0;
// }

// calculate_circle_point_mass_inertia :: (_body: *Physics_Body_Base, local_pivot_offset: Vector3, axis: Vector3) -> float {
//     body := cast(*Physics_Body_Internal) _body;
//     mass := body.properties.mass;
//     using body.collider.circle;

//     // my attempt at an even mass distribution of 16 points over a circle.
//     // put  4 points in the inner circle with radius = R / 2, commanding 1/4 the area of the total circle
//     // put 12 points in the outer ring, commanding 3/4 the area. so, inner and outer areas have even mass distribution.
//     // further, the inner circle has symmetrical distribution between points as well as along the radius.
//     // and the outer ring has symmetrical distribution along the circle inside the ring, as well as along the radius
//     // of the ring.
//     INNER_CIRCLE_FACTOR :: #run (sqrt(2) * PI) / 16.0;
//     OUTER_CIRCLE_FACTOR :: #run sqrt(5/8);

//     inner_circle_dist := INNER_CIRCLE_FACTOR * radius;
//     outer_circle_dist := OUTER_CIRCLE_FACTOR * radius;

//     inertia := 0.0;

//     // 4 inner circle points
//     inertia += line_dist_sq(body.next_position + body.x_axis * inner_circle_dist, local_pivot_offset, axis);
//     inertia += line_dist_sq(body.next_position + body.y_axis * inner_circle_dist, local_pivot_offset, axis);
//     inertia += line_dist_sq(body.next_position - body.x_axis * inner_circle_dist, local_pivot_offset, axis);
//     inertia += line_dist_sq(body.next_position - body.y_axis * inner_circle_dist, local_pivot_offset, axis);

//     // 12 outer ring points
//     #insert -> string {
//         builder: String_Builder;
//         for 0..11 {
//             print(*builder,
//             #string HERE
//                 {
//                     COS_T :: #run cos(% * PI / 12);
//                     SIN_T :: #run sin(% * PI / 12);
//                     x_offset := body.x_axis * (outer_circle_dist * COS_T);
//                     y_offset := body.y_axis * (outer_circle_dist * SIN_T);
//                     inertia := line_dist_sq(body.next_position + x_offset + y_offset, local_pivot_offset, axis);
//                 }
//             HERE,
//                 it * 2 + 1, it * 2 + 1
//             );
//         }
//         retrurn builder_to_string(*builder);
//     }

//     inertia *= mass;
//     return inertia;
// }

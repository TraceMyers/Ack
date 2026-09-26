
get_bounding_sphere_from_circle :: inline (circle: Shape_Circle) -> Shape_Sphere {
    return {circle.radius};
}

get_bounding_sphere_from_rectangle :: inline (rectangle: Shape_Rectangle) -> Shape_Sphere {
    radius := sqrt(square(rectangle.half_height) + square(rectangle.half_width));
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_cylinder :: inline (cylinder: Shape_Cylinder) -> Shape_Sphere {
    radius := sqrt(square(cylinder.half_height) + square(cylinder.radius));
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_box :: inline (box: Shape_Box) -> Shape_Sphere {
    radius := sqrt(square(box.half_height) + square(box.half_length) + square(box.half_width));
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_pillbox :: inline (pillbox: Shape_Pillbox) -> Shape_Sphere {
    half_length := pillbox.half_box_length + pillbox.radius;
    radius := sqrt(square(pillbox.half_height) + square(half_length) + square(radius));
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_capsule :: inline (capsule: Shape_Capsule) -> Shape_Sphere {
    radius := sqrt(square(capsule.half_height) + square(capsule.radius));
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_convex :: inline (convex: Shape_Convex) -> Shape_Sphere {
    radius_sq: float;
    data := get_convex_data(convex);
    for data.points {
        radius_sq = max(radius_sq, length_squared(data.center, it));
    }
    radius := sqrt(radius_sq);
    return {radius + radius * ERROR_FACTOR};
}

get_bounding_sphere_from_triangle :: inline (a: Vector3, b: Vector3, c: Vector3, out_center: *Vector3) -> Shape_Sphere {
    ONE_THIRD :: #run 1.0 / 3.0;
    out_center.*  = (a + b + c) * ONE_THIRD;
    radius_sq    := distance_squared(out_center.*, a);
    radius_sq     = max(radius_sq, distance_squared(out_center.*, b));
    radius_sq     = max(radius_sq, distance_squared(out_center.*, c));
    radius       := sqrt(radius_sq);
    return {radius = radius + radius * ERROR_FACTOR};
}

#scope_module

ERROR_FACTOR :: VERY_SMALL_NUMBER;

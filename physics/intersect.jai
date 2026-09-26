ray_intersects_sphere :: inline (ray_origin: Vector3, ray_destination: Vector3, sphere_center: Vector3, sphere_radius: float) -> bool {
    return distance_squared_from_line_segment(sphere_center, ray_origin, ray_destination) <= square(sphere_radius);
}

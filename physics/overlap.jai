overlap_sphere_sphere :: inline (position_a: Vector3, sphere_a: Shape_Sphere, position_b: Vector3, sphere_b: Shape_Sphere) -> bool {
    distance_sq        := distance_squared(position_a, position_b);
    combined_radius_sq := square(sphere_a.radius + sphere_b.radius);
    return distance_sq <= combined_radius_sq;
}

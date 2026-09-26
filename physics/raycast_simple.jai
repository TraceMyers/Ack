// optionally quicken hot path raycasts for a select few shapes. 
// probably triangle and plane mostly.

Raycast_Result_Simple :: struct {
    hit_location: Vector3;
    hit_distance: float;
    is_hit: bool;
    hit_back_face: bool;
}

raycast_plane :: inline (result: *Raycast_Result_Simple, ray_origin: Vector3, ray_direction: Vector3, point_on_plane: Vector3, plane_normal: Vector3) -> bool {
    diff_to_plane            := point_on_plane - ray_origin;
    signed_distance_to_plane := dot(diff_to_plane, plane_normal);
    pointing_cos_t           := dot(plane_normal, ray_direction);
    result.hit_distance       = signed_distance_to_plane / pointing_cos_t;
    result.is_hit             = (result.hit_distance >= 0) & (pointing_cos_t != 0);
    result.hit_back_face      = signed_distance_to_plane > 0;
    result.hit_location       = ray_origin + ray_direction * result.hit_distance;
    return result.is_hit;
}

raycast_triangle :: inline (result: *Raycast_Result_Simple, ray_origin: Vector3, ray_direction: Vector3, a: Vector3, b: Vector3, c: Vector3, out_normal: *Vector3) -> bool {
    ab := b - a;
    ac := c - a;
    out_normal.* = normalize(cross(ac, ab));

    if raycast_plane(result, ray_origin, ray_direction, a, out_normal.*) {
        ac_scaled_normal := cross(out_normal.*, ac);
        cb_scaled_normal := cross(out_normal.*, b - c);
        ba_scaled_normal := cross(out_normal.*, -ab);
        ah := result.hit_location - a;
        bh := result.hit_location - b;
        // each triangle edge is on a line bisecting the plane. check the point is on the side the triangle is on.
        if dot(ac_scaled_normal, ah) < 0 || dot(cb_scaled_normal, bh) < 0 || dot(ba_scaled_normal, bh) < 0 { 
            result.* = {};
            return false;
        }
        return true;
    }
    return false;
}

raycast_circle :: inline (result: *Raycast_Result_Simple, ray_origin: Vector3, ray_direction: Vector3, center: Vector3, radius: float, plane_normal: Vector3) -> bool {
    if raycast_plane_simple(result, ray_origin, ray_direction, center, plane_normal) {
        if distance_squared(center, result.hit_location) > square(radius) {
            result.* = {};
            return false;
        }
        return true;
    }
    return false;
}

raycast_rectangle :: inline (result: *Raycast_Result_Simple, ray_origin: Vector3, ray_direction: Vector3, center: Vector3, half_width: float, half_length: float, width_direction: Vector3, length_direction: Vector3, plane_normal: Vector3) -> bool {
    if raycast_plane_simple(result, ray_origin, ray_direction, center, plane_normal) {
        toward_hit_diff := result.hit_location - center;
        width_dist := dot(width_direction, toward_hit_diff);
        if abs(width_dist) > half_width {
            result.* = {};
            return false;
        }
        length_dist := dot(length_direction, toward_hit_diff);
        if abs(length_dist) > half_length {
            result.* = {};
            return false;
        }
        return true;
    } 
    return false;
}

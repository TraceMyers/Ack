is_point_in_box_2d :: inline (a_x: s32, a_y: s32, b_xmin: s32, b_ymin: s32, b_xmax: s32, b_ymax: s32) -> bool {
    return a_x >= b_xmin && a_x <= b_xmax && a_y >= b_ymin && a_y <= b_ymax;
}

AABB :: struct {
    center: Vector3;
    extent: Vector3;
}

Box :: struct {
    center: Vector3;
    extent: Vector3;
    fore: Vector3;
    up: Vector3;
    right: Vector3;
#overlay(fore) axes: [3]Vector3 = ---;
}

Box_Point :: enum u8 {
    BOT_LOWER_LEFT;
    BOT_LOWER_RIGHT;
    BOT_UPPER_LEFT;
    BOT_UPPER_RIGHT;
    TOP_LOWER_LEFT;
    TOP_LOWER_RIGHT;
    TOP_UPPER_LEFT;
    TOP_UPPER_RIGHT;
}

Box_Edge :: struct {
    a: Box_Point;
    b: Box_Point;
}

Box_Edges :: Box_Edge.[
    .{.BOT_LOWER_LEFT,  .BOT_LOWER_RIGHT},
    .{.BOT_LOWER_LEFT,  .BOT_UPPER_LEFT},
    .{.BOT_UPPER_RIGHT, .BOT_LOWER_RIGHT},
    .{.BOT_UPPER_RIGHT, .BOT_UPPER_LEFT},
    .{.BOT_LOWER_LEFT,  .TOP_LOWER_LEFT},
    .{.BOT_LOWER_RIGHT, .TOP_LOWER_RIGHT},
    .{.BOT_UPPER_LEFT,  .TOP_UPPER_LEFT},
    .{.BOT_UPPER_RIGHT, .TOP_UPPER_RIGHT},
    .{.TOP_LOWER_LEFT,  .TOP_LOWER_RIGHT},
    .{.TOP_LOWER_LEFT,  .TOP_UPPER_LEFT},
    .{.TOP_UPPER_RIGHT, .TOP_LOWER_RIGHT},
    .{.TOP_UPPER_RIGHT, .TOP_UPPER_LEFT}
];

is_overlap_aabb_aabb :: inline (aabb_a: AABB, aabb_b: AABB) -> bool {
    abs_pos_diff := abs(aabb_a.center - aabb_b.center);
    return abs_pos_diff.x < aabb_a.extent.x + aabb_b.extent.x && abs_pos_diff.y < aabb_a.extent.y + aabb_b.extent.y && abs_pos_diff.z < aabb_a.extent.z + aabb_b.extent.z;
}

get_aabb_points :: (aabb: AABB, out_points: *[8]Vector3) {
    out_points.*[Box_Point.BOT_LOWER_LEFT]    = aabb.center - aabb.extent;
    out_points.*[Box_Point.BOT_LOWER_RIGHT]   = aabb.center + Vector3.{ aabb.extent.x, -aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.BOT_UPPER_LEFT]    = aabb.center + Vector3.{-aabb.extent.x,  aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.BOT_UPPER_RIGHT]   = aabb.center + Vector3.{ aabb.extent.x,  aabb.extent.y, -aabb.extent.z}; 
    out_points.*[Box_Point.TOP_LOWER_LEFT]    = aabb.center + Vector3.{-aabb.extent.x, -aabb.extent.y,  aabb.extent.z};
    out_points.*[Box_Point.TOP_LOWER_RIGHT]   = aabb.center + Vector3.{ aabb.extent.x, -aabb.extent.y,  aabb.extent.z}; 
    out_points.*[Box_Point.TOP_UPPER_LEFT]    = aabb.center + Vector3.{-aabb.extent.x,  aabb.extent.y,  aabb.extent.z};
    out_points.*[Box_Point.TOP_UPPER_RIGHT]   = aabb.center + aabb.extent;
} 

get_box_points :: inline (position: Vector3, length_vec: Vector3, height_vec: Vector3, width_vec: Vector3, out_points: *[8]Vector3) {
    out_points.*[Box_Point.BOT_LOWER_LEFT]     = position - length_vec - height_vec - width_vec;
    out_points.*[Box_Point.BOT_LOWER_RIGHT]    = position - length_vec - height_vec + width_vec;
    out_points.*[Box_Point.BOT_UPPER_LEFT]     = position + length_vec - height_vec - width_vec;
    out_points.*[Box_Point.BOT_UPPER_RIGHT]    = position + length_vec - height_vec + width_vec;
    out_points.*[Box_Point.TOP_LOWER_LEFT]     = position - length_vec + height_vec - width_vec;
    out_points.*[Box_Point.TOP_LOWER_RIGHT]    = position - length_vec + height_vec + width_vec;
    out_points.*[Box_Point.TOP_UPPER_LEFT]     = position + length_vec + height_vec - width_vec;
    out_points.*[Box_Point.TOP_UPPER_RIGHT]    = position + length_vec + height_vec + width_vec;
}

get_closest_point_in_aabb :: inline (position: Vector3, aabb: AABB) -> Vector3 {
    diff := position - aabb.center;
    return aabb.center + clamp(diff, aabb.extent);
}

get_closest_point_in_box :: inline (position: Vector3, box: Box) -> Vector3 {
    diff := position - box.center;
    dist_along_axes := Vector3.{dot(diff, box.right), dot(diff, box.fore), dot(diff, box.up)};
    return box.center + clamp(dist_along_axes, box.extent);
}

is_point_inside_box :: (point: Vector2, upper_left: Vector2, lower_right: Vector2) -> bool {
    return point.x >= upper_left.x && point.x <= lower_right.x
        && point.y >= upper_left.y && point.y <= lower_right.y;
}

is_point_inside_box :: (point: Vector2i, upper_left: Vector2i, lower_right: Vector2i) -> bool {
    return point.x >= upper_left.x && point.x <= lower_right.x
        && point.y >= upper_left.y && point.y <= lower_right.y;
}

// extent = (half width, half length, half height)
is_point_inside_box :: inline (point: Vector3, box_center: Vector3, box_extent: Vector3, box_width_direction: Vector3, box_length_direction: Vector3, box_height_direction: Vector3) -> bool {
    diff := point - box_center;

    width_dist  := abs(dot(diff, box_width_direction));
    length_dist := abs(dot(diff, box_length_direction));
    height_dist := abs(dot(diff, box_height_direction));

    return width_dist <= box_extent.x && length_dist <= box_extent.y && height_dist <= box_extent.x;
}

is_point_inside_cylinder :: inline (point: Vector3, cylinder_center: Vector3, cylinder_radius: float, cylinder_half_height: float, cylinder_height_direction: Vector3) -> bool {
    top_center := cylinder_center + cylinder_half_height * cylinder_height_direction;
    bot_center := cylinder_center - cylinder_half_height * cylinder_height_direction;

    radial_dist  := distance_from_line(point, top_center, bot_center);
    toward_point := point - cylinder_center;
    height_dist  := abs(dot(toward_point, cylinder_height_direction));

    return radial_dist <= cylinder_radius + SMALL_NUMBER && height_dist <= cylinder_half_height + SMALL_NUMBER;
}

// if an AABB were to move, what would the bounding box containing the previous and new AABB be?
sweep_aabb :: inline (aabb: AABB, displacement: Vector3) -> AABB {
    min := aabb.center - aabb.extent;
    max := aabb.center + aabb.extent;
    if displacement.x < 0 then min.x += displacement.x; else max.x += displacement.x;
    if displacement.y < 0 then min.y += displacement.y; else max.y += displacement.y;
    if displacement.z < 0 then min.z += displacement.z; else max.z += displacement.z;
    extent := (max - min) * 0.5;
    return .{min + extent, extent};
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

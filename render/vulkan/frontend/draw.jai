// immediate draws: things drawn for one frame only. call these any time before the renderer 
// updates. they're cleared after each rendered frame (except timed lines, which last until their 
// time runs out).

Frame_Draws :: struct {
    lines:       [..]Line_Draw;
    timed_lines: [..]Timed_Line_Draw;
}

Line_Draw :: struct {
    a:     Vector3;
    b:     Vector3;
    color: Color4b;
    width: float;
    layer: Draw_Layer;
}

Timed_Line_Draw :: struct {
    draw: Line_Draw;
    time_remaining: float;
}

// draw_in_front puts a debug draw in LAYER_1, so it draws over everything
in_front_layer :: inline (draw_in_front: bool) -> Draw_Layer {
    return ifx draw_in_front then .LAYER_1 else .GAME;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------------- lines

// lines whose color has alpha < 255 are blended
draw_line :: (begin: Vector3, end: Vector3, color: Color4b, width := 1.0, draw_in_front := false, time := 0.0) {
    using engine.renderer;
    render_check(!currently_updating_renderer, level=.HIGH);
    draw := Line_Draw.{begin, end, color, width, in_front_layer(draw_in_front)};
    if time > 0 {
        array_add(*draws.timed_lines, .{draw = draw, time_remaining = time});
    } else {
        array_add(*draws.lines, draw);
    }
}

draw_circle :: (center: Vector3, radius: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    render_check(segment_count >= 3);

    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_position := center + right * radius;

    for 1..segment_count {
        radians := (cast(float) it * inv_segment_count) * 2.0 * PI;
        sin_x, cos_x := sin_cos(radians);
        next_radius_position := center + right * (radius * cos_x) + up * (radius * sin_x);

        draw_line(radius_position, next_radius_position, color, line_width, draw_in_front, time);
        draw_line(center, next_radius_position, color, line_width, draw_in_front, time);

        radius_position = next_radius_position;
    }
}

draw_circle :: inline (center: Vector3, radius: float32, orientation: Quaternion, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    draw_circle(center, radius, get_up_direction(orientation), get_right_direction(orientation), color, line_width, segment_count, draw_in_front, time);
}

draw_triangle :: (a: Vector3, b: Vector3, c: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    draw_line(a, b, color, line_width, draw_in_front, time);
    draw_line(b, c, color, line_width, draw_in_front, time);
    draw_line(c, a, color, line_width, draw_in_front, time);
}

draw_rectangle :: (center: Vector3, half_width: float, half_height: float, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    ul := center + up * half_height - right * half_width;
    ur := center + up * half_height + right * half_width;
    ll := center - up * half_height - right * half_width;
    lr := center - up * half_height + right * half_width;
    draw_line(ul, ur, color, line_width, draw_in_front, time);
    draw_line(ur, lr, color, line_width, draw_in_front, time);
    draw_line(lr, ll, color, line_width, draw_in_front, time);
    draw_line(ll, ul, color, line_width, draw_in_front, time);
}

draw_box :: (center: Vector3, extent: Vector3, up: Vector3, right: Vector3, forward: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    top_center := center + up * extent.z;
    bot_center := center - up * extent.z;

    top_a := top_center + forward * extent.y - right * extent.x;
    top_b := top_center + forward * extent.y + right * extent.x;
    top_c := top_center - forward * extent.y - right * extent.x;
    top_d := top_center - forward * extent.y + right * extent.x;

    bot_a := bot_center + forward * extent.y - right * extent.x;
    bot_b := bot_center + forward * extent.y + right * extent.x;
    bot_c := bot_center - forward * extent.y - right * extent.x;
    bot_d := bot_center - forward * extent.y + right * extent.x;

    draw_line(top_a, top_b, color, line_width, draw_in_front, time);
    draw_line(top_b, top_d, color, line_width, draw_in_front, time);
    draw_line(top_d, top_c, color, line_width, draw_in_front, time);
    draw_line(top_c, top_a, color, line_width, draw_in_front, time);

    draw_line(bot_a, bot_b, color, line_width, draw_in_front, time);
    draw_line(bot_b, bot_d, color, line_width, draw_in_front, time);
    draw_line(bot_d, bot_c, color, line_width, draw_in_front, time);
    draw_line(bot_c, bot_a, color, line_width, draw_in_front, time);

    draw_line(top_a, bot_a, color, line_width, draw_in_front, time);
    draw_line(top_b, bot_b, color, line_width, draw_in_front, time);
    draw_line(top_c, bot_c, color, line_width, draw_in_front, time);
    draw_line(top_d, bot_d, color, line_width, draw_in_front, time);
}

// draw_portion < 1 means only draw that portion of the cylinder.
draw_cylinder :: (center: Vector3, radius: float32, height: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0, draw_portion := 1.0) {
    render_check(segment_count >= 3);
    render_check(draw_portion >= 0 && draw_portion <= 1);

    fore := cross(up, right);

    half_height := height * 0.5;
    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_position := center + right * radius;

    up_offset := up * half_height;
    up_center   := center + up_offset;
    down_center := center - up_offset;

    for 1..segment_count {
        radians := (cast(float) it * inv_segment_count) * (2.0 * PI * draw_portion);
        sin_x, cos_x := sin_cos(radians);
        next_radius_position := center + right * (radius * cos_x) + fore * (radius * sin_x);

        up_radius_position        := radius_position + up_offset;
        up_next_radius_position   := next_radius_position + up_offset;
        down_radius_position      := radius_position - up_offset;
        down_next_radius_position := next_radius_position - up_offset;

        // top circle
        draw_line(up_radius_position, up_next_radius_position, color, line_width, draw_in_front, time);
        draw_line(up_center, up_next_radius_position, color, line_width, draw_in_front, time);

        // bottom circle
        draw_line(down_radius_position, down_next_radius_position, color, line_width, draw_in_front, time);
        draw_line(down_center, down_next_radius_position, color, line_width, draw_in_front, time);

        // side
        draw_line(up_radius_position, down_radius_position, color, line_width, draw_in_front, time);

        radius_position = next_radius_position;
    }
}

draw_cylinder :: inline (center: Vector3, radius: float32, height: float32, orientation: Quaternion, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    draw_cylinder(center, radius, height, get_up_direction(orientation), get_right_direction(orientation), color, line_width, segment_count, draw_in_front, time);
}

draw_sphere :: (center: Vector3, radius: float32, color: Color4b, line_width := 1.0, segment_count := 12, draw_in_front := false, time := 0.0) {
    draw_capsule(center, radius, 0, {z=1}, {x=1}, color, line_width, segment_count, draw_in_front, time);
}

draw_capsule :: (center: Vector3, radius: float32, half_height: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 8, draw_in_front := false, time := 0.0, draw_portion := 1.0) {
    MAX_SEGMENTS :: 64;
    render_check(segment_count >= 3 && segment_count <= MAX_SEGMENTS);
    render_check(draw_portion >= 0 && draw_portion <= 1);

    fore := cross(up, right);

    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_direction := right;
    radius_position := center + radius_direction * radius;

    up_offset := up * max((half_height - radius), 0);

    MAX_VERTICAL_SEGMENT_COUNT :: #run div_ceil(MAX_SEGMENTS, 2) + 1;
    vertical_segment_count := div_ceil(segment_count, 2)+1;
    vertical_segment_cos_values := make_local_static_array(float, MAX_VERTICAL_SEGMENT_COUNT, vertical_segment_count, id="0");
    vertical_segment_sin_values := make_local_static_array(float, MAX_VERTICAL_SEGMENT_COUNT, vertical_segment_count, id="1");

    for < 1..vertical_segment_cos_values.count {
        norm_angle := cast(float) it / vertical_segment_count;
        vertical_segment_sin_values[it-1], vertical_segment_cos_values[it-1] = sin_cos(norm_angle * PI * 0.5);
        vertical_segment_sin_values[it-1] *= radius;
        vertical_segment_cos_values[it-1] *= radius;
    }

    for 1..segment_count+1 {
        radians := (cast(float) it * inv_segment_count) * (2.0 * PI * draw_portion);
        sin_x, cos_x := sin_cos(radians);
        next_radius_direction := right * cos_x + fore * sin_x;
        next_radius_position  := center + next_radius_direction * radius;

        if half_height - radius > 0 {
            up_radius_position        := radius_position + up_offset;
            up_next_radius_position   := next_radius_position + up_offset;
            down_radius_position      := radius_position - up_offset;
            down_next_radius_position := next_radius_position - up_offset;
            // top circle
            draw_line(up_radius_position, up_next_radius_position, color, line_width, draw_in_front, time);
            // bottom circle
            draw_line(down_radius_position, down_next_radius_position, color, line_width, draw_in_front, time);
            // side
            draw_line(up_radius_position, down_radius_position, color, line_width, draw_in_front, time);
        } else {
            // draw the belt of the sphere
            draw_line(radius_position, next_radius_position, color, line_width, draw_in_front, time);
        }

        vertical_position_up   := center + radius_direction * radius + up_offset;
        vertical_position_down := center + radius_direction * radius - up_offset;

        for 0..vertical_segment_cos_values.count-1 {
            sin_factor := vertical_segment_sin_values[it];
            cos_factor := vertical_segment_cos_values[it];

            next_vertical_position_up := center + radius_direction * cos_factor + up * sin_factor + up_offset;
            next_ring_position_up     := center + next_radius_direction * cos_factor + up * sin_factor + up_offset;

            next_vertical_position_down := center + radius_direction * cos_factor - up * sin_factor - up_offset;
            next_ring_position_down     := center + next_radius_direction * cos_factor - up * sin_factor - up_offset;

            draw_line(vertical_position_up, next_vertical_position_up, color, line_width, draw_in_front, time);
            draw_line(next_vertical_position_up, next_ring_position_up, color, line_width, draw_in_front, time);

            draw_line(vertical_position_down, next_vertical_position_down, color, line_width, draw_in_front, time);
            draw_line(next_vertical_position_down, next_ring_position_down, color, line_width, draw_in_front, time);

            vertical_position_up = next_vertical_position_up;
            vertical_position_down = next_vertical_position_down;
        }

        radius_direction = next_radius_direction;
        radius_position  = next_radius_position;
    }
}

draw_raycast :: (result: Raycast_Result, origin_color := COLOR4F_MAGENTA, miss_ray_color := COLOR4F_BLUE, hit_ray_color := COLOR4F_RED, hit_marker_radius := 0.02, line_width := 4.0, draw_in_front := false, time := 10.0) {
    ray_normal: Vector3;

    if is_normalized(result.hit_normal) {
        ray_normal = result.hit_normal;
    } else {
        ray_normal = normalize(result.ray_destination - result.ray_origin);
    }

    ray_right, ray_up: Vector3;
    if abs(ray_normal.z) > 0.95 {
        ray_right = cross(ray_normal, Vector3.{x=1});
    } else {
        ray_right = cross(ray_normal, Vector3.{z=1});
    }
    ray_up = cross(ray_normal, ray_right);

    origin_radius := hit_marker_radius * 0.5;
    draw_circle(result.ray_origin, origin_radius, ray_up, ray_right, to_color4b(origin_color), line_width, 4, draw_in_front, time);

    if result.is_hit {
        draw_line(result.ray_origin, result.hit_location, to_color4b(hit_ray_color), line_width, draw_in_front, time);
        draw_circle(result.hit_location, hit_marker_radius, ray_up, ray_right, to_color4b(hit_ray_color), line_width, 4, draw_in_front, time);
    } else {
        draw_line(result.ray_origin, result.ray_destination, to_color4b(miss_ray_color), line_width, draw_in_front, time);
    }
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------- particles

Particle_Draw :: struct {
    position: Vector3;
    color: Color4b = #run to_color4b(COLOR4F_WHITE);
    scale: float = 1.0;
    texture_index: s32 = -1;
    layer: Draw_Layer;
}

// todo: billboards aren't ported to the new renderer yet. this draws nothing.
draw_particle :: (draw: Particle_Draw) {
}

// -----------------------------------------------------------------------------------

// called after each rendered frame
reset_frame_draws :: () {
    using engine.renderer;
    array_reset_keeping_memory(*draws.lines);
    for *draws.timed_lines {
        it.time_remaining -= unscaled_delta_time;
        if it.time_remaining <= 0 {
            remove it;
        }
    }
}

draw_particle :: (renderer: *Renderer, draw: Particle_Draw) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    billboard_instance := array_add(*renderer.particle_draws);
    billboard_instance.position      = draw.position;
    billboard_instance.scale         = {draw.scale, draw.scale};
    billboard_instance.uv_offset     = {0,0};
    billboard_instance.uv_scale      = {1,1};
    billboard_instance.tint          = to_color4f(draw.color);
    billboard_instance.texture_index = xx draw.texture_index;
    billboard_instance.layer         = draw.layer;
}

draw_static_mesh :: (renderer: *Renderer, draw: Static_Mesh_Draw) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    mesh := get_mesh(draw.ref);
    render_check(.LOW, is_static_mesh(mesh));
    array_add(*renderer.static_mesh_draws, draw);
    renderer.last_mesh_draw_was_static = true;
}

draw_static_mesh :: (renderer: *Renderer, ref: Mesh_Ref, position: Vector3, scale := 1.0, orientation := Quaternion.{}, layer := Draw_Layer.GAME) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    mesh := get_mesh(ref);
    render_check(.LOW, is_static_mesh(mesh));
    array_add(*renderer.static_mesh_draws, {ref, position, orientation, {scale,scale,scale}, layer, -1});
    renderer.last_mesh_draw_was_static = true;
}

draw_static_mesh :: (renderer: *Renderer, ref: Mesh_Ref, position: Vector3, scale := Vector3.{1, 1, 1}, orientation := Quaternion.{}, layer := Draw_Layer.GAME) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    mesh := get_mesh(ref);
    render_check(.LOW, is_static_mesh(mesh));
    array_add(*renderer.static_mesh_draws, {ref, position, orientation, scale, layer, -1});
    renderer.last_mesh_draw_was_static = true;
}

draw_skinned_mesh :: (renderer: *Renderer, draw: Skinned_Mesh_Draw) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    mesh := get_mesh(ref);
    render_check(.LOW, !is_static_mesh(mesh));
    add_skinning_joints(renderer, *draw);
    array_add(*renderer.skinned_mesh_draws, draw);
    renderer.last_mesh_draw_was_static = false;
}

draw_skinned_mesh :: (renderer: *Renderer, ref: Mesh_Ref, position: Vector3, pose: *Skeletal_Pose = null, scale := Vector3.{1,1,1}, orientation := Quaternion.{}, layer := Draw_Layer.GAME) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    mesh := get_mesh(ref);
    render_check(.LOW, !is_static_mesh(mesh));
    new_draw := array_add(*renderer.skinned_mesh_draws);
    new_draw.* = {static_draw={ref, position, orientation, scale, layer, -1}, joint_data._interface.pose=pose};
    add_skinning_joints(renderer, new_draw);
    renderer.last_mesh_draw_was_static = false;
}

deduce_specialization_type :: (name: string) -> Type {
    tinfo := cast(*Type_Info_Struct) type_info(Mesh_Specialization_Params);
    for member : tinfo.members {
        if member.name == "flags" then continue;
        if member.name == name {
            return (cast(*Type) *member.type).*;
        }
    }
    return void;
}

add_draw_specialization :: (renderer: *Renderer, $name: string, specialization: $T)
#modify {
    T = deduce_specialization_type(name);
    return T != void;
} {
    draw   := add_specialization_to_last_draw_if_needed(renderer);
    params := *renderer.mesh_draw_specializations[draw.specialization];
    add_draw_specialization_to_params(params, name, specialization);
}

add_draw_specialization_to_params :: (params: *Mesh_Specialization_Params, $name: string, specialization: $T) {
    #insert #run tprint("params.% = specialization;\n", name);
    #insert #run tprint("params.flags |= .%;\n", to_upper(name));
}

add_flagged_draw_specializations :: (renderer: *Renderer, params: *Mesh_Specialization_Params) {
    #insert -> string {
        builder: String_Builder;
        tinfo := cast(*Type_Info_Struct) type_info(Mesh_Specialization_Params);
        for member : tinfo.members {
            if member.name == "flags" {
                continue;
            }
            print(*builder, "\tif params.flags & .% { ", to_upper(member.name));
            print(*builder, "add_draw_specialization(renderer, \"%\", params.%); }\n", member.name, member.name);
        }
        return builder_to_string(*builder);
    }
}

// todo: make lines use layer system. halves number of draw paths
draw_line :: inline (renderer: *Renderer, begin: Vector3, end: Vector3, color: Color4b, width := 1.0, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    draw := Line_Draw.{begin, end, color, width};
    if draw_in_front {
        if color.a < 255 {
            array_add(*renderer.transparent_in_front_line_draws, draw);
            render_check(.LOW, time == 0, "don't support timed transparent line draws yet");
        } else {
            array_add(*renderer.in_front_line_draws, draw);
            if time > 0 {
                array_add(*renderer.timed_in_front_line_draws, {draw=draw, time_remaining=time});
            }
        }
    } else {
        array_add(*renderer.line_draws, draw);
        if time > 0 {
            array_add(*renderer.timed_line_draws, {draw=draw, time_remaining=time});
        }
    }
}

draw_circle :: (renderer: *Renderer, center: Vector3, radius: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    render_check(.LOW, segment_count >= 3);

    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_position := center + right * radius;
    next_radius_position: Vector3;

    for 1..segment_count {
        radians := (cast(float) it * inv_segment_count) * 2.0 * PI; 
        sin_x, cos_x := sin_cos(radians);
        next_radius_position := center + right * (radius * cos_x) + up * (radius * sin_x);

        draw_line(renderer, radius_position, next_radius_position, color, line_width, draw_in_front, time);
        draw_line(renderer, center, next_radius_position, color, line_width, draw_in_front, time);

        radius_position = next_radius_position;
    }
}

draw_circle :: inline (renderer: *Renderer, center: Vector3, radius: float32, orientation: Quaternion, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    up    := get_up_direction(*orientation);
    right := get_right_direction(*orientation);
    draw_circle(renderer, center, radius, up, right, color, line_width, segment_count, draw_in_front, time);
}

draw_triangle :: (renderer: *Renderer, a: Vector3, b: Vector3, c: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    draw_line(renderer, a, b, color, line_width, draw_in_front, time);
    draw_line(renderer, b, c, color, line_width, draw_in_front, time);
    draw_line(renderer, c, a, color, line_width, draw_in_front, time);
}

draw_rectangle :: (renderer: *Renderer, center: Vector3, half_width: float, half_height: float, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    ul := center + up * half_height - right * half_width;
    ur := center + up * half_height + right * half_width;
    ll := center - up * half_height - right * half_width;
    lr := center - up * half_height + right * half_width;
    draw_line(renderer, ul, ur, color, line_width, draw_in_front, time);
    draw_line(renderer, ur, lr, color, line_width, draw_in_front, time);
    draw_line(renderer, lr, ll, color, line_width, draw_in_front, time);
    draw_line(renderer, ll, ul, color, line_width, draw_in_front, time);
}

draw_box :: (renderer: *Renderer, center: Vector3, extent: Vector3, up: Vector3, right: Vector3, forward: Vector3, color: Color4b, line_width := 1.0, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
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

    draw_line(renderer, top_a, top_b, color, line_width, draw_in_front, time);
    draw_line(renderer, top_b, top_d, color, line_width, draw_in_front, time);
    draw_line(renderer, top_d, top_c, color, line_width, draw_in_front, time);
    draw_line(renderer, top_c, top_a, color, line_width, draw_in_front, time);

    draw_line(renderer, bot_a, bot_b, color, line_width, draw_in_front, time);
    draw_line(renderer, bot_b, bot_d, color, line_width, draw_in_front, time);
    draw_line(renderer, bot_d, bot_c, color, line_width, draw_in_front, time);
    draw_line(renderer, bot_c, bot_a, color, line_width, draw_in_front, time);

    draw_line(renderer, top_a, bot_a, color, line_width, draw_in_front, time);
    draw_line(renderer, top_b, bot_b, color, line_width, draw_in_front, time);
    draw_line(renderer, top_c, bot_c, color, line_width, draw_in_front, time);
    draw_line(renderer, top_d, bot_d, color, line_width, draw_in_front, time);
}

// draw_portion < 1 means only draw that portion of the cylinder.
draw_cylinder :: (renderer: *Renderer, center: Vector3, radius: float32, height: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0, draw_portion := 1.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    render_check(.LOW, segment_count >= 3);
    render_check(.LOW, draw_portion >= 0 && draw_portion <= 1);

    fore := cross(up, right);

    half_height := height * 0.5;
    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_position := center + right * radius;
    next_radius_position: Vector3;

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
        draw_line(renderer, up_radius_position, up_next_radius_position, color, line_width, draw_in_front, time);
        draw_line(renderer, up_center, up_next_radius_position, color, line_width, draw_in_front, time);

        // bottom circle
        draw_line(renderer, down_radius_position, down_next_radius_position, color, line_width, draw_in_front, time);
        draw_line(renderer, down_center, down_next_radius_position, color, line_width, draw_in_front, time);

        // side
        draw_line(renderer, up_radius_position, down_radius_position, color, line_width, draw_in_front, time);

        radius_position = next_radius_position;
    }
}

draw_cylinder :: inline (renderer: *Renderer, center: Vector3, radius: float32, height: float32, orientation: Quaternion, color: Color4b, line_width := 1.0, segment_count := 16, draw_in_front := false, time := 0.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    up    := get_up_direction(*orientation);
    right := get_right_direction(*orientation);
    draw_cylinder(renderer, center, radius, height, up, right, color, line_width, segment_count, draw_in_front, time);
}

draw_sphere :: (renderer: *Renderer, center: Vector3, radius: float32, color: Color4b, line_width := 1.0, segment_count := 12, draw_in_front := false, time := 0.0) {
    draw_capsule(renderer, center, radius, 0, {z=1}, {x=1}, color, line_width, segment_count, draw_in_front, time);
}

draw_capsule :: (renderer: *Renderer, center: Vector3, radius: float32, half_height: float32, up: Vector3, right: Vector3, color: Color4b, line_width := 1.0, segment_count := 8, draw_in_front := false, time := 0.0, draw_portion := 1.0) {
    MAX_SEGMENTS :: 64;
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
    render_check(.LOW, segment_count >= 3 && segment_count <= MAX_SEGMENTS);
    render_check(.LOW, draw_portion >= 0 && draw_portion <= 1);

    fore := cross(up, right);

    inv_segment_count := 1.0 / cast(float) segment_count;
    radius_direction := right;
    radius_position := center + radius_direction * radius;

    up_offset := up * max((half_height - radius), 0);
    up_center   := center + up_offset;
    down_center := center - up_offset;

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
        next_radius_position  := center + radius_direction * radius;

        if half_height - radius > 0 {
            up_radius_position        := radius_position + up_offset;
            up_next_radius_position   := next_radius_position + up_offset;
            down_radius_position      := radius_position - up_offset;
            down_next_radius_position := next_radius_position - up_offset;
            // top circle
            draw_line(renderer, up_radius_position, up_next_radius_position, color, line_width, draw_in_front, time);
            // bottom circle
            draw_line(renderer, down_radius_position, down_next_radius_position, color, line_width, draw_in_front, time);
            // side
            draw_line(renderer, up_radius_position, down_radius_position, color, line_width, draw_in_front, time);
        } else {
            // draw the belt of the sphere
            draw_line(renderer, radius_position, next_radius_position, color, line_width, draw_in_front, time);
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

            draw_line(renderer, vertical_position_up, next_vertical_position_up, color, line_width, draw_in_front, time);
            draw_line(renderer, next_vertical_position_up, next_ring_position_up, color, line_width, draw_in_front, time);

            draw_line(renderer, vertical_position_down, next_vertical_position_down, color, line_width, draw_in_front, time);
            draw_line(renderer, next_vertical_position_down, next_ring_position_down, color, line_width, draw_in_front, time);

            vertical_position_up = next_vertical_position_up;
            vertical_position_down = next_vertical_position_down;
        }

        radius_direction = next_radius_direction;
        radius_position  = next_radius_position;
    }
}

draw_raycast :: (renderer: *Renderer, result: Raycast_Result, origin_color := COLOR4F_MAGENTA, miss_ray_color := COLOR4F_BLUE, hit_ray_color := COLOR4F_RED, hit_marker_radius := 0.02, line_width := 4.0, draw_in_front := false, time := 10.0) {
    render_check(.HIGH, !renderer.in_the_middle_of_rendering);
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
    draw_circle(renderer, result.ray_origin, origin_radius, ray_up, ray_right, to_color4b(origin_color), line_width, 4, draw_in_front, time);

    if result.is_hit {
        draw_line(renderer, result.ray_origin, result.hit_location, to_color4b(hit_ray_color), line_width, draw_in_front, time);
        draw_circle(renderer, result.hit_location, hit_marker_radius, ray_up, ray_right, to_color4b(hit_ray_color), line_width, 4, draw_in_front, time);
    } else {
        draw_line(renderer, result.ray_origin, result.ray_destination, to_color4b(miss_ray_color), line_width, draw_in_front, time);
    }
}

#scope_file

add_specialization_to_last_draw_if_needed :: (renderer: *Renderer) -> *Static_Mesh_Draw {
    draw: *Static_Mesh_Draw;
    if renderer.last_mesh_draw_was_static {
        draw = *renderer.static_mesh_draws[renderer.static_mesh_draws.count-1];
    } else {
        last_draw := *renderer.skinned_mesh_draws[renderer.skinned_mesh_draws.count-1];
        draw = *last_draw.static_draw;
    }
    if draw.specialization == -1 {
        array_add(*renderer.mesh_draw_specializations, {});
        draw.specialization = xx (renderer.mesh_draw_specializations.count - 1);
    }
    return draw;
}

add_skinning_joints :: (renderer: *Renderer, draw: *Skinned_Mesh_Draw) {
    render_check(.LOW, draw.pose != null);
    joint_offset := renderer.skinning_joints.count;
    array_append(*renderer.skinning_joints, draw.pose.skinning_joints);
    draw.pose = null;
    draw.joint_offset = xx joint_offset;
}

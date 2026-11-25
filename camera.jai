// basis is y forward, x right, z up

Camera_Projection :: enum {
    PERSPECTIVE;
    ORTHOGRAPHIC;
}

// fundamental non-spatial parameters of a 3d camera
Camera_Basic :: struct {
    projection := Camera_Projection.PERSPECTIVE;
    orthographic_scale := 1.0;
    perspective_vertical_fov := 80.0; // degrees
    aspect_ratio := 0.0; // 0 for default
    near_plane := 0.05;
    far_plane  := 10_000.0;
}

// camera component that can be attached to an entity for higher-level features
Camera :: struct {
    using #as base: Spatial_Component;
    using basic: Camera_Basic;

    rotation_axis: Vector3;
    rotation_speed: float32;
    rotation_speed_target: float32;

    // radians per second per unit input.
    rotation_acceleration := 1.5;
    look_up_degree_limit := 85.0;
}

Camera_Aspect_Ratio :: enum { X_OVER_Y; Y_OVER_X; }

// procedures have a Camera_Basic proc version and *Camera (entity component) proc version,
// depending on if you need more or less controls

// --- *Camera ---

get_camera_aspect_ratio :: inline (camera: *Camera, which_ratio := Camera_Aspect_Ratio.X_OVER_Y) -> float {
    return get_camera_aspect_ratio(camera.basic, get_viewport(), which_ratio);
}

get_camera_perspective_horizontal_fov :: inline (camera: *Camera) -> float {
    return get_camera_perspective_horizontal_fov(camera.basic, get_viewport());
}

make_camera_view_matrix :: inline (camera: *Camera) -> Matrix4 {
    return make_camera_view_matrix(camera.position, camera.orientation);
}

make_camera_projection_matrix :: (camera: *Camera) -> Matrix4 {
    return make_camera_projection_matrix(camera.basic, get_viewport());
}

transform_to_clip_coordinates :: inline (camera: *Camera, point: Vector3) -> Vector4 {
    return transform_to_clip_coordinates(camera.basic, camera.position, camera.orientation, get_viewport(), point);
}

get_camera_ray_passing_through_mouse_cursor :: inline (camera: *Camera) -> origin: Vector3, direction: Vector3, success: bool {
    return get_camera_ray_passing_through_mouse_cursor(camera.basic, camera.position, camera.orientation, get_viewport(), window);
}

get_camera_ray_passing_through_window_position :: inline (camera: *Camera, window_pos: Vector2) -> origin: Vector3, direction: Vector3 {
    return get_camera_ray_passing_through_window_position(camera.basic, camera.position, camera.orientation, get_viewport(), window_pos);
}

get_window_position_from_camera_ray :: inline (camera: *Camera, ray: Vector3) -> window_pos: Vector2 {
    return get_window_position_from_camera_ray(camera.basic, camera.position, camera.orientation, get_viewport(), ray);
}

// --- Camera_Basic ---

get_camera_aspect_ratio :: (using camera: Camera_Basic, viewport: Vector2, which_ratio := Camera_Aspect_Ratio.X_OVER_Y) -> float {
    if which_ratio == .X_OVER_Y {
        engine_check(viewport.y > 0);
        return ifx aspect_ratio == 0.0 then viewport.x / viewport.y else aspect_ratio;
    } else {
        engine_check(viewport.x > 0);
        return ifx aspect_ratio == 0.0 then viewport.y / viewport.x else 1.0 / aspect_ratio;
    }
}

get_camera_perspective_horizontal_fov :: (using camera: Camera_Basic, viewport: Vector2) -> float {
    d := tan(camera.perspective_vertical_fov * 0.5 * (PI / 180.0));
    aspect := get_camera_aspect_ratio(camera, viewport);
    return 2 * atan(aspect * d) * (180.0 / PI);
}

make_camera_view_matrix :: (camera_center: Vector3, camera_orientation: Quaternion) -> Matrix4 {
    q     := normalize(camera_orientation);
    up    := get_up_direction(q); 
    fore  := get_fore_direction(q);
    right := get_right_direction(q);

    view: Matrix4 = ---;
    view.v[0] = .{right.x,   right.y,  right.z, -dot(right, camera_center)};
    // flipping due to y-down normalized device coords
    view.v[1] = .{-up.x,    -up.y,    -up.z,     dot(up,    camera_center)};
    view.v[2] = .{fore.x,    fore.y,   fore.z,  -dot(fore,  camera_center)};
    view.v[3] = .{0,         0,        0,        1};

    return view;
}

// 
make_camera_projection_matrix :: (using camera: Camera_Basic, viewport: Vector2, z_min := 0.0, z_max := 1.0) -> Matrix4 {
    aspect := get_camera_aspect_ratio(camera, viewport);
    inv_plane_to_plane := 1 / (far_plane - near_plane);
    half_vertical_angle_radians := PI / 180 * perspective_vertical_fov * 0.5;

    if #complete camera.projection == {
    case .PERSPECTIVE;
        inv_far_plane_half_height := 1 / tan(half_vertical_angle_radians);
        inv_far_plane_half_width := inv_far_plane_half_height / aspect;

        // I solved this with some intuitive thinking and I have never been very good at finding solutions like this,
        // so I feel pretty proud of myself :).
        // (-x1 * z * n + x2 + x3 * fn) / (f - n) + x4 -> (zmin, zmax)
        // found with x1 = x3 = a, x2 = 0 and x4 = zmin * f...
        // a * (-n^2 + fn) / (f - n) + b = zmax * n, to get the near clip
        // a * (-fn  + fn) / (f - n) + b = zmin * f, to get the far clip
        // a ('z_factor') is then = (zmax * n - zmin * f) / n
        z_factor := (z_max * near_plane - z_min * far_plane) / near_plane;
        z_far_plane_offset := z_min * far_plane;

        perspective := Matrix4.{
            // scale camera relative horizontal dist by the far plane half width
            _11 = inv_far_plane_half_width,
            // scale camera relative vertical dist by the far plane half height
            _22 = inv_far_plane_half_height,
            // normalized depth (1=near, 0=far) = fore dist * (-near / near far dist) ...
            _33 = z_factor * -near_plane * inv_plane_to_plane,
            // ... + near * far dist / near far dist
            _34 = z_far_plane_offset + z_factor * near_plane * far_plane * inv_plane_to_plane,
            // w = z, for ndc normalization using the depth coord I think
            _43 = 1,
            _44 = 0
        };

        return perspective;
    case .ORTHOGRAPHIC;
        half_width := orthographic_scale * aspect;
        half_height := orthographic_scale;

        // todo: z_min and z_max for orthographic
        orthographic := Matrix4.{
            // scale
            _11 = 1 / half_width,
            _22 = 1 / half_height,
            _33 = -inv_plane_to_plane,
            _34 = far_plane * inv_plane_to_plane, 
            _44 = 1
        };

        return orthographic;
    }
}

// breaking projection into steps and putting it on cpu for debug
transform_to_clip_coordinates :: (using camera: Camera_Basic, camera_center: Vector3, camera_orientation: Quaternion, viewport: Vector2, point: Vector3) -> Vector4 {
    view_mat := make_camera_view_matrix(camera_center, camera_orientation);
    projection_mat := make_camera_projection_matrix(camera, viewport);
    view_coords := view_mat * Vector4.{xyz=point,w=1};
    clip_coords := projection_mat * view_coords;
    return clip_coords;
}

// returns the ray passing through the camera's near plane at the location of the 
// mouse cursor. origin is camera center if projection is perspective. if orthographic, the origin
// is the point on the camera plane at the mouse cursor location.
get_camera_ray_passing_through_mouse_cursor :: (using camera: Camera_Basic, camera_center: Vector3, camera_orientation: Quaternion, viewport: Vector2) -> origin: Vector3, direction: Vector3, success: bool {
    cursor_pos_x, cursor_pos_y := get_mouse_cursor_position(true);
    if success {
        origin, direction := get_camera_ray_passing_through_window_position(camera, camera_center, camera_orientation, viewport, {xx cursor_pos_x, xx cursor_pos_y});
        return origin, direction, true;
    } else {
        return {}, {}, false;
    }
}

// returns the ray passing through the camera's near plane at the given window position.
// origin is camera center if projection is perspective. if orthographic, the origin
// is the point on the camera plane at the given window position.
get_camera_ray_passing_through_window_position :: (using camera: Camera_Basic, camera_center: Vector3, camera_orientation: Quaternion, viewport: Vector2, window_pos: Vector2) -> origin: Vector3, direction: Vector3 {
    engine_check(viewport.x > 0);
    engine_check(viewport.y > 0);
    engine_check(is_normalized(camera_orientation), level=.HIGH);

    norm_position := window_pos / viewport;
    norm_clip_rect_center := Vector2.{0.5,0.5};
    norm_center_diff := norm_position - norm_clip_rect_center;

    camera_axis_fore := rotate(WORLD_AXIS_FORE, camera_orientation);
    camera_axis_right := rotate(WORLD_AXIS_RIGHT, camera_orientation);
    camera_axis_up := normalize(cross(camera_axis_right, camera_axis_fore));

    if camera.projection == .PERSPECTIVE {
        theta := (perspective_vertical_fov * 0.5) * (PI / 180.0);
        half_y_dist := near_plane * tan(theta); // tan(theta) = opp / adj
        clip_rect_height := half_y_dist * 2.0;
        clip_rect_width := get_camera_aspect_ratio(camera, viewport) * clip_rect_height;

        world_clip_rect_diff := norm_center_diff * Vector2.{clip_rect_width, -clip_rect_height};

        world_clip_rect_center := camera_center + camera_axis_fore * near_plane;
        world_clip_rect_cursor_pos := world_clip_rect_center + world_clip_rect_diff.x * camera_axis_right + world_clip_rect_diff.y * camera_axis_up;
        ray_direction := normalize(world_clip_rect_cursor_pos - camera_center);

        return camera_center, ray_direction;
    } else {
        aspect := get_camera_aspect_ratio(camera, viewport);
        half_width := orthographic_scale * aspect;
        half_height := orthographic_scale;

        world_clip_rect_diff := norm_center_diff * Vector2.{2*half_width, -2*half_height};

        origin := camera_center + world_clip_rect_diff.x * camera_axis_right + world_clip_rect_diff.y * camera_axis_up;
        return origin, camera_axis_fore;
    }
}

// ray doesn't have to be normalized (?)
get_window_position_from_camera_ray :: (using camera: Camera_Basic, camera_center: Vector3, camera_orientation: Quaternion, viewport: Vector2, ray: Vector3) -> window_pos: Vector2 {
    engine_check(is_normalized(camera_orientation), level=.HIGH);

    camera_axis_fore  := rotate(WORLD_AXIS_FORE, camera_orientation);
    camera_axis_right := rotate(WORLD_AXIS_RIGHT, camera_orientation);
    camera_axis_up    := normalize(cross(camera_axis_right, camera_axis_fore));

    if camera.projection == .PERSPECTIVE {
        hz_projection := project_point_onto_plane(camera_center + ray, camera_center, camera_axis_up); 
        vt_projection := project_point_onto_plane(camera_center + ray, camera_center, camera_axis_right); 

        toward_hz_projection := normalize(hz_projection - camera_center);
        toward_vt_projection := normalize(vt_projection - camera_center);

        x_sign := ifx dot(toward_hz_projection, camera_axis_right) > 0 then  1.0 else -1.0;
        y_sign := ifx dot(toward_vt_projection, camera_axis_up)    > 0 then -1.0 else  1.0;

        // todo : prob don't have to acos twice and tan twice...
        hz_theta := acos(dot(toward_hz_projection, camera_axis_fore));
        vt_theta := acos(dot(toward_vt_projection, camera_axis_fore));
        w := near_plane * tan(hz_theta) * x_sign; 
        h := near_plane * tan(vt_theta) * y_sign;

        theta := (perspective_vertical_fov * 0.5) * (PI / 180.0);
        clip_rect_half_height := near_plane * tan(theta); // tan(theta) = opp / adj
        clip_rect_half_width := get_camera_aspect_ratio(camera, viewport) * clip_rect_half_height;

        x_norm_pos := (w + clip_rect_half_width)  / (2 * clip_rect_half_width);
        y_norm_pos := (h + clip_rect_half_height) / (2 * clip_rect_half_height);

        return Vector2.{x_norm_pos, y_norm_pos} * viewport;
    } else {
        right_dist := dot(ray, camera_axis_right);
        up_dist    := dot(ray, camera_axis_up);

        aspect := get_camera_aspect_ratio(camera, viewport);
        half_width := orthographic_scale * aspect;
        half_height := orthographic_scale;

        norm_x := (half_width + right_dist) / (2 * half_width);
        norm_y := (half_height - up_dist) / (2 * half_height);

        viewport_pos := viewport * Vector2.{norm_x, norm_y};

        return viewport_pos;
    }
}

#scope_module

WORLD_AXIS_FORE  :: Vector3.{0, 1, 0};
WORLD_AXIS_RIGHT :: Vector3.{1, 0, 0};

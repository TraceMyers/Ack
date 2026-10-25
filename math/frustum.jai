View_Frustum :: struct {
    Plane :: enum {
        NEAR;
        TOP;
        BOTTOM;
        LEFT;
        RIGHT;
    }
    planes: [5]Vector4;
    far_plane: float;
}

get_plane :: (frustum: *View_Frustum, plane: View_Frustum.Plane) -> *Vector4 {
    return *frustum.planes[plane];
}

make_view_frustum :: (camera: Camera_Info, camera_center: Vector3, camera_orientation: Quaternion, viewport: Vector2) -> View_Frustum {
    engine_check(is_normalized(camera_orientation), level=.HIGH);

    camera_axis_fore  := rotate(WORLD_AXIS_FORE, camera_orientation);
    camera_axis_right := rotate(WORLD_AXIS_RIGHT, camera_orientation);
    camera_axis_up    := normalize(cross(camera_axis_right, camera_axis_fore));   

    frustum := View_Frustum.{far_plane=camera.far_plane - camera.near_plane};

    // for each plane, get the normal & a point, then project the origin onto it to get w
    near_plane := get_plane(*frustum, .NEAR);

    near_plane.xyz    = camera_axis_fore;
    near_plane_point := camera_center + camera_axis_fore * camera.near_plane;
    near_plane.w      = -signed_point_plane_distance({}, near_plane_point, camera_axis_fore);

    planes      := View_Frustum.Plane.[.TOP, .BOTTOM, .LEFT, .RIGHT];
    directions  := Vector3.[camera_axis_up, -camera_axis_up, -camera_axis_right, camera_axis_right];

    if camera.projection == .PERSPECTIVE {
        vt_fov    := camera.perspective_vertical_fov * (PI / 180.0);
        hz_fov    := get_camera_perspective_horizontal_fov(camera, viewport) * (PI / 180.0);
        half_fovs := float.[vt_fov * 0.5, -vt_fov * 0.5, hz_fov * 0.5, -hz_fov * 0.5];
        
        for 0..3 {
            rot_axis: Vector3;
            if it <= 1 {
                rot_axis = camera_axis_right;
            } else {
                rot_axis = camera_axis_up;
            }

            outward_plane_normal := rotate(directions[it], rot_axis, half_fovs[it]);
            plane := get_plane(*frustum, planes[it]);
            plane.xyz = -outward_plane_normal;
            plane.w = signed_point_plane_distance({}, camera_center, outward_plane_normal);
        }
    } else {
        aspect            := get_camera_aspect_ratio(camera, viewport);
        ortho_half_width  := camera.orthographic_scale * aspect;
        ortho_half_height := camera.orthographic_scale;

        ortho_dists := float.[ortho_half_height, ortho_half_height, ortho_half_width, ortho_half_width];

        for 0..3 {
            plane := get_plane(*frustum, planes[it]);
            plane.xyz = -directions[it];
            point_on_plane := camera_center + directions[it] * ortho_dists[it];
            plane.w = signed_point_plane_distance({}, point_on_plane, directions[it]);
        }
    }
    
    return frustum;
}

does_frustum_intersect_sphere :: (frustum: *View_Frustum, sphere_center: Vector3, sphere_radius: float) -> bool {
    near_dist := signed_point_plane_distance(sphere_center, get_plane(frustum, .NEAR).*);
    if near_dist < -sphere_radius || near_dist - sphere_radius > frustum.far_plane {
        return false;
    }
    inside_side_count: u8;
    top_dist   := signed_point_plane_distance(sphere_center, get_plane(frustum, .TOP).*);
    inside_side_count += cast(u8) (top_dist > -sphere_radius);
    bot_dist   := signed_point_plane_distance(sphere_center, get_plane(frustum, .BOTTOM).*);
    inside_side_count += cast(u8) (bot_dist > -sphere_radius);
    left_dist  := signed_point_plane_distance(sphere_center, get_plane(frustum, .LEFT).*);
    inside_side_count += cast(u8) (left_dist > -sphere_radius);
    right_dist := signed_point_plane_distance(sphere_center, get_plane(frustum, .RIGHT).*);
    inside_side_count += cast(u8) (right_dist > -sphere_radius);
    return inside_side_count == 4;
}


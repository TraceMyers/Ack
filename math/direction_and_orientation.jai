Direction_3D :: enum u8 {
    UP;
    DOWN;
    LEFT;
    RIGHT;
    FORE;
    BACK;
}

Direction_2D :: enum u8 {
    UP;
    RIGHT;
    DOWN;
    LEFT;
}

is_vertical :: (dir: Direction_2D) -> bool {
    return (dir & 0x1) == 0;
}

is_horizontal :: (dir: Direction_2D) -> bool {
    return (dir & 0x1) == 1;
}

rotate :: (dir: Direction_2D, clockwise := true) -> Direction_2D {
    if clockwise {
        return increment_wrap(dir, Direction_2D.UP, Direction_2D.LEFT);
    } else {
        return decrement_wrap(dir, Direction_2D.UP, Direction_2D.LEFT);
    }
}

to_direction2d :: (dir: Vector2) -> cardinal: Direction_2D {
    if abs(dir.y) > VERY_SMALL_NUMBER {
        if dir.x == 0 {
            return ifx dir.y > 0 then Y_POSITIVE_DIRECTION_2D else Y_NEGATIVE_DIRECTION_2D;
        }
        abs_xy_ratio := abs(dir.x / dir.y);
        if abs_xy_ratio >= 0.5 {
            return ifx dir.x > 0 then .RIGHT else .LEFT;
        } else {
            return ifx dir.y > 0 then Y_POSITIVE_DIRECTION_2D else Y_NEGATIVE_DIRECTION_2D;
        }
    } else if dir.x >= 0 {
        return .RIGHT;
    } else {
        return .LEFT;
    }
}

to_vector2 :: (cardinal: Direction_2D) -> Vector2 {
    if #complete dir == {
    case .UP;
        return VECTOR2_UP;
    case .RIGHT;
        return VECTOR2_RIGHT;
    case .DOWN;
        return VECTOR2_DOWN;
    case .LEFT;
        return VECTOR2_LEFT;
    }
}

to_vector3 :: (cardinal: Direction_3D) -> Vector3 {
    if #complete dir == {
    case .UP;
        return VECTOR3_UP;
    case .DOWN;
        return VECTOR3_DOWN;
    case .LEFT;
        return VECTOR3_LEFT;
    case .RIGHT;
        return VECTOR3_RIGHT;
    case .FORE;
        return VECTOR3_FORE;
    case .BACK;
        return VECTOR3_BACK;
    }
}

to_vector3 :: (cardinal: Direction_3D, orientation: Quaternion) -> Vector3 {
    if #complete cardinal == {
    case .UP;
        return  get_up_direction(orientation);
    case .DOWN;
        return -get_up_direction(orientation);
    case .LEFT;
        return -get_right_direction(orientation);
    case .RIGHT;
        return  get_right_direction(orientation);
    case .FORE;
        return  get_fore_direction(orientation);
    case .BACK;
        return -get_fore_direction(orientation);
    }
}

get_relative_direction_vector :: (up: Vector2, relative_direction: Direction_2D) -> Vector2 {
    if #complete relative_direction == {
    case .UP;
        return up;
    case .DOWN;
        return -up;
    case .RIGHT;
        return Vector2.{up.y, -up.x};
    case .LEFT;
        return Vector2.{-up.y, up.x};
    }
}

get_fore_direction :: inline (q: Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(VECTOR3_FORE, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

get_right_direction :: inline (q: Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(VECTOR3_RIGHT, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

get_up_direction :: inline (q: Quaternion, $do_normalize := true) -> Vector3 {
    vec := rotate(VECTOR3_UP, q);
    #if do_normalize {
        normalize(*vec);
    }
    return vec;
}

get_fore_direction_xy :: inline (q: Quaternion) -> Vector3 {
    fore_3d := get_fore_direction(q, false);
    fore_3d.z = 0;
    return normalize(fore_3d);
}

get_right_direction_xy :: inline (q: Quaternion) -> Vector3 {
    right_3d := get_right_direction(q, false);
    right_3d.z = 0;
    return normalize(right_3d);
}

calculate_axes :: (orientation: Quaternion, fore: *Vector3, right: *Vector3, up: *Vector3) {
    fore.* = get_fore_direction(orientation);
    up.* = get_up_direction(orientation);
    right.* = normalize(cross(fore.*, up.*));
}

// e.g. local -> world
change_basis_forward :: inline (scalars: Vector3, fore: Vector3, right: Vector3, up: Vector3) -> Vector3 {
    return right * scalars.x + fore * scalars.y + up * scalars.z;
}

// e.g. world -> local
change_basis_backward :: inline (vector: Vector3, fore: Vector3, right: Vector3, up: Vector3) -> Vector3 {
    return {dot(right, vector), dot(fore, vector), dot(up, vector)};
}

change_basis_forward :: (quaternion: Quaternion, basis_change: Matrix3) -> Quaternion {
    basis_quat := get_rotation(basis_change);
    return normalize(basis_quat * quaternion * conjugate(basis_quat));
}

distance_squared :: inline (q1: Quaternion, q2: Quaternion) -> float {
    diff := Vector4.{
        q1.x - q2.x,
        q1.y - q2.y,
        q1.z - q2.z,
        q1.w - q2.w,
    };
    return length_squared(diff);
}

distance :: inline (q1: Quaternion, q2: Quaternion) -> float {
    diff := Vector4.{
        q1.x - q2.x,
        q1.y - q2.y,
        q1.z - q2.z,
        q1.w - q2.w,
    };
    return length(diff);
}

make_quat :: (fore: Vector3, right: Vector3, up: Vector3) -> Quaternion {
    #if GENERAL_VALIDATION_LEVEL == Ack_Validation_Level.HIGH {
        if !is_normalized(fore,  SMALL_NUMBER) 
        || !is_normalized(right, SMALL_NUMBER)
        || !is_normalized(up,    SMALL_NUMBER) {
            ONE_OVER_ROOT_2 :: #run 1. / sqrt(2.);
            // if any of the vectors isn't normalized, randomly return one of two highly different rotations to make it obvious something is wrong. using % 4 (as opposed to % 2) to try to dodge the cpus that might only return even tsc values. https://community.intel.com/t5/Mobile-and-Desktop-Processors/RDTSC-only-returns-evenly-numbered-values-on-some-chips/m-p/1231812/highlight/true?profile.language=en
            if rdtsc() % 4 == 0 {
                return {x=ONE_OVER_ROOT_2, w=ONE_OVER_ROOT_2};
            } else {
                return {y=ONE_OVER_ROOT_2, w=ONE_OVER_ROOT_2};
            }
        }
    }
    rot_matrix := Matrix3.{
        right.x, fore.x, up.x,
        right.y, fore.y, up.y,
        right.z, fore.z, up.z,
    };
    return get_rotation(rot_matrix);
}

make_quat :: inline (fore: Vector3, up: Vector3) -> Quaternion {
    right := normalize(cross(fore, up));
    return make_quat(fore, right, up);
}

make_quat_with_fore_and_right :: inline (fore: Vector3, right: Vector3) -> Quaternion {
    up := normalize(cross(fore, -right)); 
    return make_quat(fore, right, up);
}

set_orientation :: (out_orientation: *Quaternion, forward: Vector3, up: Vector3) {
    out_orientation.* = make_quat(forward, up);
}

rotate :: (in_out_orientation: *Quaternion, axis: Vector3, angle: float32) {
    if angle == 0 then return;
    engine_check(.HIGH, is_normalized(axis));
    ht := angle * 0.5;
    sin_ht, cos_ht := sin_cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    in_out_orientation.* = rot_quat * in_out_orientation.*;
    normalize_or_identity(in_out_orientation);
}

rotate :: inline (v: Vector3, axis: Vector3, angle: float32, $do_normalize := true) -> Vector3 {
    if angle == 0 then return v;
    engine_check(.HIGH, is_normalized(axis));
    ht := angle * 0.5;
    sin_ht, cos_ht := sin_cos(ht);
    rot_quat := Quaternion.{xyz=axis*sin_ht, w=cos_ht};
    out_vec := rotate(v, rot_quat);
    if do_normalize {
        return normalize(out_vec);
    } else {
        return out_vec;
    }
}

interp_rotate_with_alpha :: (origin: Quaternion, target: Quaternion, alpha: float32) -> Quaternion {
    engine_check(.HIGH, alpha >= 0.0 && alpha <= 1.0, "alpha: %", alpha);
    cos_theta := dot(origin, target);

    // put target in the same hemisphere as the origin, so that the interpolation takes the shortest path
    use_target := ifx cos_theta < 0 then -target else target;
    
    if cos_theta >= ALMOST_COS_0 {
        return use_target;
    } else if cos_theta >= COS_PI_OVER_12 {
        // small distances can be lerped without being able to tell the difference
        return nlerp(origin, use_target, alpha);
    } else {
        return slerp(origin, use_target, alpha);
    }
}

// slow because of acos at the top
// instead of calling this a bunch, for a fixed rotation, just use quat multiply
interp_rotate_with_time :: (origin: Quaternion, target: Quaternion, speed: float32, delta_time: float32) -> Quaternion {
    engine_check(.HIGH, speed >= 0);
    rot_dist := speed * delta_time;
    cos_ht := abs(dot(origin, target));
    t := 2.0 * acos_approx(cos_ht);
    if abs(rot_dist) >= t {
        return target;
    } else {
        return interp_rotate_with_alpha(origin, target, rot_dist / t);
    }
}

quat_to_euler :: (q: Quaternion, degrees := true) -> Vector3 {
    yaw, roll, pitch: float = ---;
    // yaw (Z axis rotation)
    siny_cosp := 2.0 * (q.w * q.z + q.x * q.y);
    cosy_cosp := 1.0 - 2.0 * (q.y * q.y + q.z * q.z);
    yaw = atan2(siny_cosp, cosy_cosp);

    // roll (Y axis rotaton)
    sinr_cosp := 2.0 * (q.w * q.x + q.y * q.z);
    cosr_cosp := 1.0 - 2.0 * (q.x * q.x + q.y * q.y);
    roll = atan2(sinr_cosp, cosr_cosp);

    // pitch (X axis rotation)
    sinp := 2.0 * (q.w * q.y - q.z * q.x);
    if abs(sinp) >= 1 {
        pitch = PI / 2 * sign(sinp); // clamp
    } else {
        pitch = asin(sinp);
    }

    if degrees {
        return .{pitch, roll, yaw} * (180.0 / PI);
    } else {
        return .{pitch, roll, yaw};
    }
}

euler_to_quat :: (euler_angles: Vector3, degrees := true) -> Quaternion {
    use_angles := euler_angles;
    if degrees {
        use_angles *= (PI / 180.0);
    }
    sy, cy := sin_cos(use_angles.z * 0.5);
    sp, cp := sin_cos(use_angles.x * 0.5);
    sr, cr := sin_cos(use_angles.y * 0.5);

    q: Quaternion;
    q.w = cr * cp * cy + sr * sp * sy;
    q.x = sr * cp * cy - cr * sp * sy;
    q.y = cr * sp * cy + sr * cp * sy;
    q.z = cr * cp * sy - sr * sp * cy;
    return normalize(q);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

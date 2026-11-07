#load "boxes.jai";
#load "clamp.jai";
#load "constants.jai";
#load "conversion_rounding_and_respace.jai";
#load "orientation.jai";
#load "limits.jai";
#load "lines.jai";
#load "lut.jai";
#load "misc.jai";
#load "power_of_2.jai";
#load "smoothing.jai";
#load "transform.jai";
#load "trigonometry_and_exponentials.jai";
#load "vector.jai";
#load "frustum.jai";

math_test :: () -> bool {
    near :: (a: float64, b: float64, tolerance := 0.0001) -> bool {
        return abs(a - b) <= tolerance;
    }
    near :: (a: Vector3, b: Vector3, tolerance := 0.0001) -> bool {
        return length(a - b) <= tolerance;
    }
    // q and -q are the same rotation
    same_rotation :: (a: Quaternion, b: Quaternion, tolerance := 0.0005) -> bool {
        return abs(abs(dot(a, b)) - 1.0) <= tolerance;
    }

    // --- powers of two
    test_condition(!is_power_of_two(0));
    test_condition(!is_power_of_two(-1));
    test_condition(!is_power_of_two(65));
    for i : 0..62 {
        pow2 := (1).(s64) << i;
        test_condition(is_power_of_two(pow2));
        if i > 1 then test_condition(!is_power_of_two(pow2 - 1));
    }
    test_condition(ceil_to_power_of_two(1) == 1);
    test_condition(ceil_to_power_of_two(5) == 8);
    test_condition(ceil_to_power_of_two(8) == 8);
    test_condition(ceil_to_power_of_two(1000) == 1024);
    test_condition(ceil_to_power_of_two_multiple(13, 8) == 16);
    test_condition(ceil_to_power_of_two_multiple(16, 8) == 16);
    test_condition(floor_to_power_of_two_multiple(15, 8) == 8);
    for i : 0..20 {
        test_condition((1 << shift_for_power_of_two_mul_or_div(1 << i)) == (1 << i));
    }

    // --- integer multiples and wrapping
    test_condition(div_ceil(9, 8) == 2 && div_ceil(8, 8) == 1 && div_ceil(1, 8) == 1);
    test_condition(ceil_to_multiple(9, 8) == 16 && ceil_to_multiple(8, 8) == 8 && ceil_to_multiple(7, 8) == 8);
    test_condition(floor_to_multiple(9, 8) == 8 && floor_to_multiple(8, 8) == 8 && floor_to_multiple(7, 8) == 0);
    test_condition(align_up(13, 16) == 16 && align_up(32, 16) == 32);

    test_condition(add_wrap(5, 20, 2, 8) == 4);
    test_condition(add_wrap(11, 2, 2, 12) == 2);
    test_condition(add_wrap(11, 2 + 10, 2, 12) == 12);
    test_condition(add_wrap(3, 9, 2, 12) == 12);
    test_condition(add_wrap(3, -1, 2, 12) == 2);
    test_condition(add_wrap(3, -2, 2, 12) == 12);
    test_condition(add_wrap(3, -12, 2, 12) == 2);
    test_condition(add_wrap(3, -13, 2, 12) == 12);
    test_condition(add_wrap(2, 20, 2, 2) == 2 && add_wrap(2, -20, 2, 2) == 2);
    test_condition(increment_wrap(8, 2, 8) == 2 && increment_wrap(5, 2, 8) == 6);
    test_condition(decrement_wrap(2, 2, 8) == 8 && decrement_wrap(5, 2, 8) == 4);

    // --- conversion, rounding, respace
    test_condition(round(2.5) == 2 && round(2.51) == 3 && round(-2.51) == -3 && round(-0.4) == 0);
    {
        int_val: u8 = 127;
        test_condition(abs(alter_cast(int_val, float, true) - 0.5) <= 0.005);
        int_val = 0;
        test_condition(alter_cast(int_val, float, true) == 0.0);
        int_val = 255;
        test_condition(alter_cast(int_val, float, true) == 1.0);

        test_condition(alter_cast(0.0, s8, false, false) == 0);
        test_condition(alter_cast(1.0, s8, true, false) == 127);
        test_condition(alter_cast(1.0, s8, true, true) == 127);
        test_condition(alter_cast(300.0, u8) == 255);
        test_condition(alter_cast(-5.0, u8) == 0);

        // round() clamps instead of overflowing
        big: float = xx S32_MAX;
        test_condition(alter_cast(big, s32, false, true) == S32_MAX);
        min_s32: s32 = S32_MIN;
        small := min_s32.(float) - 128.0;
        test_condition(alter_cast(small, s32, false, true) == S32_MIN);
    }
    test_condition(near(respace(5, .{0, 10}, .{0, 1}), 0.5));
    test_condition(near(respace(2.5, .{10, 0}, .{0, 1}), 0.75));
    test_condition(near(respace(20, .{0, 10}, .{0, 1}), 1.0));
    test_condition(near(respace(20, .{0, 10}, .{0, 1}, do_clamp=false), 2.0));
    test_condition(near(respace(0.25, .{0, 1}, .{-4, 4}), -2.0));

    // --- misc
    test_condition(sign(-3) == -1 && sign(0) == 0 && sign(0, false) == 1 && sign(-2.5) == -1.0);
    test_condition(compose_float(1, "5", 0) == 1.5);
    test_condition(compose_float(-3, "25", 0) == -3.25);
    test_condition(compose_float(1, "", 3) == 1000.0);
    test_condition(compose_float(0, "", 0) == 0.0);
    test_condition(abs(compose_float(0, "1", 0) - 0.1) <= 0.1 * 1.0e-15);
    test_condition(abs(compose_float(12345, "678", -3) - 12.345678) <= 12.345678 * 1.0e-15);
    test_condition(abs(compose_float(6, "02214076", 23) - 6.02214076e23) <= 6.02214076e23 * 1.0e-15);
    {
        f, ok := compose_float("201", "0001", "-2");
        test_condition(ok && abs(f - 2.010001) <= 1.0e-15);
        _, ok = compose_float("2a", "", "");
        test_condition(!ok);
        _, ok = compose_float("-", "", "");
        test_condition(!ok);
    }

    // --- constants
    test_condition(near(COS_PI_OVER_4, cos(PI / 4)));
    test_condition(near(COS_PI_OVER_3, 0.5));
    test_condition(near(SIN_PI_OVER_3, sqrt(3.0) / 2));
    test_condition(near(SIN_PI_OVER_6, 0.5));

    // --- fast trig approximations stay within their documented error
    for i : 0..2000 {
        x := -50.0 + i.(float) * 0.05;
        s, c := sin_cos(x);
        test_condition(near(s, sin(x), 0.002) && near(c, cos(x), 0.002));
    }
    for i : 0..200 {
        x := -1.0 + i.(float) * 0.01;
        test_condition(near(acos_approx(x), acos(x), 0.001));
    }
    for i : 0..100 {
        x := -5.0 + i.(float) * 0.1;
        test_condition(abs(exp_approx(x) - exp(x)) <= exp(x) * 0.07);
    }

    // --- planes, reflection, lines
    {
        point := Vector3.{3, 4, 5};
        plane := Vector4.{0, 0, 1, 2}; // normal (0, 0, 1), 2 units from origin
        pos, dist := project_point_onto_plane(point, plane);
        test_condition(near(pos, .{3, 4, 2}) && near(dist, 3));
        test_condition(near(signed_point_plane_distance(.{0, 0, -1}, plane), -3));
        test_condition(near(project_vector_onto_plane(.{1, 2, 3}, VECTOR3_UP), .{1, 2, 0}));
        test_condition(near(reflect(.{1, -1, 0}, .{0, 1, 0}), .{1, 1, 0}));
    }
    {
        pa, pb: Vector3;
        // skew segments crossing over each other
        s, t := closest_point_on_each_line_segment(.{-1, 0, 0}, .{1, 0, 0}, .{0, -1, 1}, .{0, 1, 1}, *pa, *pb);
        test_condition(near(s, 0.5) && near(t, 0.5) && near(pa, .{0, 0, 0}) && near(pb, .{0, 0, 1}));
        // parallel and not overlapping: a's end is closest to b's beginning
        s, t = closest_point_on_each_line_segment(.{0, 0, 0}, .{1, 0, 0}, .{3, 1, 0}, .{5, 1, 0}, *pa, *pb);
        test_condition(near(s, 1) && near(t, 0) && near(pa, .{1, 0, 0}) && near(pb, .{3, 1, 0}));
        // the closest points are past the segment ends, so they clamp
        s, t = closest_point_on_each_line_segment(.{0, 0, 0}, .{1, 0, 0}, .{2, 1, 0}, .{2, 3, 0}, *pa, *pb);
        test_condition(near(pa, .{1, 0, 0}) && near(pb, .{2, 1, 0}));

        on_segment, norm := closest_point_on_line_segment(Vector3.{5, 1, 0}, .{0, 0, 0}, .{2, 0, 0});
        test_condition(near(on_segment, .{2, 0, 0}) && near(norm, 1));
        on_line, line_norm := closest_point_on_line(Vector3.{5, 1, 0}, .{0, 0, 0}, .{2, 0, 0});
        test_condition(near(on_line, .{5, 0, 0}) && near(line_norm, 2.5));
    }

    // --- 2d directions
    test_condition(to_direction2d(.{1, 0.1}) == .RIGHT);
    test_condition(to_direction2d(.{-1, 0}) == .LEFT);
    test_condition(to_direction2d(.{0.1, 1}) == Y_POSITIVE_DIRECTION_2D);
    test_condition(rotate(Direction_2D.UP) == .RIGHT && rotate(Direction_2D.LEFT) == .UP);
    test_condition(rotate(Direction_2D.UP, false) == .LEFT);
    test_condition(is_vertical(.DOWN) && is_horizontal(.LEFT));

    // --- orientation
    {
        yaw_90 := rotate(Quaternion.{}, VECTOR3_UP, PI / 2);
        test_condition(near(get_fore_direction(yaw_90), VECTOR3_LEFT, 0.001));
        test_condition(near(get_right_direction(yaw_90), VECTOR3_FORE, 0.001));
        test_condition(near(get_up_direction(yaw_90), VECTOR3_UP, 0.001));
        test_condition(near(to_relative_direction_vector(yaw_90, .BACK), VECTOR3_RIGHT, 0.001));

        q := euler_to_quat(.{20, -35, 110});
        x, y, z: Vector3;
        calculate_axes(q, *x, *y, *z);
        test_condition(near(dot(x, y), 0, 0.001) && near(dot(y, z), 0, 0.001) && near(dot(x, z), 0, 0.001));
        test_condition(near(cross(x, y), z, 0.001));
        test_condition(same_rotation(make_quat(x, y, z), q));
        test_condition(same_rotation(make_quat_xy(x, y), q));
        test_condition(same_rotation(make_quat_xz(x, z), q));
        test_condition(same_rotation(make_quat_yz(y, z), q));

        test_condition(near(quat_to_euler(q), .{20, -35, 110}, 0.05));
        test_condition(near(quat_to_euler(euler_to_quat(.{-60, 10, -45})), .{-60, 10, -45}, 0.05));

        test_condition(near(change_basis_world_to_local(change_basis_local_to_world(.{1, 2, 3}, x, y, z), x, y, z), .{1, 2, 3}, 0.001));

        // interpolation takes the short path and hits both ends
        target := rotate(Quaternion.{}, VECTOR3_UP, PI / 2);
        test_condition(same_rotation(interp_rotate_with_alpha(.{}, target, 0), .{}));
        test_condition(same_rotation(interp_rotate_with_alpha(.{}, target, 1), target));
        half := rotate(Quaternion.{}, VECTOR3_UP, PI / 4);
        test_condition(same_rotation(interp_rotate_with_alpha(.{}, target, 0.5), half));
        test_condition(same_rotation(interp_rotate_with_alpha(.{}, -target, 0.5), half));
        test_condition(same_rotation(interp_rotate_with_time(.{}, target, 1, 100), target));
    }

    // --- transforms
    {
        position := Vector3.{1, -2, 3};
        orientation := euler_to_quat(.{15, 30, -70});
        scale := Vector3.{2, 3, 0.5};
        mat := make_transform_matrix(position, orientation, scale);

        // the matrix applies scale, then rotation, then translation
        local := Vector3.{1, 1, 1};
        expected := rotate(local * scale, orientation) + position;
        transformed := mat * Vector4.{local.x, local.y, local.z, 1};
        test_condition(near(transformed.xyz, expected, 0.001));

        out_position, out_scale: Vector3;
        out_orientation: Quaternion;
        decompose_transform_matrix(*mat, *out_position, *out_orientation, *out_scale);
        test_condition(near(out_position, position, 0.001));
        test_condition(near(out_scale, scale, 0.001));
        test_condition(same_rotation(out_orientation, orientation));
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

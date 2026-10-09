// most procedures by default take an alpha in [0, 1] and return a y value in [0, 1].
// adjust x params to change the domain (e.g. x_min=0 and x_max=0.5 for curve_linear takes alpha
// in [0, 1] and return y in [0, 0.5].
// adjust y params to bias and scale the function

Curve :: struct {
    type: Curve_Type;

    y_offset := 0.0;
    y_scale  := 1.0;

    x_min := 0.0;
    x_max := 1.0;

    #overlay(x_min) sine_phase: float;
    #overlay(x_max) sine_frequency: float;

    #overlay(x_min) bias: float;

    #overlay(x_min) gain: float;

    #overlay(x_min) cubic_begin_slope: float;
    #overlay(x_max) cubic_end_slope: float;
}

apply_curve :: inline (curve: Curve, alpha: float) -> float {
    return CURVE_PROCEDURES[curve.type](alpha, curve.x_min, curve.x_max, curve.y_offset, curve.y_scale);
}

apply_linear_curve :: (alpha: float, x_min := 0.0, x_max := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := alpha_to_x(alpha, x_min, x_max);
    return y_offset + y_scale * y;
}

apply_smooth_step_curve :: (alpha: float, x_min := 0.0, x_max := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    y := (3 * x * x) - (2 * x * x * x);
    return y_offset + y_scale * y;
}

apply_smoother_step_curve :: (alpha: float, x_min := 0.0, x_max := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    x_sq := x * x;
    y := (6 * x_sq * x_sq * x) - (15 * x_sq * x_sq) + (10 * x_sq * x);
    return y_offset + y_scale * y;
}

// (1 - cos(f * (x * pi - p))) * 0.5
apply_sinusoid_curve :: (alpha: float, phase := 0.0, frequency := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := (1 - cos(frequency * (alpha * PI - phase))) * 0.5;
    return y_offset + y_scale * y;
}

apply_sigmoid_curve :: (alpha: float, x_min := -8.0, x_max := 8.0, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    y := 1 / (1 + exp(-x));
    return y_offset + y_scale * y;
}

apply_bias_curve :: (alpha: float, bias := 0.5, _ := 0.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := calculate_bias_curve(alpha, bias);
    return y_offset + y_scale * y;
}

apply_gain_curve :: (alpha: float, gain := 0.5, _ := 0.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := ifx alpha < 0.5 
        then calculate_bias_curve(2 * alpha, gain) * 0.5 
        else 1 - calculate_bias_curve(2 - 2 * alpha, gain) * 0.5;
    return y_offset + y_scale * y;
}

apply_cubic_curve :: (alpha: float, start_slope: float, end_slope: float, y_offset := 0.0, y_scale := 1.0) -> float {
    x0 :: 0.0;
    x1 :: 1.0;
    y0 :: 0.0;
    y1 :: 1.0;

    s    := alpha;
    s_sq := s * s;
    s_cu := s_sq * s;

    y := (2 * y0 - 2 * y1 + (x1 - x0) * (start_slope + end_slope)) * s_cu + (-3 * y0 + 3 * y1 - (x1 - x0) * (2 * start_slope + end_slope)) * s_sq + ((x1 - x0) * start_slope) * s + y0;

    return y_offset + y_scale * y;
}

// by default, 0 -> 0, 0.5 -> 1, 1 -> 0
apply_triangle_curve :: (alpha: float, x_min := 0.0, x_max := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    x           := alpha_to_x(alpha * 2, x_min, x_max);
    xf          := floor(x);
    base        := (cast(s32) xf) & 0x1;
    tooth_alpha := x - xf;
    slope       := cast(float) (1 - base * 2);
    y           := base + tooth_alpha * slope;
    return y_offset + y_scale * y;
}

apply_square_curve :: (alpha: float, x_min := 0.0, x_max := 0.999999, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    y := (cast(int) floor(x * 2)) & 0x1;
    return y_offset + y_scale * y;
}

apply_sawtooth_curve :: (alpha: float, x_min := 0.0, x_max := 0.999999, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    xf := floor(x);
    y  := x - xf;
    return y_offset + y_scale * y;
}

// todo: make a universal curve palette that 1. applies to any engine float field (including user-made interfaces) and many under-the-hood float values and 2. you can call up the interface whenever and apply your interactions (curve selection + params) to whatever you like in code.
use_curve_palette :: (window: Window_Type, renderer: *Renderer, camera_info: Camera_Info, camera_position: Vector3, camera_orientation: Quaternion, viewport: Vector2, time: float, screen_portion_max := 0.4) -> float {
    if viewport.x == 0 || viewport.y == 0 {
        engine_warning(.HIGH, "viewport = % both components must be nonzero", viewport);
        return 0;
    }

    plane_dist := 0.1;
    draw_plane := make_draw_plane(camera_info, viewport, plane_dist);

    fore_dir  := get_fore_direction(camera_orientation);
    up_dir    := get_up_direction(camera_orientation);
    right_dir := get_right_direction(camera_orientation);

    viewport_ratio := viewport.y / viewport.x;

    height_pad := 0.025;
    width_pad  := height_pad * viewport_ratio;

    draw_rect_height := min(1 - height_pad * 2, screen_portion_max);
    draw_rect_width  := draw_rect_height * viewport_ratio;

    squares_per_side := cast(int) (ceil(sqrt(cast(float) CURVE_PROCEDURES.count)) + 0.00001);

    if squares_per_side == 0 {
        return 0;
    }

    inner_height_pad := 0.025;
    inner_width_pad  := inner_height_pad * viewport_ratio;

    square_height    := (draw_rect_height - inner_height_pad * (squares_per_side - 1)) / squares_per_side;
    square_width     := square_height * viewport_ratio;

    // centered
    // begin_draw_x := 0.5 - 0.5 * (squares_per_side * square_width + (squares_per_side - 1) * inner_width_pad);

    // bottom right align
    begin_draw_x := 1 - (width_pad + squares_per_side * square_width + (squares_per_side - 1) * inner_width_pad);

    t := time - cast(int) time;

    for y : 0..squares_per_side-1 {
        for x : 0..squares_per_side-1 {
            curve_type := cast(Curve_Type) (y * squares_per_side + x);
            if curve_type >= CURVE_PROCEDURES.count {
                break y;
            }

            norm_ll_x := begin_draw_x + (inner_width_pad  + square_width)  * cast(float) x;
            norm_ll_y := height_pad + (inner_height_pad + square_height) * cast(float) y;
            norm_ur_x := norm_ll_x + square_width;
            norm_ur_y := norm_ll_y + square_height;

            ll := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, {norm_ll_x, norm_ll_y});
            lr := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, {norm_ur_x, norm_ll_y});
            ur := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, {norm_ur_x, norm_ur_y});
            ul := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, {norm_ll_x, norm_ur_y});

            curve := Curve.{type=curve_type, y_offset=norm_ll_y, y_scale=norm_ur_y-norm_ll_y};

            // todo: change curve params over time, but first do the ball thing
            if curve_type == {
            case .BIAS;
                curve.bias = 0.25;
            case .GAIN;
                curve.gain = 0.25;
            case .CUBIC;
                curve.cubic_begin_slope = 3;
                curve.cubic_end_slope = 1;
            case .SQUARE; #through;
            case .SAWTOOTH;
                curve.x_max = 1.99999;
            }

            prev_point: Vector2;
            END :: 30;
            for 0..END {
                alpha := cast(float) it / END;
                x := norm_ll_x + alpha * (norm_ur_x - norm_ll_x);
                y := apply_curve(curve, alpha);

                new_point := Vector2.{x, y};
                defer prev_point = new_point;

                if it > 0 {
                    line_pt_0 := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, new_point);
                    line_pt_1 := get_point_on_draw_plane(draw_plane, camera_info, camera_position, fore_dir, up_dir, prev_point);
                    draw_line(renderer, line_pt_0, line_pt_1, COLOR4B_WHITE, 3, true);
                }
            }

            raycast_result: Raycast_Result_Simple;
            _, pointer_ray := get_camera_ray_passing_through_mouse_pointer_position(camera_info, camera_position, camera_orientation, viewport, window);
            if raycast_rectangle(*raycast_result, camera_position, pointer_ray, (ll + ur) * 0.5, length(lr-ll) * 0.5, length(ul-ll) * 0.5, right_dir, up_dir, -fore_dir) {
                draw_line(renderer, ul, ur, COLOR4B_WHITE, 3);
                draw_line(renderer, ur, lr, COLOR4B_WHITE, 3);
                draw_line(renderer, lr, ll, COLOR4B_WHITE, 3);
                draw_line(renderer, ll, ul, COLOR4B_WHITE, 3);

                curve.y_offset = 0;
                curve.y_scale  = 1;
                circle_pt  := ll + (lr - ll) * apply_curve(curve, t);
                circle_rad := square_width * 0.08 * plane_dist;

                draw_circle(renderer, circle_pt, circle_rad, up_dir, right_dir, COLOR4B_WHITE, 3);
            }
        }
    }

    return 0;
}

#scope_file

CURVE_CREATE_INFOS :: Enumarray_Create_Info.[
    {"LINEAR",          apply_linear_curve},
    {"SMOOTH_STEP",     apply_smooth_step_curve},
    {"SMOOTHER_STEP",   apply_smoother_step_curve},
    {"SINUSOID",        apply_sinusoid_curve},
    {"BIAS",            apply_bias_curve},
    {"GAIN",            apply_gain_curve},
    {"CUBIC",           apply_cubic_curve},
    {"TRIANGLE",        apply_triangle_curve},
    {"SQUARE",          apply_square_curve},
    {"SAWTOOTH",        apply_sawtooth_curve}
];

Curve_Procedure :: #type (alpha: float, param_a: float, param_b: float, y_offset: float, y_scale: float) -> float;

#insert #run generate_parallel_enum_and_array(..CURVE_CREATE_INFOS, "Curve_Type", u8, "CURVE_PROCEDURES", "Curve_Procedure", true);

alpha_to_x :: inline (alpha: float, x_min: float, x_max: float) -> float {
    max_min_diff := x_max - x_min;
    x_diff := alpha * max_min_diff;
    return x_min + x_diff;
}

calculate_bias_curve :: inline (alpha: float, bias: float) -> float {
    return alpha / ((1 / bias - 2) * (1 - alpha) + 1);
}

curve_palette_selection: int;

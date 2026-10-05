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

    #overlay(x_min) radian_begin: float;
    #overlay(x_max) radian_end: float;

    #overlay(x_min) bias: float;
    #overlay(x_max) gain: float;
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

// 1 - 0.5 * cos(f * (x * pi - p))
apply_sinusoid_curve :: (alpha: float, phase := 0.0, frequency := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := 1 - 0.5 * cos(frequency * (alpha * pi - phase));
    return y_offset + y_scale * y;
}

apply_sigmoid_curve :: (alpha: float, x_min := 0.0, x_max := 1.0, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    y := 1 / (1 + exp(-x));
    return y_offset + y_scale * y;
}

apply_bias_curve :: (alpha: float, bias := 0.5, #discard _ := 0.0, y_offset := 0.0, y_scale := 1.0) -> float {
    y := calculate_bias_curve(alpha, bias);
    return y_offset + y_scale * y;
}

apply_gain_curve :: (alpha: float, bias := 0.5, gain := 0.5, y_offset := 0.0, y_scale := 1.0) -> float {
    y := ifx alpha < 0.5 
        then calculate_bias_curve(2 * alpha, gain) * 0.5 
        else 1 - calculate_bias_curve(2 - 2 * alpha, gain) * 0.5;
    return y_offset + y_scale * y;
}

apply_cubic_hermite_curve :: (alpha: float, start_slope: float, end_slope: float, y_offset := 0.0, y_scale := 1.0) -> float {
    a_sq := alpha * alpha;
    a_cu := a_sq * a;
    y := start_slope * (a_cu - 2 * a_sq + a) + (3 * a_sq - 2 * a_cu) + end_slope * (a_cu - a_sq);
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

apply_square_curve :: (alpha: x_min := 0.0, x_max := 0.999999, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    y := (cast(int) floor(x * 2)) & 0x1;
    return y_offset + y_scale * y;
}

apply_sawtooth_curve :: (alpha: x_min := 0.0, x_max := 0.999999, y_offset := 0.0, y_scale := 1.0) -> float {
    x := alpha_to_x(alpha, x_min, x_max);
    xf := floor(x);
    y  := x - xf;
    return y_offset + y_scale * y;
}

#scope_file

CURVE_CREATE_INFOS :: Enumarray_Create_Info.[
    {"LINEAR",          apply_linear_curve},
    {"SMOOTH_STEP",     apply_smooth_step_curve},
    {"SMOOTHER_STEP",   apply_smoother_step_curve},
    {"SINUSOID",        apply_sinusoid_curve},
    {"BIAS",            apply_bias_curve},
    {"GAIN",            apply_gain_curve},
    {"CUBIC_HERMITE",   apply_cubic_hermite_curve},
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

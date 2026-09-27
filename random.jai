// credit to Marc "MAHK" LeBlanc
// predicate can take either pointer to T or just T. returns the same.
random_select :: (array: []$T1, predicate: (x: $T2) -> bool, _state: *Random_State = null) -> T2 #modify { 
    return T2 == T1 || type_2_is_pointer_to_type_1(T1, T2);
} {
    best_score := -1.0;
    best_item: T2;

    state := ifx _state == null then *context.random_state else _state;

    for *=(T2==*T1) array {
        if predicate(it) {
            score := random_get_zero_to_one(state);
            if score > best_score {
                best_score = score;
                best_item  = it;
            }
        }
    }
    
    return best_item;
}

random_color :: inline (saturation_range := Vector2.{0.3, 1.0}, lightness_range := Vector2.{0.3, 0.7}, alpha := 1.0, random_state : *Random_State = null) -> Color4f {
    if random_state == null {
        random_state = *context.random_state;
    }

    hsy: Color_HSY = ---;
    hsy.hue        = random_get_zero_to_one(random_state);
    hsy.saturation = respace(random_get_zero_to_one(random_state), {0, 1}, saturation_range);

    lightness     := respace(random_get_zero_to_one(random_state), {0, 1}, lightness_range);
    set_lightness(*hsy, lightness);

    hsy.alpha      = alpha;

    return hsy_to_rgb(hsy);
}

random_vector :: (x_range: Vector2, y_range: Vector2, z_range: Vector2, state: *Random_State = null) -> Vector3 {
    x, y, z: float;
    if state {
        x = random_get_zero_to_one(state);
        y = random_get_zero_to_one(state);
        z = random_get_zero_to_one(state);
    } else {
        x = random_get_zero_to_one();
        y = random_get_zero_to_one();
        z = random_get_zero_to_one();
    }
    return {
        respace(x, {0, 1}, x_range),
        respace(y, {0, 1}, y_range),
        respace(z, {0, 1}, z_range)
    };
}

// 'pdf' doesn't have to be normalized for its domain.
// sample_resolution is how many possible y values can be drawn from the distribution.
// sample_granularity is the maximum difference in likelihood between y values.
make_pmf :: (pdf: (x: float) -> y: float, min_x: float, max_x: float, sample_resolution: int, sample_granularity := 10.0) -> []float {
    engine_check(.LOW, sample_resolution >= 2);
    engine_check(.LOW, sample_granularity >= 2);

    y_value_count_max := sample_granularity - 1;

    curve := make_lut(pdf, min_x, max_x, sample_resolution,, temp);

    max_y: float;
    for y : curve.y_values {
        // (pseudo) likelihood values must be >= 0
        engine_check(.HIGH, y >= 0);
        max_y = max(y, max_y);
    }

    if max_y <= 0 {
        return .[0.0];
    }
    inv_max_y := 1.0 / max_y;

    total_sample_count: int;
    for y : curve.y_values {
        total_sample_count += round(y * inv_max_y * sample_granularity);
    }

    if total_sample_count == 0 {
        return .[0.0];
    }

    pmf: [..]float;
    array_reserve(*pmf, total_sample_count);

    for y : curve.y_values {
        sample_count := round(y * inv_max_y * sample_granularity);
        if sample_count > 0 { 
            x := get_lut_x_value(it_index, min_x, max_x, sample_resolution);
            for 0..sample_count - 1 {
                array_add(*pmf, x);
            }
        }
    }

    return pmf;
}

sample :: (array: []$T, state: *Random_State = null) -> T {
    x := ifx state then random_get_zero_to_one(state) else random_get_zero_to_one();
    i := round(respace(x, {0, 1}, {0, xx (array.count - 1)}));
    return array[i];
}


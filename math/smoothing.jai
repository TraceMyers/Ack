decay_exponentially_with_time :: inline (a: $T/VectorAndFloatTypes, b: T, speed: float32, delta_time: float32) -> T {
    move_factor := min(speed * delta_time, 1.0);
    return a + (b - a) * move_factor;
}

sigmoid :: inline (x: float32) -> float32 {
    return 1.0 / (1.0 + exp(-x));
}

// alpha: 0 to 1 linear value to be transformed into an S-curve value
// extent: how much of the curve to include. smaller number will clip values close to the edges and as such will also begin and end at a faster speed (steeper gradient on curve)
// midpoint: 0 to 1 linear value, toward 0 = more time spent smoothing out, toward 1 = more time spent smoothing in
interp_sigmoid_with_alpha :: (alpha: float32, extent := 10.0, midpoint := 0.5) -> float32 {
    sigmoid_input: float32 = ---;
    if midpoint != 0.5 {
        if alpha < midpoint {
            sigmoid_input = respace(alpha, {0, midpoint}, {0, 0.5});
        } else {
            sigmoid_input = respace(alpha, {midpoint, 1}, {0.5, 1});
        }
    } else {
        sigmoid_input = alpha;
    }
    neg_one_to_one := (sigmoid_input - 0.5) * 2.0;
    return sigmoid(clamp(neg_one_to_one * extent, -extent, extent));
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

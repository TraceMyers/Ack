clamp :: inline (v: $T/Vector2Types, min: T, max: T) -> T {
    return .{
        clamp(v.x, min.x, max.x),
        clamp(v.y, min.y, max.y),
    };
}

clamp :: inline (v: $T/Vector3Types, min: T, max: T) -> T {
    return .{
        clamp(v.x, min.x, max.x),
        clamp(v.y, min.y, max.y),
        clamp(v.z, min.z, max.z),
    };
}

clamp_point_to_rect :: inline (point: Vector3, rect_center: Vector3, rect_up: Vector3, rect_right: Vector3, half_height: float, half_width: float) -> Vector3 {
    toward_point := point - rect_center;
    // todo: for collisions only, axes will be cached
    clamped_z_dist := clamp(dot(toward_point, rect_up),    -half_height, half_height);
    clamped_x_dist := clamp(dot(toward_point, rect_right), -half_width,  half_width);
    return rect_center + rect_up * clamped_z_dist + rect_right * clamped_x_dist;
}

min_and_max :: inline (a: $T, b: T) -> min: T, max: T {
    if a < b {
        return a, b;
    } else {
        return b, a;
    }
}

min_and_max :: inline (a: $T, b: T, $a_less_than_b: (T, T) -> bool) -> min: T, max: T {
    if inline a_less_than_b(a, b) {
        return a, b;
    } else {
        return b, a;
    }
}

min :: inline (a: $T, b: T, $a_less_than_b: (T, T) -> bool) -> min: T {
    if inline a_less_than_b(a, b) {
        return a;
    } else {
        return b;
    }
}

max :: inline (a: $T, b: T, $a_less_than_b: (T, T) -> bool) -> min: T {
    if inline a_less_than_b(a, b) {
        return b;
    } else {
        return a;
    }
}

increment_wrap :: inline (val: $T, min: T, max: T) -> T {
    if val >= max {
        val = min;
    } else val += 1;
    return val;
}

decrement_wrap :: inline (val: $T, min: T, max: T) -> T {
    if val <= min {
        val = max;
    } else val -= 1;
    return val;
}

add_wrap :: (val: $T, add_amt: T, min: T, max: T) -> T {
    engine_check(.MEDIUM, val >= min && val <= max && max >= min);
    sum := val + add_amt;
    min_max_diff := (max - min) + 1;
    if sum > max {
        sum_max_diff := sum - (max + 1); // adding one makes the rest simpler
        remainder := sum_max_diff % min_max_diff;
        return min + remainder;
    } else if sum < min {
        min_sum_diff := (min - 1) - sum;
        remainder := min_sum_diff % min_max_diff;
        return max - remainder;
    } else {
        return sum;
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

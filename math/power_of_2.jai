is_power_of_two :: inline (val: $T) -> bool {
    return val > 0 && (val & (val - 1)) == 0;
}

ceil_to_power_of_two_multiple :: inline (n: $T, power_of_two_size: T) -> T {
    engine_check(.HIGH, is_power_of_two(power_of_two_size));
    return (n + power_of_two_size-1) & ~(power_of_two_size-1);
}

// floor to a multiple of a power of 2
floor_to_power_of_two_multiple :: inline (n: $T, power_of_two_size: T) -> T {
    engine_check(.HIGH, is_power_of_two(power_of_two_size));
    return n & ~(power_of_two_size-1);
}

ceil_to_power_of_two :: inline (n: $T) -> T {
    if n == 0 {
        return 0;
    } else if !is_power_of_two(n) {
        return xx ((1).(u64) << (bit_scan_reverse(n)).(u64));
    } else return n;
}

shift_for_power_of_two_mul_or_div :: inline (divide_by: int) -> u8 {
    engine_check(.HIGH, is_power_of_two(divide_by), "non power of two: %", divide_by);
    return xx (bit_scan_forward(divide_by) - 1);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

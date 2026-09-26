sign :: inline (x: $T, $can_return_zero := true) -> T {
    #if can_return_zero {
        if x == 0 return xx 0;
    }
    return ifx x < 0 then (-1).(T) else (1).(T);
}

deg2rad :: inline (deg: float) -> rad: float {
    return deg * (PI / 180.0);
}

rad2deg :: inline (rad: float) -> deg: float {
    return rad * (180.0 / PI);
}

splat :: inline (x: float, $vector_size: int) -> $T
#modify {
    T = void;
    if vector_size == {
    case 2;
        T = Vector2;
    case 3;
        T = Vector3;
    case 4;
        T = Vector4;
    }
    return T != void;
} {
    #if vector_size == {
    case 2;
        return {x, x};
    case 3;
        return {x, x, x};
    case 4;
        return {x, x, x, x};
    }
}

// note that because this is done step-wise, it degrades the amount at each step, not the initial value. meaning, it doesn't actually lose 'proportion_lost_per_second' per second. that name only makes sense if you consider what is happening in the moment of application.
degrade_over_time :: (x: *$T/VectorAndFloatTypes, proportion_lost_per_second: float, time_step: float) -> bool {
    IS_VECTOR_TYPE :: #run array_find(VectorTypes, T);
    keep_proportion_per_second := 1 - proportion_lost_per_second;
    delta := x.* * (keep_proportion_per_second * time_step);
    #if IS_VECTOR_TYPE {
        if length_squared(delta) > length_squared(x) {
            x.* = .{};
            return true;
        } else {
            x.* -= delta;
            return false;
        }
    } else {
        if delta > x {
            x.* = 0;
            return true;
        } else {
            x.* -= delta;
            return false;
        }
    }
}

// compose a float, as in ("201", "0001", "-2") -> 2.010001
compose_float :: (base: string, fraction: string, exponent: string) -> float64, bool {
    // ---

    to_digit :: inline (byte: u8) -> u8 {
        if byte >= #char "0" && byte <= #char "9" {
            return byte - #char "0";
        }
        return 0xff;
    }

    parse_float_component :: inline (component_str: string) -> s64, bool {
        value : s64 = 0;
        sign  : s64 = 1;
        for component_str {
            if it == #char "-" {
                if it_index != 0 || component_str.count == 1 {
                    return 0, false;
                }
                sign = -1;
            } else {
                digit := to_digit(it);
                if digit > 9 {
                    return 0, false;
                } 
                value = value * 10 + digit;
            }
        }
        return value * sign, true;
    }

    // ---

    b, success := parse_float_component(base);
    if !success then return 0, false;
    e:, success = parse_float_component(exponent);
    if !success then return 0, false;

    return compose_float(b, fraction, e), true;
}

// compose a float, as in (201, "0001", -2) -> 2.010001
// WARNING: produced by Claude. I don't feel 100% great about it, but it tested well enough for my uses, 
// and it works the way I wanted it to. thanks to whoever wrote the code that was stolen, if it clearly was. 
// I will put a repo link or license info here, or replace the procedure if somebody informs me (main@tracemyers.com).
compose_float :: (base: s64, fraction: string, exponent: s64) -> float64 {
    sign: s64 = ---;
    significand: u64 = ---;

    if base < 0 {
        sign = -1;
        significand = cast(u64) -base;
    } else {
        sign = 1;
        significand = cast(u64) base;
    }

    for fraction {
        significand = significand * 10 + cast(u64)(it - #char "0");
    }

    if significand == 0 {
        bits: u64 = 0;
        if sign < 0 then bits = cast(u64) 1 << 63;
        return (cast(*float64) *bits).*;
    }

    dec_exp := exponent - cast(s64) fraction.count;
    binary_exp: s64 = 0;

    // 10^n = 5^n * 2^n, so multiply/divide by 5 and track powers of 2 separately.
    if dec_exp > 0 {
        for 1..dec_exp {
            while significand & 0xE000_0000_0000_0000 != 0 {
                significand >>= 1;
                binary_exp += 1;
            }
            significand *= 5;
            binary_exp += 1;
        }
    } else if dec_exp < 0 {
        for 1..(-dec_exp) {
            while significand & 0x8000_0000_0000_0000 == 0 {
                significand <<= 1;
                binary_exp -= 1;
            }
            new_significand := significand / 5;
            remainder       := significand % 5;
            significand = ifx remainder >= 3 then new_significand + 1 else new_significand;
            binary_exp -= 1;
        }
    }

    // Normalize so bit 52 is the leading bit, rounding to nearest even.
    round_bit: u64 = 0;
    sticky: u64 = 0;
    while significand >= cast(u64) 1 << 53 {
        sticky |= round_bit;
        round_bit = significand & 1;
        significand >>= 1;
        binary_exp += 1;
    }
    if round_bit != 0 && (sticky != 0 || significand & 1 != 0) {
        significand += 1;
        if significand >= cast(u64) 1 << 53 {
            significand >>= 1;
            binary_exp += 1;
        }
    }
    while significand < cast(u64) 1 << 52 {
        significand <<= 1;
        binary_exp -= 1;
    }

    mantissa := significand & ((cast(u64) 1 << 52) - 1);
    biased_exp := binary_exp + 52 + 1023;

    if biased_exp >= 2047 {
        bits: u64 = cast(u64) 0x7FF << 52;
        if sign < 0 {
            bits |= cast(u64) 1 << 63;
        }
        return (cast(*float64) *bits).*;
    }
    if biased_exp <= 0 {
        bits: u64 = 0;
        if sign < 0 {
            bits = cast(u64) 1 << 63;
        }
        return (cast(*float64) *bits).*;
    }

    bits: u64 = 0;
    if sign < 0 {
        bits |= cast(u64) 1 << 63;
    }
    bits |= (cast(u64) biased_exp & 0x7FF) << 52;
    bits |= mantissa;

    return (cast(*float64) *bits).*;
}

is_norm_float :: inline (x: float) -> bool {
    return x >= 0 && x <= 1;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

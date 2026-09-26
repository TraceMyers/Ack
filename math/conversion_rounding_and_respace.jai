div_ceil :: inline (a: $Int_Type, b: Int_Type) -> Int_Type 
#modify {
    return Int_Type.(*Type_Info).type == .INTEGER;
} {
    engine_check(.HIGH, a >= 0 && b > 0);
    return ((a - 1) / b) + 1;
}

ceil_to_multiple :: inline (a: $Int_Type, b: Int_Type) -> Int_Type
#modify {
    return Int_Type.(*Type_Info).type == .INTEGER;
} {
    engine_checkl(.HIGH, a >= 0 && b > 0);
    return div_ceil(a, b) * b;
}

floor_to_multiple :: inline (a: $Int_Type, b: Int_Type) -> Int_Type
#modify {
    return Int_Type.(*Type_Info).type == .INTEGER;
} {
    engine_check(.HIGH, a >= 0 && b > 0);
    return (a / b) * b;
}

round :: (a: float64, $Int_Type := s32) -> Int_Type 
#modify {
    return Int_Type.(*Type_Info).type == .INTEGER;
} {
    if a < get_min_value(Int_Type).(float64) {
        return get_min_value(Int_Type);
    }
    rounded_toward_zero := a.(Int_Type);
    if a > 0 && rounded_toward_zero < 0 { // overflow on cast
        return get_max_value(Int_Type);
    }
    diff := a - cast(float64)rounded_toward_zero;
    if diff > 0.5 {
        return rounded_toward_zero + 1;
    } else if diff < -0.5 {
        return rounded_toward_zero - 1;
    } else {
        return rounded_toward_zero;
    }
}

// cast between int and normalized or non-normalized floats with optional rounding on float->int
alter_cast :: inline (number: $In_Type, $Out_Type: Type, $NORMALIZED_FLOAT := false, $ROUND_TO_INT := true) -> Out_Type
#modify {
    float_to_int := In_Type.(*Type_Info).type == .FLOAT && Out_Type.(*Type_Info).type == .INTEGER;
    int_to_float := In_Type.(*Type_Info).type == .INTEGER && Out_Type.(*Type_Info).type == .FLOAT;
    return float_to_int || int_to_float;
} {
    MIN_IN :: #run get_min_value(In_Type);
    MAX_IN :: #run get_max_value(In_Type);
    IN_DIFF :: MAX_IN - MIN_IN;
    MIN_OUT :: #run get_min_value(Out_Type);
    MAX_OUT :: #run get_max_value(Out_Type);
    OUT_DIFF :: MAX_OUT - MIN_OUT;
    IN_IS_FLOAT :: #run type_info(In_Type).type == .FLOAT;
    OUT_IS_FLOAT :: #run type_info(Out_Type).type == .FLOAT;
    FLOAT_TO_INT :: IN_IS_FLOAT && !OUT_IS_FLOAT;
    INT_TO_FLOAT :: !IN_IS_FLOAT && OUT_IS_FLOAT;

    #if NORMALIZED_FLOAT {
        #if FLOAT_TO_INT {
            #if ROUND_TO_INT {
                return round(MIN_OUT.(float64) + (MAX_OUT.(float64) - MIN_OUT.(float64)) * xx number, Out_Type);
            } else {
                return xx (MIN_OUT.(float64) + (MAX_OUT.(float64) - MIN_OUT.(float64)) * xx number);
            }
        } else #if INT_TO_FLOAT {
            return xx clamp((number.(float64) - MIN_IN.(float64)) / IN_DIFF.(float64), 0.0, 1.0);
        }
    } else {
        if number < MIN_OUT {
            return MIN_OUT;
        } else if number > MAX_OUT {
            return MAX_OUT;
        } else {
            #if FLOAT_TO_INT && ROUND_TO_INT {
                return round(number, Out_Type);
            } 
            return xx number;
        }
    }
    return xx 0;
}

// transform x from space in_range to space out_range
// e.g. respace(time, {min_time, max_time}, {0, 1}); outputs normalized time
respace :: (x: float32, in_range: Vector2, out_range: Vector2, $do_clamp := true) -> float32 {
    norm_val: float32 = ---;
    if in_range.y > in_range.x {
        in_range_width := in_range.y - in_range.x;
        #if do_clamp {
            norm_val = (clamp(x, in_range.x, in_range.y) - in_range.x) / in_range_width;
        } else {
            norm_val = (x - in_range.x) / in_range_width;
        }
    } else {
        in_range_width := in_range.x - in_range.y;
        #if do_clamp {
            norm_val = 1.0 - (clamp(x, in_range.y, in_range.x) - in_range.y) / in_range_width;
        } else {
            norm_val = 1.0 - (x - in_range.y) / in_range_width;
        }
    }
    out_range_width := out_range.y - out_range.x;
    return out_range.x + out_range_width * norm_val;
}

align_up :: inline (value: int, align: int) -> int {
    return (value + align - 1) & ~(align - 1);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

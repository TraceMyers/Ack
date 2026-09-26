linear_compress_float :: inline (x: float, $in_min: float, $in_max: float, $out_type := u16, $do_clamp := true) -> out_type {
    #run assert(out_type.(*Type_Info).type == .INTEGER);
    INV_RANGE :: 1.0 / (in_max - in_min);
    INT_TYPE_MIN :: get_min_value(out_type).(float);
    INT_TYPE_MAX :: get_max_value(out_type).(float);
    INT_TYPE_RANGE :: INT_TYPE_MAX - INT_TYPE_MIN;
    #if do_clamp {
        xc := clamp(x, in_min, in_max);
    } else {
        xc := x;
    }
    min_diff := xc - in_min;
    norm := min_diff * INV_RANGE;
    return round(INT_TYPE_MIN + INT_TYPE_RANGE * norm, out_type);
}

linear_decompress_float :: inline (u: $in_type, $min_value: float, $max_value: float) -> float 
#modify {
    return in_type.(*Type_Info).type == .INTEGER;
} {
    INT_TYPE_MIN :: get_min_value(in_type).(float);
    INT_TYPE_MAX :: get_max_value(in_type).(float);
    INT_TYPE_RANGE :: INT_TYPE_MAX - INT_TYPE_MIN;
    INV_INT_TYPE_RANGE :: 1.0 / INT_TYPE_RANGE.(float);
    FLOAT_RANGE :: #run (max_value - min_value);
    norm := (u.(float) - INT_TYPE_MIN) * INV_INT_RANGE;
    return min_value + norm * FLOAT_RANGE;
}

linear_compress_float_8bit          :: #bake_arguments linear_compress_float(out_type=u8);
linear_decompress_float_8bit :: inline (u: $in_type, $min_value: float, $max_value: float) -> float 
#modify {
    return in_type == u8;
} {
    return linear_decompress_float(u, min_value, max_value);
}

linear_compress_float_16bit         :: #bake_arguments linear_compress_float(out_type=u16);
linear_decompress_float_16bit :: inline (u: $in_type, $min_value: float, $max_value: float) -> float 
#modify {
    return in_type == u16;
} {
    return linear_decompress_float(u, min_value, max_value);
}

linear_compress_float_21bit :: inline (x: float, $min_value: float, $max_value: float, $do_clamp := true) -> u64 {
    INV_RANGE :: 1.0 / (max_value - min_value);
    #if do_clamp {
        xc := clamp(x, min_value, max_value);
    } else {
        xc := x;
    }
    min_diff := xc - min_value;
    norm := min_diff * INV_RANGE;
    out_val := round(_21_BITS_MAX.(float) * norm, u64);
    return out_val;
}

linear_decompress_float_21bit :: inline (u: u64, $min_value: float, $max_value: float) -> float {
    FLOAT_RANGE :: #run (max_value - min_value);
    norm := u.(float) * INV_21_BITS_MAX;
    return min_value + norm * FLOAT_RANGE;
}

linear_compress_vector3 :: inline (v: Vector3, $min_value: float, $max_value: float) -> u64 {
    x := linear_compress_float_21bit(v.x, min_value, max_value);
    y := linear_compress_float_21bit(v.y, min_value, max_value);
    z := linear_compress_float_21bit(v.z, min_value, max_value);
    return (z << 42) | (y << 21) | (x << 0);
}

linear_decompress_vector3 :: inline (v: u64, $min_value: float, $max_value: float) -> Vector3 {
    x := (v >>  0) & 0x1fffff;
    y := (v >> 21) & 0x1fffff;
    z := (v >> 42) & 0x1fffff;
    return .{
        linear_decompress_float_21bit(x, min_value, max_value),
        linear_decompress_float_21bit(y, min_value, max_value),
        linear_decompress_float_21bit(z, min_value, max_value),
    };
}

linear_compress_norm_vector3        :: #bake_arguments linear_compress_vector3(min_value=-1, max_value=1);
linear_decompress_norm_vector3      :: #bake_arguments linear_decompress_vector3(min_value=-1, max_value=1);

#scope_file

_21_BITS_MAX :: (((1).(u64) << 21)-1);
INV_21_BITS_MAX : float : ((1.0).(float64) / _21_BITS_MAX.(float64)).(float);

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

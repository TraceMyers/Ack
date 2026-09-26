log_with_base :: (x: float, $base: float) -> float {
    INV_LOG_OF_BASE :: #run 1.0 / log(base);
    return log(abs(x)) * INV_LOG_OF_BASE;
}

// small abs max error (~0.0008) and ~15% faster when using cephes.jai acos() as the reference. thanks to Vasili at https://math.stackexchange.com/questions/4983100/finding-arcsin-or-arccos-from-other-mathmatical-functions
acos_approx :: inline (x: float) -> float {
    if x < 0 {
        x = max(-x, -1);
        return PI - sqrt(1-x) * (1.5707963267948966 - 0.20347053865798365 * x + 0.046887774236182234 * x * x).(float32);
    } else {
        x = min(x, 1);
        return sqrt(1-x) * (1.5707963267948966 - 0.20347053865798365 * x + 0.046887774236182234 * x * x).(float32);
    }
}

// don't use this procedure if the input value is too large! makes large error.
// recommended max ~4000
mod_two_pi :: inline (x: float) -> float {
    engine_check(.HIGH, x >= 0);

    // fixed point division, from before cpus could divide. conveniently gives the remainder as a byproduct.

    x_fixed := (x * FIXED_ONE).(u64);
    prod := x_fixed * RECIP_TWO_PI_FIXED_32;
    quotient := prod >> 32;

    remainder_fixed := x_fixed - (quotient * TWO_PI_FIXED);
    if remainder_fixed < 0 {
        remainder_fixed += TWO_PI_FIXED;
    } else if remainder_fixed >= TWO_PI_FIXED {
        remainder_fixed -= TWO_PI_FIXED;
    }

    out_val := remainder_fixed.(float) * INV_FIXED_ONE;
    return out_val;
}

// gives value and sign in [-pi/2, pi/2] for sin_cos
convert_to_fast_trig_range :: inline (x: float32) -> x1: float32, sin_sign: float32, cos_sign: float32 {
    pos_x, sin_sign, cos_sign : float32 = ---;
    if sign(x) == 1.0 {
        pos_x = x;
        sin_sign = 1.0;
        cos_sign = 1.0;
    } else {
        pos_x = x * -1.0;
        sin_sign = sign(x);
        cos_sign = -sin_sign;
    }

    // get value in [0, 2pi)
    x1 := mod_two_pi(pos_x);
    // map to [-pi/2, pi/2)
    if x1 > (3 * PI * 0.5) {
        x1 -= 2.0 * PI;
    } else if x1 > PI {
        x1 = (PI * 0.5 - (x1 - (3.0 * PI * 0.5)));
        sin_sign *= -1.0;
    } else if x1 > PI * 0.5 {
        x1 = PI - x1;    
        cos_sign *= -1.0;
    }

    return x1, sin_sign, cos_sign;
}

// test shows ~25-50% reduction in time (maybe depending on branch misses) from using sin and cos separately. inputs are recommended to stay within domain (-5000,5000) to keep max error below 0.035 and median error ~0.0001, due to limitations with mod_two_pi()
// todo: bring the error down
sin_cos :: inline (x: float32) -> sin_x: float32, cos_x: float32 {
    if x == 0 {
        return 0, 1;
    }
    x1, sin_sign, cos_sign := convert_to_fast_trig_range(x); 
    x2 := x1 * x1;
	pos_val_sin := (((((-0.000000023889859 * x2 + 0.0000027525562) * x2 - 0.00019840874) * x2 + 0.0083333310) * x2 - 0.16666667) * x2 + 1.0) * x1;
	pos_val_cos := ((((-0.00000026051615 * x2 + 0.000024760495) * x2 - 0.0013888378) * x2 + 0.041666638) * x2 - 0.5) * x2 + 1.0;
    return pos_val_sin * sin_sign, pos_val_cos * cos_sign;
}

// convenience wrapper for exp_approx_with_positive_x.
exp_approx :: inline (x: float) -> float {
    if x < 0 {
        return 1.0 / exp_approx_with_positive_x(-x);
    } else {
        return exp_approx_with_positive_x(x);
    }
}

// linearization of e^x between each e(x) = 2^(x/ln(2))
// x must be positive for this to work
exp_approx_with_positive_x :: inline (x: float) -> float {
    ONE_OVER_LOG_2 :: #run 1.0 / log(2.0);

    power := x * ONE_OVER_LOG_2;
    power_int := cast(int) power;
    power_remainder := power - cast(float) power_int;

    value_lower := 1 << power_int;
    value_upper := 1 << (power_int + 1);
    
    return value_lower + cast(float) (value_upper - value_lower) * power_remainder;
}

#scope_module

// precalculated fixed point math values for sin_cos
FIXED_SHIFT : u64 : 14; // seems to maximize precision over the whole sin_cos process
FIXED_ONE : u64 : 1 << FIXED_SHIFT;
INV_FIXED_ONE :: 1.0 / FIXED_ONE.(float);
TWO_PI_FIXED : u64 : xx (PI * 2.0 * FIXED_ONE.(float));
RECIP_TWO_PI_FIXED_32 :: (1 << 32) / TWO_PI_FIXED;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

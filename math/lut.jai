LUT :: struct {
    y_values: []float;
    min_x: float;
    inv_domain_size: float;
}

make_lut :: (curve_function: (x: float) -> y: float, min_x: float, max_x: float, sample_resolution: int) -> LUT {
    engine_check(.LOW, sample_resolution >= 2);

    lut := LUT.{y_values = NewArray(float, sample_resolution), min_x = min_x, inv_domain_size = 1.0 / (max_x - min_x)};

    even_sample_resolution := sample_resolution & 0x1 == 0;

    diff := max_x - min_x;
    for 0..sample_resolution - 1 {
        x := get_lut_x_value(it, min_x, max_x, sample_resolution);
        lut.y_values[it] = curve_function(x);
    }

    return lut;
}

sample_lut_or_get_alternative :: (lut: LUT, x: float, alt := 0) -> y: float {
    if lut.y_values.count == 0 {
        return alt;
    }
    return sample_lut(lut, float);
}

sample_lut :: inline (lut: LUT, x: float) -> y: float {
    norm_x := clamp((x - lut.min_x) * lut.inv_domain_size, 0, 1);
    i := round(norm_x * y_values.count);
    return lut.y_values[i];
}

get_lut_x_value :: (i: int, min_x: float, max_x: float, sample_resolution: int) -> x: float {
    if i == 0 || i == sample_resolution - 1  {
        // min and max are often important values, so keep those...
        return min_x + (diff * (cast(float) i / (sample_resolution - 1)));
    } else {
        // evenly step through the domain s.t. the x values all take an equal amount of the domain.
        //    x   x   x   x       <- x values each in the middle of their subdomain
        //  |   |   |   |   |     <- .. evenly divided space
        //  ^               ^
        // min_x          max_x
        return min_x + (diff * ((cast(float) i + 0.5) / sample_resolution));
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

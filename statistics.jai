calculate_sum :: (array: []$T) -> T {
    sum: T = 0;
    for value : array {
        sum += value;
    }
    return sum;
}

calculate_mean :: (array: []$T) -> float64, success: bool {
    if array.count <= 0 {
        return 0, false;
    }
    sum := inline calculate_sum(array);
    return sum / cast(float64) array.count, true;
}

calculate_min :: (array: []$T) -> T, success: bool {
    if array.count <= 0 {
        return 0, false;
    }
    min_value := array[0];
    if array.count > 1 then for 1..array.count-1 {
        min_value = min(min_value, array[it]);
    }
    return min_value, true;
}

calculate_max :: (array: []$T) -> T, success: bool {
    if array.count <= 0 {
        return 0, false;
    }
    max_value := array[0];
    if array.count > 1 then for 1..array.count-1 {
        max_value = max(max_value, array[it]);
    }
    return max_value, true;
}

calculate_median :: (in_array: []$T, sort_in_place: bool) -> float64, success: bool {
    if in_array.count == 0 {
        return 0, false;
    } else if in_array.count == 1 {
        return in_array[0], true;
    }

    array := ifx sort_in_place then in_array else array_copy(in_array,, temp);
    quick_sort(array, a, b => a - b);

    half_count := array.count / 2;
    if array.count % 2 == 0 {
        return cast(float64) (array[half_count] + array[half_count-1]) * 0.5, true;
    } else {
        return cast(float64) array[half_count], true;
    }
}

calculate_mode :: (array: []$T) -> T, success: bool {
    if array.count == 0 {
        return 0, false;
    } else if array.count <= 2 {
        return array[0], true;
    }
    
    // comptime and init table settings are chosen to avoid reallocation,
    // taking into account the Table reallocation strategy.
    table: Table(T, u32, LOAD_FACTOR_PERCENT=80);
    init(*table, round(ceil(array.count * (101.0 / 80.0))),, temp);

    mode: *T;
    mode_count: s32;

    for *item : array {
        count_ptr := find_or_add(*table, item.*);
        count_ptr.* += 1;

        if count_ptr.* > mode_count {
            mode = item;
            mode_count = count_ptr.*;
        }
    }

    engine_check(.LOW, mode != null);
    return mode.*, true;
}

calculate_mean_and_sum_of_square_error :: (array: []$T) -> mean: float64, sse: float64 {
    mean := calculate_mean(array);
    sse: float64;
    for value : array {
        sse += square(value - mean);
    }
    return mean, sse;
}

calculate_mean_and_variance :: (array: []$T, sample_variance := true) -> mean: float64, variance: float64 {
    sample_size := ifx sample_variance then array.count - 1 else array.count;
    if sample_size <= 1 {
        return calculate_mean(array), 0;
    }
    mean, sse := calculate_mean_and_sum_of_square_error(array);
    return mean, sse / cast(float64) sample_size;
}

calculate_mean_and_standard_deviation :: (array: []$T, sample_sd := true) -> mean: float64, sd: float64 {
    mean, variance := calculate_mean_and_variance(array, sample_sd);
    if variance == 0 {
        return mean, 0;
    }
    return mean, sqrt(variance);
}

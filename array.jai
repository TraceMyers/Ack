copy_items :: inline (dest: *$T, src: *T, count: s64) {
    memcpy(dest, src, count * size_of(T));
}

array_init :: inline (array: []$T) {
    init_range(array.data, 0, array.count);
}

make_dynamic_array :: inline ($T: Type, reserve_count := 0) -> [..]T {
    array: [..]T;
    array.allocator = context.allocator;
    array_reserve(*array, reserve_count);
    return array;
}

make_static_array :: inline ($T: Type, count := 0) -> []T {
    return NewArray(count, T);
}

array_element_index :: inline (array: []T, item: *$T) -> s64 {
    index := item - array.data;
    engine_check(.LOW, index >= 0 && index < array.count);
    return index;
}

arrays_equal :: inline (a: []$T, b: []T) -> bool {
    if a.count != b.count return false;
    return memcmp(a.data, b.data, a.count) == 0;
}

array_append :: (a: *[..]$T, b: []T) {
    if b.count == 0 then return;
    prev_count := a.count;
    array_resize(a, a.count + b.count);
    copy_items(a.data + prev_count, b.data, b.count);
}

array_concatenate :: (arrays: ..[]$T) -> []T {
    out_count := 0;
    for arrays {
        out_count += it.count;
    }

    if out_count <= 0 {
        return .[];
    }

    out_array := make_static_array(out_count);
    dst_index := 0;

    for arrays {
        copy_size := it.count * size_of(T);
        memcpy(out_array.data + dst_index, it.data, copy_size);
        dst_index += it.count;
    }
    engine_check(.LOW, dst_index == out_array.count);

    return out_array;
}

make_local_static_array :: inline ($T: Type, $max: int, count := 0, $id := "") -> []T #expand {
    engine_check(.LOW, count <= max);
    array_name :: #run tprint("`_local_static_array_storage_%", id);
    #insert #run tprint("%: [max]T;", array_name);
    array: []T;
    array.data = #insert #run tprint("%.data;", array_name);
    array.count = count;
    return array;
}

static_array_add :: inline (array: *[]$T, item: T, upper_bound: s64) -> bool {
    if array.count >= upper_bound {
        return false;
    } else {
        array.count += 1;
        array.data[array.count-1] = item;
        return true;
    }
}

copy_range_inside_array :: (array: *[]$T, dst: s64, src: s64, count: s64) {
    engine_check(.LOW, count > 0 && dst != src);
    diff := dst - src;
    abs_diff := abs(diff);
    if abs_diff < count {
        if diff < 0 then for 0..count-1 {
            array[dst+it] = array[src+it];
        } else for < 0..count-1 {
            array[dst+it] = array[src+it];
        }
    } else {
        copy_items(array.data + dst, array.data + src, count);
    }
}

array_shrink :: (array: *[..]$T, remove_free_proportion := 0.75) {
    engine_check(.LOW, remove_free_proportion >= 0 && remove_free_proportion <= 1);

    maybe_new_allocation: *T;
    keep_allocated := array.allocated;

    if array.count > 0 {
        keep_extra := round(cast(float) (array.allocated - array.count) * (1-remove_free_proportion));
        keep_allocated = array.count + keep_extra;

        if keep_allocated == array.allocated {
            maybe_new_allocation = array.data;
        } else {
            if keep_allocated > 0 {
                maybe_new_allocation = alloc(keep_allocated * size_of(T),, array.allocator);
                memcpy(maybe_new_allocation, array.data, keep_allocated * size_of(T));
            }
            array_free(array.*,,array.allocator);
        }
    } else {
        array_free(array.*,,array.allocator);
        keep_allocated = 0;
    }

    array.data = maybe_new_allocation;
    array.allocated = keep_allocated;
}

array_shrink_if_small_enough :: (array: *[..]$T, realloc_if_using_leq_proportion := 0.35, remove_free_proportion := 0.75, minimum_allocated := 8) -> bool {
    if array.allocated == 0 {
        engine_check(.LOW, array.data == null);
        engine_check(.LOW, array.count == 0);
        return false;
    }

    using_proportion := array.count.(float) / array.allocated.(float);
    if using_proportion <= realloc_if_using_leq_proportion {
        if minimum_allocated >= array.allocated {
            return false;
        }
        min_proportion := minimum_allocated.(float) / array.allocated.(float);
        remove_proportion := min(1 - min_proportion, remove_free_proportion);
        prev_allocated := array.allocated;
        array_shrink(array, remove_proportion);
        engine_check(.LOW, prev_allocated >= array.allocated);
        return prev_allocated != array.allocated;
    }

    return false;
}

#scope_module

// copied from module Basic in /Array
init_range :: (ptr: *$T, begin: s64, end: s64) {
    ini :: initializer_of(T);
    #if ini {
        for begin..end-1  inline ini(ptr + it);  // Really this can be one ini followed by a bunch of memcpy. For long arrays we could power-of-two double the copy out, etc.
    } else {
        count := end - begin;
        if count <= 0  return;

        // Fast path for init to zero.
        // In the case that we are shrinking an array, count will be negative.
        memset(ptr + begin, 0, count * size_of(T));
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

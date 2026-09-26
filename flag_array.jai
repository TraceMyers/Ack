// convenient for making one big flag set that expands or might expand beyond 64 flags.
// uses an enum as an indexer to the bits in an array.

Flag_Array_Indexer :: struct {
    index: s16;
    bit: s16;
}

Flag_Array :: struct($Enum_Type: Type) {
    FLAG_COUNT :: #run enum_highest_value(Enum_Type) + 1;
    flag_sets: [#run div_ceil(FLAG_COUNT, 8)]u8;
}

convert_to_lfa_indexer :: inline (int_val: s64) -> Flag_Array_Indexer {
    return .{xx ((int_val & ~0x07) >> 3), xx (int_val & 0x07)};
}

is_set :: inline (arr: *Flag_Array($T), enum_val: T) -> bool {
    indexer := convert_to_lfa_indexer(xx enum_val);
    return (arr.flag_sets[indexer.index] & ((1).(u8) << indexer.bit)) != 0;
}

set :: inline (arr: *Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] |= ((1).(u8) << indexer.bit);
}

clear :: inline (arr: *Flag_Array($T), enum_val: T) {
    indexer := convert_to_lfa_indexer(xx enum_val);
    arr.flag_sets[indexer.index] &= ~((1).(u8) << indexer.bit);
}

set :: inline (arr: *Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        set(arr, it);
    }
}

clear :: inline (arr: *Flag_Array($T), enum_vals: []T) {
    for enum_vals {
        clear(arr, it);
    }
}

are_all_set :: inline (array: *Flag_Array($T), enum_vals: []T) -> bool {
    for enum_vals {
        if !is_set(array, it) {
            return false;
        }
    }
    return true;
}

are_any_set :: inline (array: *Flag_Array($T), enum_vals: []T) -> bool {
    any_set := false;
    for enum_vals {
        any_set |= is_set(array, it);
    }
    return any_set;
}

are_any_set :: inline (array: *Flag_Array) -> bool {
    for array.flag_sets {
        if it != 0 {
            return true;
        }
    }
    return false;
}

clear_all :: inline (arr: *Flag_Array($T)) {
    memset(arr.flag_sets.data, 0x00, arr.flag_sets.count);
}

set_all :: inline (arr: *Flag_Array($T)) {
    memset(arr.flag_sets.data, 0xff, arr.flag_sets.count);
}

make_flag_array :: (enum_vals: ..$T) -> Flag_Array(T) {
    flags: Flag_Array(T);
    for val : enum_vals {
        set(*flags, val);
    }
    return flags;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

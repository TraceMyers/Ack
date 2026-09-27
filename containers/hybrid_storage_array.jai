// an internal/external storage hybrid array wherein data is stored on-struct until
// it's too big. you can preset the allocator since that is not overwritten by 
// internal data (unless internal buffer overflow).

Hybrid_Storage_Array :: struct($T: Type) {
    allocation: Hybrid_Storage_Array_Allocation = .INTERNAL;
    internal_count: s32;
    external: [..]T;
    #overlay(external) internal_items: [INTERNAL_COUNT]T;

    INTERNAL_COUNT :: #run size_of(Resize_Array_Partial) / size_of(T);
}

data :: inline (using array: *Hybrid_Storage_Array($T)) -> *T {
    return ifx allocation == .INTERNAL then internal_items.data else external.data;
}

count :: inline (using array: *Hybrid_Storage_Array) -> int {
    return ifx allocation == .INTERNAL then internal_count else external.count;
}

array_view :: inline (using array: *Hybrid_Storage_Array($T)) -> []T {
    slice: []T = ---;
    if allocation == .INTERNAL {
        slice.data  = internal_items.data;
        slice.count = internal_count;
    } else {
        slice = external;
    }
    return slice;
}

operator *[] :: (using array: *Hybrid_Storage_Array($T), i: int) -> *T {
    return ifx allocation == .INTERNAL then internal_items[i] else external[i];
}

operator []= :: (using array: *Hybrid_Storage_Array($T), i: int, x: T) {
    if allocation == .INTERNAL {
        engine_check(.LOW, i < internal_count);
        internal_items[i] = x;
    } else {
        external[i] = x;
    }
}

// make sure the context has the right allocator set when calling
array_add :: (using array: *Hybrid_Storage_Array($T), item: T) {
    if allocation == .INTERNAL {
        if internal_count < internal_items.count {
            internal_items[internal_count] = item;
            internal_count += 1;
            return;
        }

        engine_check(.LOW, internal_count == internal_items.count);
        move_to_external_allocation(array, internal_items.count * 2);
    } 

    array_add(*external, item);
}

array_unordered_remove_by_value :: (using array: *Hybrid_Storage_Array($T), item: T) {
    if allocation == .EXTERNAL {
        array_unordered_remove_by_value(*external, item);   
        if external.count <= #run Hybrid_Storage_Array(T).internal_items.count / 2 {
            move_to_internal_allocation(array);
        }
    } else {
        if internal_count > 0 then for 0..internal_count-1 {
            if internal_items[it] == item {
                if it != internal_count - 1 {
                    internal_items[it] = internal_items[internal_count-1];
                }
                internal_count -= 1;
                return;
            }
        }
    }
}

array_reserve :: (array: *Hybrid_Storage_Array($T), reserve_count: int) {
    if allocation == .EXTERNAL {
        if reserve_count > external.allocated {
            array_reserve(*external, reserve_count);
        }
    } else {
        if reserve_count > internal_items.count {
            move_to_external_allocation(array, reserve_count);            
        }
    }
}

array_reset :: hybrid_array_reset;

hybrid_array_reset :: (using array: *Hybrid_Storage_Array) {
    if allocation == .EXTERNAL {
        free(external.data,, external.allocator);
    }
    array.* = .{};
}

for_expansion :: (array: *Hybrid_Storage_Array($T), body: Code, flags: For_Flags) #expand {
    items := array_view(array);

    for item, ind : items {
        `it := item;
        `it_index := ind;

        #insert body;
    }
}

Hybrid_Storage_Array_Allocation :: enum u32 {
    EXTERNAL;
    INTERNAL;
}

#scope_module

Resize_Array_Partial :: struct {
    count: s64;
    data: *void;
    allocated: s64;
}

move_to_internal_allocation :: inline (using array: *Hybrid_Storage_Array) {
    engine_check(.LOW, external.count <= internal_items.count);

    allocation = .INTERNAL;

    data := external.data;
    internal_count = xx external.count;
    if internal_count > 0 {
        memcpy(internal_items.data, data, internal_count * size_of(T));
    }

    free(data,, external.allocator);
}

move_to_external_allocation :: inline (using array: *Hybrid_Storage_Array, reserve_count: int) {
    allocation = .EXTERNAL;

    external_temp: [..]T;
    external_temp.allocator = context.allocator;

    array_resize(*external_temp, reserve_count);
    external_temp.count = internal_count;
    if internal_count > 0 {
        memcpy(external_temp.data, internal_items.data, internal_count * size_of(T));
    }

    external = external_temp;
}

Pool_Resize_Behavior :: enum {
    DEFAULT;
    ALLOW;
    DISALLOW;
}

Pool :: struct($Item_Type: Type) {
    items: [..]Item_Type;
    in_use: Bit_Array;
    generations: [..]u32;
    top := -1;
    shrink_to_min : s32 = 0;
    allow_grow_default := true;
    allow_shrink_default := true;
    track_generation := false;
}

pool_init :: (pool: *Pool, cap: s64, lock_allocation := false, do_track_generation := false) {
    pool.* = {};
    pool_set_allocator(pool, context.allocator);
    pool_set_capacity(pool, cap);
    if lock_allocation {
        pool_lock_allocation(pool);
    }
    pool.track_generation = do_track_generation;
}

pool_set_capacity :: (using pool: *Pool($T), cap: s64) {
    array_resize(*items, cap);
    resize_in_use(pool, cap);
}

pool_set_allocator :: (using pool: *Pool($T), allocator: Allocator) {
    items.allocator = allocator;
    in_use.allocator = allocator; 
}

pool_lock_allocation :: (using pool: *Pool($T)) {
    pool_set_allocator(pool, no_allocator);
    allow_grow_default = false;
    allow_shrink_default = false;
}

pool_reset :: (using pool: *Pool($T), deinit_item_proc: (*T) = null) {
    if deinit_item_proc != null {
        for *(pool.*) {
            deinit_item_proc(it);
        }
    }
    array_reset(*items);
    resize_in_use(pool, 0);
    top = -1;
}

pool_reset_keeping_memory :: (using pool: *Pool($T), deinit_item_proc: (*T) = null) {
    if deinit_item_proc != null {
        for *(pool.*) {
            deinit_item_proc(it);
        }
    }
    clear_all_bits(*in_use);
    top = -1;
}

pool_borrow :: (using pool: *Pool($T), init_item_proc: (*T) = null, grow_behavior := Pool_Resize_Behavior.DEFAULT) -> s64 {
    index: s64 = -1;

    if items.data != null then for :only_cleared_bits in_use {
        index = it_index;
        break;
    }

    if index != -1 {
        set_bit(*in_use, index);
        if index > top then top = index;
        if top >= items.count {
            engine_check(.LOW, top < items.allocated);
            items.count = top + 1;
        }

        if init_item_proc then init_item_proc(*items[index]);
        increment_item_generation(pool, index);
        return index;
    }

    do_allow_grow := ifx grow_behavior == .DEFAULT then allow_grow_default else grow_behavior == .ALLOW;
    if !do_allow_grow {
        return -1;
    }

    index = items.count;
    top = items.count;

    new_item_count := max(items.count * 2, 8);
    pool_set_capacity(pool, new_item_count);
    set_bit(*in_use, index);

    if init_item_proc then init_item_proc(*items[index]);
    increment_item_generation(pool, index);
    return index;
}

pool_return :: inline (pool: *Pool($T), item: *T, deinit_item_proc: (*T) = null, shrink_behavior := Pool_Resize_Behavior.DEFAULT) {
    pool_return(pool, pool_get_index(pool, item), deinit_item_proc, shrink_behavior);
}

pool_return :: (using pool: *Pool($T), i: s64, deinit_item_proc: (*T) = null, shrink_behavior := Pool_Resize_Behavior.DEFAULT, reinitialize_data := true) {
    if deinit_item_proc then deinit_item_proc(*items[i]);

    clear_bit(*in_use, i);
    increment_item_generation(pool, i);

    if reinitialize_data {
        ini :: initializer_of(T);
        #if ini {
            ini(*items[i]);
        } else #if type_info(T).type == .STRUCT {
            items[i] = {};
        } else {
            items[i] = xx 0;
        }
    }

    if i == top {
        top = -1;
        for < :only_set_bits in_use {
            top = it_index;
            break;
        }

        do_allow_shrink := ifx shrink_behavior == .DEFAULT 
            then allow_shrink_default 
            else shrink_behavior == .ALLOW;

        if do_allow_shrink && items.count > shrink_to_min {
            required_count := top + 1;
            required_count = max(required_count, shrink_to_min);
            if required_count >= items.count then return;

            // div by 2 repeatedly until we find the threshold we're under
            test_threshold := items.count >> 1;
            while required_count < test_threshold {
                test_threshold >>= 1;
            }

            // only shrink by up to half the space we could shrink, to leave room for incoming adds
            new_cap := max(test_threshold << 1, required_count);
            if new_cap < items.count {
                pool_set_capacity(pool, new_cap);
            }
        }
    }
}

operator *[] :: inline (using pool: *Pool($T), i: s64) -> *T {
    return pool_get(pool, i);
}

pool_get :: inline (using pool: *Pool($T), i: s64) -> *T {
    engine_check(.LOW, in_use[i]);
    return *items[i];
}

pool_find :: (using pool: *Pool($T1), user_data: $T2, compare_proc: (*T1, T2) -> bool) -> s64 {
    i := -1;
    for :only_set_bits in_use {
        if compare_proc(*items[it_index], user_data) then return it_index;
    }
    return -1;
}

pool_get_index :: (using pool: *Pool($T), item: *T) -> s64 {
    i := item - items.data;
    if i < 0 || i > items.count {
        return -1;
    }
    return i;
}

pool_is_empty :: inline (using pool: *Pool($T)) -> bool {
    return top == -1;
}

// todo: delete? meh
is_pool_item_in_use :: inline (using pool: *Pool($T), i: s64) -> bool {
    return in_use[i];
}

// for my_pool { ... }
for_expansion :: (pool: Pool($T), body: Code, flags: For_Flags) #expand {
    if pool.top >= 0 {
        for <=((flags & .REVERSE) != 0) item_index : 0..pool.top {
            `it_index := item_index;
            if !is_pool_item_in_use(*pool, item_index) {
                continue;
            }
            #if (flags & .POINTER) {
                `it := *pool.items[item_index];
            } else {
                `it := pool.items[item_index];
            }
            #insert body;
        }
    }
}

pool_get_item_generation :: (using pool: *Pool, index: s64) -> u32 {
    if !track_generation {
        return 0;
    }
    return generations[index];
}

#scope_module

resize_in_use :: (using pool: *Pool($T), new_count: s64) {
    if new_count == 0 {
        deinit(*in_use);
        in_use.count = 0;
        in_use.slots.count = 0;
    } else if new_count > in_use.count {
        old_allocation := in_use.slots.data;
        old_allocation_size := in_use.slots.count * BIT_ARRAY_SLOT_SIZE;
        in_use.count = 0;
        in_use.slots.count = 0;
        in_use.slots.data = null;
        init_bit_array(*in_use, new_count);
        if old_allocation_size > 0 {
            new_allocation_size := in_use.slots.count * BIT_ARRAY_SLOT_SIZE;
            memcpy(in_use.slots.data, old_allocation, old_allocation_size);
            free(old_allocation,, in_use.allocator);
        }
    }
}

increment_item_generation :: inline (using pool: *Pool, index: s64) {
    if !track_generation {
        return;
    }
    if generations.count <= index {
        array_resize(*generations, index + 1);
    }
    generations[index] += 1;
}

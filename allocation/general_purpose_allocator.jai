// two chained Allocator_64s. small handles up to 1KB in 64KB pages taken from large, large handles
// up to 64KB in 4MB pages taken from data_allocator, and anything bigger goes to data_allocator.
//
// to scope everything to a heap, start this under push_allocator(heap). see make_heap.

General_Purpose_Allocator :: struct {
    using #as base: Allocator;
    books_allocator: Allocator;
    // pages of large, and allocations over 64KB
    data_allocator:  Allocator;
    small: Allocator_64;
    large: Allocator_64;
}

general_purpose_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*General_Purpose_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        if old_memory == null then return null;
        #through;
    case .ALLOCATE;
        #through;
    case .RESIZE;
        #through;
    case .IS_THIS_YOURS;
        return allocator_64_proc(mode, size, old_size, old_memory, *allocator.small);
    case .STARTUP;
        return general_purpose_allocator_startup(allocator);
    case .SHUTDOWN;
        general_purpose_allocator_shutdown(allocator);
        return null;
    case .THREAD_START;
        #through;
    case .THREAD_STOP;
        engine_check(false, "multithreaded access not supported");
        return null;
    case .CREATE_HEAP;
        #through;
    case .DESTROY_HEAP;
        engine_check(false, "creating and destoying heaps not supported");
        return null;
    case .CAPS;
        return xx (Allocator_Caps.FREE | .ACTUALLY_RESIZE | .IS_THIS_YOURS);
    }
}

general_purpose_allocator_startup :: (using allocator: *General_Purpose_Allocator) -> *void {
    allocator.base = {proc=general_purpose_allocator_proc, data=allocator};

    // the sub-allocators may start while this allocator is context.allocator, so resolve defaults first
    if data_allocator.proc == null {
        data_allocator = context.allocator;
    }
    if books_allocator.proc == null {
        books_allocator = context.allocator;
    }

    large.slot_size       = 1024;
    large.books_allocator = books_allocator;
    large.data_allocator  = data_allocator;
    allocator_64_startup(*large);

    small.slot_size       = 16;
    small.books_allocator = books_allocator;
    small.data_allocator  = large.base;
    allocator_64_startup(*small);
    return null;
}

general_purpose_allocator_shutdown :: (allocator: *General_Purpose_Allocator) {
    allocator_64_shutdown(*allocator.small);
    allocator_64_shutdown(*allocator.large);
    allocator.* = {};
}

#scope_export

general_purpose_allocator_test :: () -> bool {
    a: General_Purpose_Allocator;
    a.data_allocator  = context.default_allocator;
    a.books_allocator = context.default_allocator;
    general_purpose_allocator_startup(*a);
    defer general_purpose_allocator_shutdown(*a);

    Live :: struct {
        memory: *u8;
        size:   s64;
        stamp:  u8;
    }
    live: [..]Live;
    live.allocator = temp;

    stamp_is_intact :: (l: Live, size: s64) -> bool {
        for 0..size-1 {
            if l.memory[it] != l.stamp then return false;
        }
        return true;
    }

    // sizes for the small and large grids and the fallback, with random resizes and frees mixed in
    for 0..4_999 {
        max_size := 1024;
        if it % 16 >= 12 then max_size = 64 * 1024;
        if it % 16 == 15 then max_size = 256 * 1024;
        size  := random_get_within_range(1, xx max_size).(s64);
        align := 8 << (it % 4);
        context.allocator_align = xx align;
        memory := alloc(size,,a).(*u8);
        test_condition((memory.(u64) & (align - 1).(u64)) == 0);
        test_condition(a.proc(.IS_THIS_YOURS, 0, 0, memory, a.data) != null);

        l := Live.{memory, size, xx (it % 255 + 1)};
        memset(l.memory, l.stamp, l.size);
        array_add(*live, l);

        context.allocator_align = 8;
        if it % 3 == 0 {
            index    := random_get_within_range(0, (live.count-1).(float)).(s64);
            l        := *live[index];
            new_size := random_get_within_range(1, xx max_size).(s64);
            l.memory  = realloc(l.memory, new_size, l.size,,a);
            test_condition(stamp_is_intact(l.*, min(l.size, new_size)));
            l.size = new_size;
            memset(l.memory, l.stamp, l.size);
        }
        if it & 1 {
            index := random_get_within_range(0, (live.count-1).(float)).(s64);
            test_condition(stamp_is_intact(live[index], live[index].size));
            free(live[index].memory,,a);
            array_unordered_remove_by_index(*live, index);
        }
    }

    for live {
        test_condition(stamp_is_intact(it, it.size));
        free(it.memory,,a);
    }

    // everything freed: only the kept empty pages are left
    test_condition(a.small.ranges.count <= a.small.keep_empty_pages);
    // small's kept pages are themselves live allocations in large
    test_condition(a.large.ranges.count <= a.large.keep_empty_pages + a.small.ranges.count);

    return true;
} @engine_test

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

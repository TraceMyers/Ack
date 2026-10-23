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

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

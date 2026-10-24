// a heap whose allocations can all be freed at once. to scope allocators to it (say, everything in a world):
//
//     world_heap := make_heap();
//     {
//         push_allocator(world_heap);
//         general_purpose_allocator_startup(*gp); // books and data both default to the heap
//         linear_allocator_startup(*scratch);
//     }
//     ...
//     release_heap(world_heap);
//     gp = {}; scratch = {}; // don't shut them down, their memory is already gone
//
// every block is linked into a list through a header in front of it, and release_heap walks that
// list. heaps nest. create_heap(world_heap) makes a heap backed by world_heap, which is freed along with it.

Heap_Allocator :: struct {
    using #as base: Allocator;
    // where blocks come from
    backing: Allocator;
    // circular list of live blocks through this sentinel
    blocks:  Heap_Block;
}

// sits right before the memory handed out. 32 bytes, so 16 byte alignment is kept.
Heap_Block :: struct {
    prev: *Heap_Block;
    next: *Heap_Block;
    // what the backing allocator returned. differs from the block if alignment needed padding.
    raw:  *void;
    size: s64;
}

make_heap :: (backing := context.default_allocator) -> Allocator {
    heap := New(Heap_Allocator,, backing);
    heap.base        = {proc=heap_allocator_proc, data=heap};
    heap.backing     = backing;
    heap.blocks.prev = *heap.blocks;
    heap.blocks.next = *heap.blocks;
    return heap.base;
}

// frees every allocation in the heap, then the heap
release_heap :: (heap: Allocator) {
    engine_check(heap.proc == heap_allocator_proc && heap.data != null, "not a heap from make_heap");
    allocator := cast(*Heap_Allocator) heap.data;
    backing   := allocator.backing;

    block := allocator.blocks.next;
    while block != *allocator.blocks {
        next := block.next;
        free(block.raw,, backing);
        block = next;
    }
    free(allocator,, backing);
}

heap_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*Heap_Allocator) allocator_data;

    if #complete mode == {
    case .ALLOCATE;
        return heap_allocator_allocate(allocator, size);
    case .RESIZE;
        if size <= 0 {
            heap_allocator_free(allocator, old_memory);
            return null;
        }
        new_memory := heap_allocator_allocate(allocator, size);
        if old_memory != null {
            memcpy(new_memory, old_memory, min(size, old_size));
            heap_allocator_free(allocator, old_memory);
        }
        return new_memory;
    case .FREE;
        heap_allocator_free(allocator, old_memory);
        return null;
    case .STARTUP;
        #through;
    case .SHUTDOWN;
        engine_check(false, "use make_heap and release_heap");
        return null;
    case .THREAD_START;
        #through;
    case .THREAD_STOP;
        engine_check(false, "multithreaded access not supported");
        return null;
    case .CREATE_HEAP;
        return make_heap(allocator.base).data;
    case .DESTROY_HEAP;
        release_heap(.{proc=heap_allocator_proc, data=allocator});
        return null;
    case .IS_THIS_YOURS;
        block := allocator.blocks.next;
        while block != *allocator.blocks {
            memory := cast(*u8) (block + 1);
            if cast(*u8) old_memory >= memory && cast(*u8) old_memory < memory + block.size {
                return cast(*void) true;
            }
            block = block.next;
        }
        return null;
    case .CAPS;
        return xx (Allocator_Caps.FREE | .CREATE_HEAP | .IS_THIS_YOURS);
    }
}

heap_allocator_allocate :: (using allocator: *Heap_Allocator, size: s64) -> *void {
    if size <= 0 {
        return null;
    }

    align := max(cast(s64) context.allocator_align, 16);
    engine_check(is_power_of_two(align), "alignment % isn't a power of two", align, level=.HIGH);

    // blocks from the backing allocator are 16 aligned, so only bigger alignments need padding
    padding := ifx align > 16 then align - 16 else 0;
    raw: *void;
    {
        push_allocator(backing, 16);
        raw = alloc(size_of(Heap_Block) + size + padding);
    }
    if raw == null {
        return null;
    }
    engine_check(((cast(u64) raw) & 15) == 0, "backing allocator returned % which isn't 16 aligned", raw, level=.HIGH);

    memory := cast(*u8) ceil_to_power_of_two_multiple((cast(u64) raw) + size_of(Heap_Block), cast(u64) align);
    block  := (cast(*Heap_Block) memory) - 1;
    block.raw  = raw;
    block.size = size;

    block.prev = *blocks;
    block.next = blocks.next;
    blocks.next.prev = block;
    blocks.next      = block;
    return memory;
}

heap_allocator_free :: (using allocator: *Heap_Allocator, memory: *void) {
    if memory == null {
        return;
    }
    block := (cast(*Heap_Block) memory) - 1;
    engine_check(block.prev.next == block && block.next.prev == block, "% wasn't allocated by a heap", memory, level=.HIGH);

    block.prev.next = block.next;
    block.next.prev = block.prev;
    free(block.raw,, backing);
}

#scope_export

world_heap_test :: () -> bool {
    heap := make_heap();

    gp:      General_Purpose_Allocator;
    scratch: Linear_Allocator;
    grid:    Allocator_64;
    {
        push_allocator(heap);
        scratch.default_page_size = 1024 * 1024;
        general_purpose_allocator_startup(*gp);
        linear_allocator_startup(*scratch);
        allocator_64_startup(*grid);
    }
    test_condition(gp.books_allocator.data == heap.data && gp.data_allocator.data == heap.data);
    test_condition(scratch.books_allocator.data == heap.data && scratch.data_allocator.data == heap.data);
    test_condition(grid.books_allocator.data == heap.data && grid.data_allocator.data == heap.data);

    stale := alloc(64,, heap);
    test_condition(heap.proc(.IS_THIS_YOURS, 0, 0, stale, heap.data) != null);

    // a nested heap is freed with its parent
    level_heap := create_heap(heap);
    memset(alloc(256 * 1024,, level_heap), 4, 256 * 1024);

    context.allocator_align = 256;
    over_aligned := alloc(100,, heap);
    context.allocator_align = 8;
    test_condition((over_aligned.(u64) & 255) == 0);

    for 0..299 {
        size := random_get_within_range(1, 128 * 1024).(s64);
        memset(alloc(size,, gp), 1, size);
        memset(alloc(size,, scratch), 2, size);
        memset(alloc(size,, grid), 3, size);
    }

    release_heap(heap);
    gp = {}; scratch = {}; grid = {};

    // the new heap may land where the old one was. it must come back empty.
    heap = make_heap();
    defer release_heap(heap);
    test_condition(heap.proc(.IS_THIS_YOURS, 0, 0, stale, heap.data) == null);

    {
        push_allocator(heap);
        general_purpose_allocator_startup(*gp);
    }
    defer gp = {};

    memories: [100]*u8;
    for *memories {
        it.* = alloc(4096,, gp);
        memset(it.*, xx it_index, 4096);
    }
    for memories {
        for byte : 0..4095 {
            test_condition(it[byte] == xx it_index);
        }
        free(it,, gp);
    }

    return true;
} @engine_test

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

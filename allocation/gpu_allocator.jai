// for allocating heaps on the gpu. was designed to be used as the data allocator for
// the other allocators. if you do things that way, the *void you get back is actually
// a masked GPU_Allocation, which tells you which heap and the offset from that heap.
//
// a heap has one type, so an allocator that sub-allocates heaps needs separate pages per type.
// GPU_Linear_Allocator and GPU_General_Allocator handle that. each keeps one sub-allocator (lane)
// per heap type, started on first use. new allocations go to the lane for
// context.gpu_alloc_info.type, existing ones to the lane for the type of the heap they're in.

GPU_Allocator :: struct {
    using #as base: Allocator;
    heaps: Pool(GPU_Heap);
    books_allocator: Allocator;
}

// passed back as *void. offset is the low 32 bits, so adding to the pointer adds to the offset.
GPU_Allocation :: struct {
    offset: u32;
    heap:   s32;
}
#assert size_of(GPU_Allocation) == size_of(*void);

GPU_Alloc_Info :: struct {
    type: GPU_Heap_Type;
}

GPU_Heap_Type :: enum u8 {
    NONE;
    DEVICE_LOCAL_BUFFER; // if this isn't the first buffer type, update is_buffer_type
    HOST_VISIBLE_BUFFER;
    VERTEX_BUFFER;
    SKINNED_VERTEX_BUFFER;
    INDEX_BUFFER; // if this isn't the last buffer type, update is_buffer_type
    DEVICE_LOCAL_IMAGE; // if this isn't the first image type, update is_buffer_type
    HOST_VISIBLE_IMAGE;
}
GPU_HEAP_TYPE_COUNT :: #run enum_highest_value(GPU_Heap_Type) + 1;

GPU_Heap :: struct {
    // GPU_Allocation size maxes out at offset size u32, so this does, too
    size: u32;
    type: GPU_Heap_Type;
    min_alignment: u32;
    renderer_data: Render_API_Heap_Data;
}

mask_gpu_allocation :: inline (allocation: GPU_Allocation) -> *void {
    copy := allocation;
    return (cast(**void) *copy).*;
}

unmask_gpu_allocation :: inline (masked_allocation: *void) -> GPU_Allocation {
    copy := masked_allocation;
    return (cast(*GPU_Allocation) *copy).*;
}

get_heap :: (allocator: *GPU_Allocator, allocation: GPU_Allocation) -> *GPU_Heap {
    return *allocator.heaps[allocation.heap];
}

get_heap :: (allocator: *GPU_Allocator, masked_allocation: *void) -> *GPU_Heap {
    return get_heap(allocator, unmask_gpu_allocation(masked_allocation));
}

// whether masked_allocation points into a heap of this allocator. safe to call with any pointer.
heap_exists :: (allocator: *GPU_Allocator, masked_allocation: *void) -> bool {
    heap := unmask_gpu_allocation(masked_allocation).heap;
    // heap 0 is reserved
    return heap > 0 && heap < allocator.heaps.items.count && is_pool_item_in_use(*allocator.heaps, heap);
}

gpu_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*GPU_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        if old_memory == null then return null;
        return gpu_allocator_free(allocator, unmask_gpu_allocation(old_memory));
    case .RESIZE;
        engine_check(false, "resize not supported");
        return null;
    case .ALLOCATE;
        return gpu_allocator_allocate(allocator, size);
    case .STARTUP;
        return gpu_allocator_startup(allocator);
    case .SHUTDOWN;
        return gpu_allocator_shutdown(allocator);
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
    case .IS_THIS_YOURS;
        return null;
    case .CAPS;
        return null;
    }
}

gpu_allocator_startup :: (using allocator: *GPU_Allocator) -> *void {
    engine_check(heaps.items.count == 0);

    base = {proc = gpu_allocator_proc, data = allocator};

    if books_allocator.proc == null {
        pool_set_allocator(*heaps, context.allocator);
    } else {
        pool_set_allocator(*heaps, books_allocator);
    }

    // reserve heap 0, otherwise first allocation would return cast(*void) {0,0}, which is null
    pool_borrow(*heaps);

    return null;
}

gpu_allocator_shutdown :: (using allocator: *GPU_Allocator) -> *void {
    // this for expansion skips unused pool slots
    for *heap : heaps {
        // heap 0 is reserved, never allocated
        if it_index == 0 continue;
        renderer_backend_free_gpu_heap(heap);
    }
    pool_reset(*heaps);
    allocator.* = {};
    return null;
}

gpu_allocator_allocate :: (allocator: *GPU_Allocator, size: s64) -> *void {
    // maximum possible size representable by GPU_Allocation
    engine_check(size <= U32_MAX);
    engine_check(context.gpu_alloc_info.type != .NONE, "context.gpu_alloc_info.type must be set before allocating gpu memory");

    heap_index := pool_borrow(*allocator.heaps);
    heap := *allocator.heaps[heap_index];
    success := renderer_backend_allocate_gpu_heap(heap, size, context.gpu_alloc_info);
    if !success {
        engine_warning("failed to allocate a gpu heap");
        pool_return(*allocator.heaps, heap_index);
        return null;
    }
    return mask_gpu_allocation(.{0, xx heap_index});
}

gpu_allocator_free :: (allocator: *GPU_Allocator, allocation: GPU_Allocation) -> *void {
    // this allocator is only for allocating and freeing whole heaps.
    // other allocators can use this allocator as the 'data allocator', and
    // they will return GPU_Allocations (masked as *void) with offset >= 0.
    engine_check(allocation.offset == 0);
    heap := get_heap(allocator, allocation);
    renderer_backend_free_gpu_heap(heap);
    pool_return(*allocator.heaps, allocation.heap);
    return null;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------- :linear lanes

// set heap_allocator to a started GPU_Allocator, then start this.
GPU_Linear_Allocator :: struct {
    using #as base: Allocator;
    heap_allocator:  *GPU_Allocator;
    books_allocator: Allocator;
    // pages are whole heaps. allocations bigger than this get a heap of their own size.
    heap_size := 64 * 1024 * 1024;
    lanes: [GPU_HEAP_TYPE_COUNT]Linear_Allocator;
}

gpu_linear_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*GPU_Linear_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        return null;
    case .ALLOCATE;
        #through;
    case .RESIZE;
        return linear_allocator_proc(mode, size, old_size, old_memory, get_lane(allocator, old_memory));
    case .STARTUP;
        return gpu_linear_allocator_startup(allocator);
    case .SHUTDOWN;
        gpu_linear_allocator_shutdown(allocator);
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
    case .IS_THIS_YOURS;
        if !heap_exists(allocator.heap_allocator, old_memory) then return null;
        lane := *allocator.lanes[get_heap(allocator.heap_allocator, old_memory).type];
        if lane.proc == null then return null;
        return linear_allocator_proc(mode, size, old_size, old_memory, lane);
    case .CAPS;
        return xx Allocator_Caps.IS_THIS_YOURS;
    }
}

gpu_linear_allocator_startup :: (using allocator: *GPU_Linear_Allocator) -> *void {
    engine_check(heap_allocator != null && heap_allocator.proc == gpu_allocator_proc, "heap_allocator must be a started GPU_Allocator");

    allocator.base = {proc=gpu_linear_allocator_proc, data=allocator};

    // lanes start while this allocator is context.allocator, so books can't default to that
    if books_allocator.proc == null {
        books_allocator = context.allocator;
    }
    return null;
}

gpu_linear_allocator_reset_keeping_memory :: (allocator: *GPU_Linear_Allocator) {
    for *allocator.lanes {
        if it.proc != null then linear_allocator_reset_keeping_memory(it);
    }
}

gpu_linear_allocator_shutdown :: (allocator: *GPU_Linear_Allocator) {
    for *allocator.lanes {
        if it.proc != null then linear_allocator_shutdown(it);
    }
    allocator.* = {};
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------ :general lanes

// set heap_allocator to a started GPU_Allocator, then start this.
GPU_General_Allocator :: struct {
    using #as base: Allocator;
    heap_allocator:  *GPU_Allocator;
    books_allocator: Allocator;
    lanes: [GPU_HEAP_TYPE_COUNT]GPU_General_Lane;
}

// chained so that heaps are big and few. small handles up to 16KB in 1MB pages taken from large,
// large handles up to 1MB in 64MB heaps, and anything bigger gets a heap of its own.
GPU_General_Lane :: struct {
    small: Allocator_64;
    large: Allocator_64;
}

// the max alignment the general allocator can satisfy. covers image alignment requirements.
GPU_GENERAL_PAGE_ALIGN :: 64 * 1024;

gpu_general_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*GPU_General_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        if old_memory == null then return null;
        #through;
    case .ALLOCATE;
        #through;
    case .RESIZE;
        return allocator_64_proc(mode, size, old_size, old_memory, *get_lane(allocator, old_memory).small);
    case .STARTUP;
        return gpu_general_allocator_startup(allocator);
    case .SHUTDOWN;
        gpu_general_allocator_shutdown(allocator);
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
    case .IS_THIS_YOURS;
        if !heap_exists(allocator.heap_allocator, old_memory) then return null;
        lane := *allocator.lanes[get_heap(allocator.heap_allocator, old_memory).type];
        if lane.small.proc == null then return null;
        return allocator_64_proc(mode, size, old_size, old_memory, *lane.small);
    case .CAPS;
        return xx (Allocator_Caps.FREE | .ACTUALLY_RESIZE | .IS_THIS_YOURS);
    }
}

gpu_general_allocator_startup :: (using allocator: *GPU_General_Allocator) -> *void {
    engine_check(heap_allocator != null && heap_allocator.proc == gpu_allocator_proc, "heap_allocator must be a started GPU_Allocator");

    allocator.base = {proc=gpu_general_allocator_proc, data=allocator};

    // lanes start while this allocator is context.allocator, so books can't default to that
    if books_allocator.proc == null {
        books_allocator = context.allocator;
    }
    return null;
}

gpu_general_allocator_shutdown :: (allocator: *GPU_General_Allocator) {
    for *allocator.lanes {
        if it.small.proc == null then continue;
        allocator_64_shutdown(*it.small);
        allocator_64_shutdown(*it.large);
    }
    allocator.* = {};
}

#scope_file

get_lane_type :: (heap_allocator: *GPU_Allocator, old_memory: *void) -> GPU_Heap_Type {
    if old_memory != null {
        return get_heap(heap_allocator, old_memory).type;
    }
    type := context.gpu_alloc_info.type;
    engine_check(type != .NONE, "context.gpu_alloc_info.type must be set before allocating gpu memory");
    return type;
}

get_lane :: (using allocator: *GPU_Linear_Allocator, old_memory: *void) -> *Linear_Allocator {
    lane := *lanes[get_lane_type(heap_allocator, old_memory)];
    if lane.proc == null {
        engine_check(old_memory == null, "% wasn't allocated by this allocator", old_memory);
        lane.default_page_size = heap_size;
        lane.books_allocator   = books_allocator;
        lane.data_allocator    = heap_allocator.base;
        linear_allocator_startup(lane);
    }
    return lane;
}

get_lane :: (using allocator: *GPU_General_Allocator, old_memory: *void) -> *GPU_General_Lane {
    lane := *lanes[get_lane_type(heap_allocator, old_memory)];
    if lane.small.proc == null {
        engine_check(old_memory == null, "% wasn't allocated by this allocator", old_memory);

        lane.large.slot_size       = 16 * 1024;
        lane.large.page_align      = GPU_GENERAL_PAGE_ALIGN;
        lane.large.books_allocator = books_allocator;
        lane.large.data_allocator  = heap_allocator.base;
        allocator_64_startup(*lane.large);

        lane.small.slot_size       = 256;
        lane.small.page_align      = GPU_GENERAL_PAGE_ALIGN;
        lane.small.books_allocator = books_allocator;
        lane.small.data_allocator  = lane.large.base;
        allocator_64_startup(*lane.small);
    }
    return lane;
}

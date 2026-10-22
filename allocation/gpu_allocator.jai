// for allocating heaps on the gpu. was designed to be used as the data allocator for
// the other allocators. if you do things that way, the *void you get back is actually
// a GPU_Allocation, which tells you which heap and the offset from that heap.

GPU_Allocator :: struct {
    using #as base: Allocator;
    heaps: Pool(GPU_Heap);
    books_allocator: Allocator;
}

// passed back as *void
GPU_Allocation :: struct {
    offset: u32;
    heap:   s32;
}

GPU_Alloc_Info :: struct {
    type: GPU_Heap_Type;

    #if GRAPHICS_API == "VULKAN" {
        buffer_usage: VkBufferUsage;
    }
}

GPU_Heap_Type :: enum u8 {
    DEVICE_LOCAL_BUFFER;
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

get_heap :: (allocator: *GPU_Allocator, allocation: GPU_Allocation) -> *GPU_Heap {
    return *allocator.heaps[allocation.heap];
}

get_heap :: (allocator: *GPU_Allocator, masked_allocation: *void) -> *GPU_Heap {
    allocation := cast,force(GPU_Allocation) masked_allocation;
    return *allocator.heaps[allocation.heap];
}

gpu_allocator_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    allocator := cast(*GPU_Allocator) allocator_data;

    if #complete mode == {
    case .FREE;
        return gpu_allocator_free(alocator, cast,force(GPU_Allocation) old_memory);
    case .RESIZE;
        return engine_validate(false, "resize not supported");
    case .ALLOCATE;
        return gpu_allocator_allocate(allocator, size);
    case .STARTUP;
        return gpu_allocator_startup(allocator);
    case .SHUTDOWN;
    case .THREAD_START; 
        #through;
    case .THREAD_STOP;
        engine_check(false, "multithreaded access not supported");
        return null;
    case .CREATE_HEAP;
    case .DESTROY_HEAP;
        engine_check(false, "creating and destoying heaps not supported");
        return null;
    case .IS_THIS_YOURS;
    case .CAPS;
    }
    return null;
}

gpu_allocator_startup :: (using allocator: *GPU_Allocator) -> *void {
    engine_check(heaps.items.count == 0);

    // reserve heap 0, otherwise first allocation would return cast(*void) {0,0}, which is null
    pool_borrow(*heaps);

    base = {
        proc = gpu_allocator_proc,
        data = allocator
    };

    if books_allocator.proc == null {
        pool_set_allocator(*heaps, context.allocator);
    } else {
        pool_set_allocator(*heaps, books_allocator);
    }

    return null;
}

gpu_allocator_allocate :: (allocator: *GPU_Allocator, size: s64) -> *void {
    // maximum possible size representable by GPU_Allocation
    engine_check(size <= U32_MAX);
        
    heap_index := pool_borrow(*allocator.heaps);
    heap := *allocator.heaps[heap_index];
    allocation := renderer_backend_allocate_gpu_heap(heap, size, context.gpu_alloc_info);
    if allocation.heap < 0 {
        engine_warning("failed to allocate a gpu heap");
        pool_return(*allocator.heaps, heap_index);
    }
    return cast(*void) allocation;
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

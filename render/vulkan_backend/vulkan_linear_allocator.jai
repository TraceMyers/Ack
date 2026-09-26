// procedures in this file will no doubt need to be split up so the code can be shared among
// allocators, but I only plan on having two of them. also, a lot of parameterization that will
// eventually be needed is hidden right now for convenience.

GPU_Linear_Allocator :: struct {
    heaps: [..]s16;
    heap_type: GPU_Heap_Type;
    frontier: int;
    frontier_offset: int;
}

gpu_linear_allocate :: inline (heap_type: GPU_Heap_Type, size: int, usage_flags: VkBufferUsageFlags, temp := false) -> GPU_Buffer {
    using context.renderer;

    render_check(.MEDIUM, is_buffer_type(heap_type));

    align := usage_alignment(usage_flags);
    buffer := GPU_Buffer.{
        allocation = gpu_linear_allocate_aligned(size, align, heap_type, temp),
        usage_flags = usage_flags
    };

    return buffer;
}

gpu_linear_allocate :: inline (heap_type: GPU_Heap_Type, width: s32, height: s32, usage_flags: VkImageUsageFlags, format := VkFormat.R8G8B8A8_UNORM, mip_count: u32 = 1, layer_count: u32 = 1, create_color_view := true) -> *GPU_Image {
    using context.renderer;

    render_check(.MEDIUM, is_image_type(heap_type));

    image_index := pool_borrow(*image_pool);
    render_check(.MEDIUM, image_index < max_texture_count);
    image := *image_pool[image_index];
    image.pool_index = xx image_index;

    image.extent      = {xx width, xx height, 1};
    image.format      = format;
    image.usage       = usage_flags;
    image.mip_count   = xx mip_count;
    image.layer_count = xx layer_count;

    create_info := VkImageCreateInfo.{
        imageType = ._2D,
        format = image.format,
        extent = image.extent,
        mipLevels = mip_count,
        // here, can stack images together, (like maybe albedo, metallic, roughness, etc.)
        // maybe it's not good for that example, though since I don't think we usually mip
        // pbr-type textures?
        arrayLayers = layer_count,
        samples = ._1_BIT, // MSAA
        tiling = .OPTIMAL,
        usage = usage_flags,
        sharingMode = .EXCLUSIVE
    };

    memory_requirements: VkMemoryRequirements;
    vkCreateImage(logical.obj, *create_info, null, *image.obj);
    vkGetImageMemoryRequirements(logical.obj, image.obj, *memory_requirements);

    align : int = xx memory_requirements.alignment;
    size  : int = xx memory_requirements.size;

    image.allocation = gpu_linear_allocate_aligned(size, align, heap_type, false);

    heap := *gpu_heap_pool[image.allocation.source_heap];
    vkBindImageMemory(logical.obj, image.obj, heap.memory, xx image.allocation.source_heap_offset);

    if create_color_view {
        view_create_info := image_view_create_info(image.format, image.obj, .COLOR_BIT, image.mip_count);
        render_check(.LOW, vkCreateImageView(logical.obj, *view_create_info, null, *image.view), "failed to create an image view for a sampled texture");
    }

    return image;
}

gpu_linear_allocate_aligned :: (size: int, align: int, heap_type: GPU_Heap_Type, temp: bool) -> GPU_Allocation {
    using context.renderer;

    if size == 0 then return {};

    allocator := get_linear_allocator(heap_type, temp);

    heap: *GPU_Heap; 
    available_size: int;

    aligned_size := size;
    aligned_frontier_offset: int;

    while allocator.frontier < allocator.heaps.count {
        frontier_heap_index := allocator.heaps[allocator.frontier];
        heap = *gpu_heap_pool[frontier_heap_index];
        render_check(.MEDIUM, heap.is_valid);

        if heap_type == .VERTEX_BUFFER || heap_type == .INDEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER {
            // vertices and indices should be packed without align padding
            aligned_frontier_offset = allocator.frontier_offset;
        } else {
            use_align := max(heap.buffer_min_alignment, cast(u32) align);
            aligned_frontier_offset = align_up(allocator.frontier_offset, use_align);
        }

        available_size = heap.size - aligned_frontier_offset;

        if available_size >= size {
            break;
        }

        allocator.frontier += 1;
    }

    allocation_offset := aligned_frontier_offset;

    if available_size < aligned_size {

        target_heap_size: int;
        buffer_usage: VkBufferUsageFlags;

        if heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER {
            target_heap_size = VERTEX_BUFFER_SIZE;
            buffer_usage = .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT;
            // there can be only one vertex buffer, because all draws use one buffer for draw simplicity
            render_check(.MEDIUM, allocator.heaps.count == 0);
        } else if heap_type == .INDEX_BUFFER {
            target_heap_size = INDEX_BUFFER_SIZE;
            buffer_usage = .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT;
            // there can be only one index buffer, because all draws use one buffer for draw simplicity
            render_check(.MEDIUM, allocator.heaps.count == 0);
        } else if is_buffer_type(heap_type) {
            target_heap_size = DEFAULT_BUFFER_HEAP_SIZE;
            buffer_usage = 
                  .TRANSFER_SRC_BIT
                | .TRANSFER_DST_BIT
                | .UNIFORM_TEXEL_BUFFER_BIT
                | .STORAGE_TEXEL_BUFFER_BIT
                | .UNIFORM_BUFFER_BIT
                | .STORAGE_BUFFER_BIT
                | .INDIRECT_BUFFER_BIT;
        } else {
            target_heap_size = DEFAULT_IMAGE_HEAP_SIZE;
        }

        heap_size := max(size, target_heap_size);

        heap_index := allocate_gpu_heap(heap_size, heap_type, .LINEAR_ALLOCATOR, buffer_usage);
        render_check(.MEDIUM, heap_index != 0xffff);
        array_add(*allocator.heaps, heap_index);
        heap = *gpu_heap_pool[heap_index];

        allocation_offset = 0;
        allocator.frontier = xx allocator.heaps.count - 1;
        allocator.frontier_offset = size;
    } else {
        allocator.frontier_offset = allocation_offset + size;
    }

    allocation := GPU_Allocation.{
        source_heap           = allocator.heaps[allocator.frontier],
        allocator_heap_index  = xx allocator.frontier,
        source_heap_offset    = xx allocation_offset,
        size                  = xx size
    };

    return allocation;
}

// assumes keeping memory. will add a parameter for not if needed
gpu_linear_allocator_reset :: (allocator: *GPU_Linear_Allocator) {
    allocator.frontier = 0;
    allocator.frontier_offset = 0;
}

get_linear_allocator :: (heap_type: GPU_Heap_Type, temp: bool) -> *GPU_Linear_Allocator {
    if temp {
        frame := get_current_frame();
        return *frame.temp_allocators[heap_type];
    } else {
        return *context.renderer.linear_allocators[heap_type]; 
    }
}

#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

GPU_Linear_Allocator :: struct {
    heaps: [..]s16;
    heap_type: GPU_Heap_Type;
    frontier: int;
    frontier_offset: int;
}

initialize_allocators :: () -> bool {
    // Create throwaway resources to probe compatibility

    dummy_buffer_create_info := VkBufferCreateInfo.{
        size = 4096,
        usage = .VERTEX_BUFFER_BIT
              | .INDEX_BUFFER_BIT
              | .UNIFORM_BUFFER_BIT
              | .STORAGE_BUFFER_BIT
              | .TRANSFER_SRC_BIT
              | .TRANSFER_DST_BIT,
        sharingMode = .EXCLUSIVE
    };
    dummy_buffer: VkBuffer;

    dummy_image_create_info := VkImageCreateInfo.{
        imageType = ._2D,
        format = .R8G8B8A8_UNORM,
        extent = {1024, 1024, 1},
        mipLevels = 1,
        arrayLayers = 1,
        samples = ._1_BIT, // MSAA
        tiling = .OPTIMAL,
        usage =  .TRANSFER_DST_BIT | .SAMPLED_BIT,
        sharingMode = .EXCLUSIVE
    };
    dummy_image: VkImage;

    dummy_buffer_requirements: VkMemoryRequirements;
    dummy_image_requirements: VkMemoryRequirements;

    vkCreateBuffer(logical_device.obj, *dummy_buffer_create_info, null, *dummy_buffer);
    vkGetBufferMemoryRequirements(logical_device.obj, dummy_buffer, *dummy_buffer_requirements);
    vkDestroyBuffer(logical_device.obj, dummy_buffer, null);

    vkCreateImage(logical_device.obj, *dummy_image_create_info, null, *dummy_image);   // OPTIMAL tiling, typical format
    vkGetImageMemoryRequirements(logical_device.obj, dummy_image, *dummy_image_requirements);
    vkDestroyImage(logical_device.obj, dummy_image, null);

    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical_device.obj, *memory_properties);

    physical_device.properties.device_local_buffer_memory_index = find_index_of_memory_type(dummy_buffer_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT, *memory_properties);
    physical_device.properties.host_visible_buffer_memory_index = find_index_of_memory_type(dummy_buffer_requirements.memoryTypeBits, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *memory_properties);
    physical_device.properties.device_local_image_memory_index = find_index_of_memory_type(dummy_image_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT, *memory_properties);
    physical_device.properties.host_visible_image_memory_index = find_index_of_memory_type(dummy_image_requirements.memoryTypeBits, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *memory_properties);

    for *linear_allocators {
        it.heap_type = cast(GPU_Heap_Type) it_index;
    }

    return true;
}

gpu_linear_allocate_aligned :: (size: int, align: int, heap_type: GPU_Heap_Type, temp: bool, buffer_usage: VkBufferUsageFlags = 0) -> GPU_Allocation {
    if size == 0 then return {};

    allocator := get_linear_allocator(heap_type, temp);

    heap: *GPU_Heap; 
    available_size: int;

    aligned_size := size;
    aligned_frontier_offset: int;

    while allocator.frontier < allocator.heaps.count {
        frontier_heap_index := allocator.heaps[allocator.frontier];
        heap = *gpu_heaps[frontier_heap_index];
        render_check(heap.is_valid);

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
        heap_size := max(size, DEFAULT_GPU_HEAP_SIZE);
        heap_index := allocate_gpu_heap(heap_size, heap_type, .LINEAR, buffer_usage);
        render_check(heap_index != 0xffff);

        array_add(*allocator.heaps, heap_index);

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
        return *linear_allocators[heap_type]; 
    }
}

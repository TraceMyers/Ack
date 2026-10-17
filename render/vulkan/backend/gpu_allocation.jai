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

GPU_Allocator :: enum u8 {
    LINEAR_ALLOCATOR;
}

GPU_Heap :: struct {
    memory: VkDeviceMemory;
    size: int;

    type: GPU_Heap_Type;
    allocator: GPU_Allocator;

    // these fields are only valid if this is a heap for allocating buffers
    buffer: VkBuffer; 
    buffer_usage: VkBufferUsageFlags;
    buffer_min_alignment: u32;

    is_valid: bool;
}

GPU_Allocation :: struct {
    source_heap: s16 = -1;
    allocator_heap_index: s16;
    source_heap_offset: s32;
    size: u32;
}

GPU_Image :: struct {
    using #as allocation: GPU_Allocation;
    obj:                  VkImage;   
    view:                 VkImageView;
    extent:               VkExtent3D;
    format:               VkFormat;
    usage:                VkImageUsageFlags;
    mip_count:            u8;
    layer_count:          u8;
    pool_index:           s16;
}

GPU_Buffer :: struct {
    using #as allocation: GPU_Allocation;
    usage_flags: VkBufferUsageFlags;
}

is_device_local_type :: (heap_type: GPU_Heap_Type) -> bool {
    return !is_host_visible_type(heap_type);
}

is_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    return heap_type <= .INDEX_BUFFER;
}

is_image_type :: (heap_type: GPU_Heap_Type) -> bool {
    return !is_buffer_type(heap_type);
}

is_host_visible_type :: (heap_type: GPU_Heap_Type) -> bool {
    if heap_type == {
    case .HOST_VISIBLE_BUFFER;
        return true;
    case .HOST_VISIBLE_IMAGE;
        return true;
    }
    return false;
}

heap_type_and_memory_index :: inline (heap_type: GPU_Heap_Type) -> VkMemoryPropertyFlags, u32 {
    using engine.renderer.backend;

    if is_buffer_type(heap_type) {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical.properties.host_visible_buffer_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical.properties.device_local_buffer_memory_index;
        }
    } else {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical.properties.host_visible_image_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical.properties.device_local_image_memory_index;
        }
    }

    return 0, 0xffff_ffff;
}

usage_alignment :: inline (usage_flags: VkBufferUsageFlags) -> int {
    using engine.renderer.backend;
    align: u32 = 0;
    if (usage_flags & (.TRANSFER_SRC_BIT | .TRANSFER_DST_BIT | .STORAGE_BUFFER_BIT)) != 0 {
        // note: I was told by an AI that meeting the requirements for storage buffers
        // almost certainly meets the requirements for optimal transfer.
        align = max(align, cast(u32) physical_device.properties.storage_buffer_alignment);
    }
    if (usage_flags & (.UNIFORM_TEXEL_BUFFER_BIT | .STORAGE_TEXEL_BUFFER_BIT)) != 0 {
        align = max(align, cast(u32) physical_device.properties.texel_buffer_alignment);
    }
    if (usage_flags & .UNIFORM_BUFFER_BIT) != 0 {
        align = max(align, cast(u32) physical_device.properties.uniform_buffer_alignment);
    }
    if (usage_flags & .VERTEX_BUFFER_BIT) != 0 {
        align = max(align, 8);
    }
    if (usage_flags & (.INDEX_BUFFER_BIT | .INDIRECT_BUFFER_BIT)) != 0 {
        align = max(align, 4);
    }
    return align;
}

find_index_of_memory_type :: (can_use_type_bits: u32, must_have_props: VkMemoryPropertyFlags, memory_properties: *VkPhysicalDeviceMemoryProperties) -> u32 {
    for 0..memory_properties.memoryTypeCount-1 {
        type_props := memory_properties.memoryTypes[it].propertyFlags;
        type_has_props := (type_props & must_have_props) == must_have_props;
        type_can_be_used := (cast(u32) (1 << it) & can_use_type_bits) != 0;
        if type_has_props && type_can_be_used {
            return cast(u32) it;
        }
    }
    return engine.renderer.backend.INVALID_MEMORY_TYPE_INDEX;
}

allocate_gpu_image :: (image: *GPU_Image, create_info: VkImageCreateInfo, memory_flags: VkMemoryPropertyFlags) {
    using engine.renderer.backend;
    memory_requirements: VkMemoryRequirements;
    vkCreateImage(logical_device.obj, *create_info, null, *image.obj);
    vkGetImageMemoryRequirements(logical_device.obj, image.obj, *memory_requirements);
    allocate_gpu_memory(*image.memory, memory_flags, memory_requirements);
    vkBindImageMemory(logical_device.obj, image.obj, image.memory, 0);   
}

allocate_gpu_buffer :: (buffer: *GPU_Buffer, create_info: VkBufferCreateInfo, memory_flags: VkMemoryPropertyFlags) {
    using engine.renderer.backend;
    memory_requirements: VkMemoryRequirements;
    vkCreateBuffer(logical_device.obj, *create_info, null, *buffer.obj);
    vkGetBufferMemoryRequirements(logical_device.obj, buffer.obj, *memory_requirements);
    allocate_gpu_memory(*buffer.memory, memory_flags, memory_requirements);
    vkBindBufferMemory(logical_device.obj, buffer.obj, buffer.memory, 0);   
}

allocate_gpu_memory :: (memory: *VkDeviceMemory, flags: VkMemoryPropertyFlags, requirements: VkMemoryRequirements) {
    using engine.renderer.backend;
    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical_device.obj, *memory_properties);
    memory_type_index := find_index_of_memory_type(requirements.memoryTypeBits, flags, *memory_properties);
    allocate_info := VkMemoryAllocateInfo.{
        allocationSize = requirements.size,
        memoryTypeIndex = memory_type_index
    };
    vkAllocateMemory(logical_device.obj, *allocate_info, null, memory);
}

allocate_material :: (mat: *Material) -> s32 {
    using engine.renderer.backend;
    new_mat_index := pool_borrow(*materials);
    render_check(new_mat_index != -1);
    update_material(xx new_mat_index, mat);
    return xx new_mat_index;
}

allocate_gpu_heap :: (size: int, type: GPU_Heap_Type, allocator: GPU_Allocator, buffer_usage: VkBufferUsageFlags = 0) -> s16 {
    using engine.renderer.backend;

    _, memory_index := heap_type_and_memory_index(type);
    allocate_info := VkMemoryAllocateInfo.{
        allocationSize = xx size,
        memoryTypeIndex = memory_index
    };

    memory: VkDeviceMemory;

    if !render_evaluate(vkAllocateMemory(logical_device.obj, *allocate_info, null, *memory), "failed to allocate a heap of type % from allocator % size %", type, allocator, size) {
        return -1;
    }

    buffer: VkBuffer;
    buffer_min_alignment: u32;

    if is_buffer_type(type) {
        create_info := VkBufferCreateInfo.{
            size        = xx size,
            usage       = buffer_usage,
            sharingMode = .EXCLUSIVE
        };

        memory_requirements: VkMemoryRequirements;
        vkCreateBuffer(logical_device.obj, *create_info, null, *buffer);
        vkGetBufferMemoryRequirements(logical_device.obj, buffer, *memory_requirements);
        buffer_min_alignment = xx memory_requirements.alignment;
        vkBindBufferMemory(logical_device.obj, buffer, memory, 0);
    }

    heap_index := cast(u16) pool_borrow(*gpu_heap_pool);
    heap := *gpu_heap_pool[heap_index];

    heap.* = GPU_Heap.{
        memory               = memory,
        size                 = size,
        type                 = type,
        allocator            = allocator,
        buffer               = buffer,
        buffer_usage         = buffer_usage,
        buffer_min_alignment = buffer_min_alignment,
        is_valid             = true
    };

    return xx heap_index;
}


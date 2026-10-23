#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

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

    gpu_allocator_startup(*heap_allocator);

    linear_allocator.heap_allocator = *heap_allocator;
    gpu_linear_allocator_startup(*linear_allocator);

    general_allocator.heap_allocator = *heap_allocator;
    gpu_general_allocator_startup(*general_allocator);

    return true;
}

DEPTH_VIEW_ATTACHMENT :: 0;
DEPTH_VIEW_SAMPLING   :: 1;

Render_API_Heap_Data :: struct {
    memory: VkDeviceMemory;
    // these fields are only valid if this is a heap for allocating buffers
    buffer: VkBuffer; 
    buffer_usage: VkBufferUsageFlags;
}

GPU_Image_View_Info :: struct {
    aspect_flags:    VkImageAspectFlags;
    expected_layout: VkImageLayout;
}

GPU_Image_View :: struct {
    obj:             VkImageView;
    using info: GPU_Image_View_Info;
}

GPU_Image :: struct {
    allocation:           GPU_Allocation;
    // what allocation came from. proc is null if the image doesn't own memory (swapchain images).
    allocator:            Allocator;
    obj:                  VkImage;   
    views:                Hybrid_Storage_Array(GPU_Image_View);
    extent:               VkExtent3D;
    format:               VkFormat;
    usage:                VkImageUsageFlags;
    layout:               VkImageLayout;
    pool_index:           s16;
    mip_count:            u8;
    layer_count:          u8;
}

GPU_Buffer :: struct {
    allocation:  GPU_Allocation;
    allocator:   Allocator;
    size:        int;
    usage_flags: VkBufferUsageFlags;
}

is_device_local_type :: (heap_type: GPU_Heap_Type) -> bool {
    return !is_host_visible_type(heap_type);
}

is_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    return heap_type != .NONE && heap_type <= .INDEX_BUFFER;
}

is_image_type :: (heap_type: GPU_Heap_Type) -> bool {
    return heap_type >= .DEVICE_LOCAL_IMAGE;
}

// vertices and indices are packed without align padding
is_packed_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    return heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER || heap_type == .INDEX_BUFFER;
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
    if is_buffer_type(heap_type) {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical_device.properties.host_visible_buffer_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical_device.properties.device_local_buffer_memory_index;
        }
    } else {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical_device.properties.host_visible_image_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical_device.properties.device_local_image_memory_index;
        }
    }

    return 0, 0xffff_ffff;
}

usage_alignment :: inline (usage_flags: VkBufferUsageFlags) -> int {
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
    return INVALID_MEMORY_TYPE_INDEX;
}

// allocations go through the context so that lane allocators know which heap type to use
gpu_alloc :: (allocator: Allocator, heap_type: GPU_Heap_Type, size: int, align: int) -> GPU_Allocation, success: bool {
    push_allocator(allocator, align, .{type = heap_type});
    memory := alloc(size);
    return unmask_gpu_allocation(memory), memory != null;
}

gpu_free :: (allocator: Allocator, allocation: GPU_Allocation) {
    free(mask_gpu_allocation(allocation),, allocator);
}

// usage flags:
// 
// TRANSFER_SRC_BIT             :: 0x1;
// TRANSFER_DST_BIT             :: 0x2;
// SAMPLED_BIT                  :: 0x4;
// STORAGE_BIT                  :: 0x8;
// COLOR_ATTACHMENT_BIT         :: 0x10;
// DEPTH_STENCIL_ATTACHMENT_BIT :: 0x20;
// TRANSIENT_ATTACHMENT_BIT     :: 0x40;
// INPUT_ATTACHMENT_BIT         :: 0x80;
// SHADING_RATE_IMAGE_BIT_NV    :: 0x100;
//
// pass allocator = .{} and a premade_image for images that don't own memory
create_gpu_image :: (allocator: Allocator, heap_type: GPU_Heap_Type, width: s32, height: s32, usage_flags: VkImageUsageFlags, format := VkFormat.R8G8B8A8_UNORM, mip_count: u32 = 1, layer_count: u32 = 1, premade_image: VkImage = null) ->  *GPU_Image {
    // if no allocator, must assign an image object
    render_check((premade_image != null) == (allocator.proc == null));

    image_index := pool_borrow(*images);
    render_check(image_index < creation_settings.max_textures);
    image := *images[image_index];
    image.pool_index = xx image_index;

    image.extent      = {xx width, xx height, 1};
    image.format      = format;
    image.usage       = usage_flags;
    image.mip_count   = xx mip_count;
    image.layer_count = xx layer_count;

    memory_requirements: VkMemoryRequirements;

    if allocator.proc != null {
        render_check(is_image_type(heap_type));
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

        vkCreateImage(logical_device.obj, *create_info, null, *image.obj);
        vkGetImageMemoryRequirements(logical_device.obj, image.obj, *memory_requirements);

        success: bool;
        image.allocation, success = gpu_alloc(allocator, heap_type, xx memory_requirements.size, xx memory_requirements.alignment);
        render_check(success, "failed to allocate % bytes for an image of heap type %", memory_requirements.size, heap_type);
        image.allocator = allocator;

        heap := get_heap(*heap_allocator, image.allocation);
        vkBindImageMemory(logical_device.obj, image.obj, heap.renderer_data.memory, image.allocation.offset);
    } else {
        image.obj = premade_image;
    }

    return image;
}

// views. pass a list of aspect flags. for each item, create an image view.
// VkImageAspectFlags 
//
// COLOR_BIT              :: 0x1;
// DEPTH_BIT              :: 0x2;
// STENCIL_BIT            :: 0x4;
// METADATA_BIT           :: 0x8;
// PLANE_0_BIT            :: 0x10;
// PLANE_1_BIT            :: 0x20;
// PLANE_2_BIT            :: 0x40;
// NONE                   :: 0x0;
// MEMORY_PLANE_0_BIT_EXT :: 0x80;
// MEMORY_PLANE_1_BIT_EXT :: 0x100;
// MEMORY_PLANE_2_BIT_EXT :: 0x200;
// MEMORY_PLANE_3_BIT_EXT :: 0x400;
// PLANE_0_BIT_KHR        :: 0x10;
// PLANE_1_BIT_KHR        :: 0x20;
// PLANE_2_BIT_KHR        :: 0x40;
// NONE_KHR               :: 0x0;
//
// VkImageLayout 
//
// UNDEFINED                                      :: 0;
// GENERAL                                        :: 1;
// COLOR_ATTACHMENT_OPTIMAL                       :: 2;
// DEPTH_STENCIL_ATTACHMENT_OPTIMAL               :: 3;
// DEPTH_STENCIL_READ_ONLY_OPTIMAL                :: 4;
// SHADER_READ_ONLY_OPTIMAL                       :: 5;
// TRANSFER_SRC_OPTIMAL                           :: 6;
// TRANSFER_DST_OPTIMAL                           :: 7;
// PREINITIALIZED                                 :: 8;
// DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL     :: 1000117000;
// DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL     :: 1000117001;
// DEPTH_ATTACHMENT_OPTIMAL                       :: 1000241000;
// DEPTH_READ_ONLY_OPTIMAL                        :: 1000241001;
// STENCIL_ATTACHMENT_OPTIMAL                     :: 1000241002;
// STENCIL_READ_ONLY_OPTIMAL                      :: 1000241003;
// READ_ONLY_OPTIMAL                              :: 1000314000;
// ATTACHMENT_OPTIMAL                             :: 1000314001;
// PRESENT_SRC_KHR                                :: 1000001002;
// VIDEO_DECODE_DST_KHR                           :: 1000024000;
// VIDEO_DECODE_SRC_KHR                           :: 1000024001;
// VIDEO_DECODE_DPB_KHR                           :: 1000024002;
// SHARED_PRESENT_KHR                             :: 1000111000;
// FRAGMENT_DENSITY_MAP_OPTIMAL_EXT               :: 1000218000;
// FRAGMENT_SHADING_RATE_ATTACHMENT_OPTIMAL_KHR   :: 1000164003;
// ATTACHMENT_FEEDBACK_LOOP_OPTIMAL_EXT           :: 1000339000;
// DEPTH_READ_ONLY_STENCIL_ATTACHMENT_OPTIMAL_KHR :: 1000117000;
// DEPTH_ATTACHMENT_STENCIL_READ_ONLY_OPTIMAL_KHR :: 1000117001;
// SHADING_RATE_OPTIMAL_NV                        :: 1000164003;
// DEPTH_ATTACHMENT_OPTIMAL_KHR                   :: 1000241000;
// DEPTH_READ_ONLY_OPTIMAL_KHR                    :: 1000241001;
// STENCIL_ATTACHMENT_OPTIMAL_KHR                 :: 1000241002;
// STENCIL_READ_ONLY_OPTIMAL_KHR                  :: 1000241003;
// READ_ONLY_OPTIMAL_KHR                          :: 1000314000;
// ATTACHMENT_OPTIMAL_KHR                         :: 1000314001;
create_image_views :: (image: *GPU_Image, create_views: ..GPU_Image_View_Info) -> bool {
    for info : create_views {
        view_create_info := image_view_create_info(image.format, image.obj, info.aspect_flags, image.mip_count);
        view := array_add(*image.views);
        view.info = info;
        if !render_evaluate(vkCreateImageView(logical_device.obj, *view_create_info, null, *view.obj), "failed to create an image view with info %", info) {
            return false;
        }
    }
    return true;
}

image_view_create_info :: inline (format: VkFormat, image: VkImage, aspect_flags: VkImageAspectFlags, mip_levels: u32 = 1) -> VkImageViewCreateInfo {
    return VkImageViewCreateInfo.{
        viewType = ._2D,
        image = image,
        format = format,
        subresourceRange = .{
            levelCount = mip_levels,
            layerCount = 1,
            aspectMask = aspect_flags
        }
    };
}

// note that the gpu vram allocation is not freed here when using a linear allocator.
// to do that, reset the whole allocator with gpu_linear_allocator_reset_keeping_memory.
// that approach is the easiest way to go for per-world stuff.
destroy_gpu_image :: (image_ptr: **GPU_Image) {
    image := image_ptr.*;
    if image == null {
        return;
    }

    for view : image.views {
        vkDestroyImageView(logical_device.obj, view.obj, null);
    }
    array_reset(*image.views);

    if image.obj != null && image.allocator.proc != null {
        vkDestroyImage(logical_device.obj, image.obj, null);
        gpu_free(image.allocator, image.allocation);
    }

    pool_return(*images, image);
    image_ptr.* = null;
}

// usage_flags is how this buffer will be used. it determines alignment, and has to be a subset of
// the usage of the heap type's buffers (see determine_buffer_usage).
create_gpu_buffer :: (allocator: Allocator, heap_type: GPU_Heap_Type, size: int, usage_flags: VkBufferUsageFlags) -> GPU_Buffer {
    render_check(is_buffer_type(heap_type));
    render_check(allocator.proc != null);
    render_check((usage_flags & ~determine_buffer_usage(heap_type)) == 0, "usage % not supported by heap type %", usage_flags, heap_type);

    align := ifx is_packed_buffer_type(heap_type) then 1 else max(usage_alignment(usage_flags), 1);

    buffer := GPU_Buffer.{allocator = allocator, size = size, usage_flags = usage_flags};
    success: bool;
    buffer.allocation, success = gpu_alloc(allocator, heap_type, size, align);
    render_check(success, "failed to allocate % bytes for a buffer of heap type %", size, heap_type);
    return buffer;
}

destroy_gpu_buffer :: (buffer: *GPU_Buffer) {
    if buffer.allocator.proc != null {
        gpu_free(buffer.allocator, buffer.allocation);
    }
    buffer.* = {};
}

allocate_material :: (mat: *Material) -> s32 {
    new_mat_index := pool_borrow(*materials);
    render_check(new_mat_index != -1);
    update_material(xx new_mat_index, mat);
    return xx new_mat_index;
}

// every buffer in a heap shares the heap's VkBuffer, so usage is per heap type
determine_buffer_usage :: (heap_type: GPU_Heap_Type) -> VkBufferUsageFlags {
    if heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER {
        return .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT;
    } else if heap_type == .INDEX_BUFFER {
        return .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT;
    } else if is_buffer_type(heap_type) {
        return 
              .TRANSFER_SRC_BIT
            | .TRANSFER_DST_BIT
            | .UNIFORM_TEXEL_BUFFER_BIT
            | .STORAGE_TEXEL_BUFFER_BIT
            | .UNIFORM_BUFFER_BIT
            | .STORAGE_BUFFER_BIT
            | .INDIRECT_BUFFER_BIT;
    }
    return 0;
}


renderer_backend_allocate_gpu_heap :: (heap: *GPU_Heap, size: int, info: GPU_Alloc_Info) -> bool {
    render_check(size > 0);

    _, memory_index := heap_type_and_memory_index(info.type);
    allocate_info := VkMemoryAllocateInfo.{
        allocationSize = xx size,
        memoryTypeIndex = memory_index
    };

    memory: VkDeviceMemory;

    if !render_evaluate(vkAllocateMemory(logical_device.obj, *allocate_info, null, *memory), "failed to allocate a heap of type %, size %", info.type, size) {
        return false;
    }

    buffer: VkBuffer;
    buffer_usage := determine_buffer_usage(info.type);
    min_alignment: u32 = 0;

    if is_buffer_type(info.type) {
        create_info := VkBufferCreateInfo.{
            size        = xx size,
            usage       = buffer_usage,
            sharingMode = .EXCLUSIVE
        };

        memory_requirements: VkMemoryRequirements;
        vkCreateBuffer(logical_device.obj, *create_info, null, *buffer);
        vkGetBufferMemoryRequirements(logical_device.obj, buffer, *memory_requirements);
        // todo:
        // 5. You allocate memory before you know the requirements. The correct order is vkCreateBuffer, then vkGetBufferMemoryRequirements, then pick a memory type that’s in memoryTypeBits, then allocate memory_requirements.size, which can exceed size, then bind. As written, the memory type index never checks memoryTypeBits, and the allocation can be smaller than the buffer needs. Either one makes vkBindBufferMemory invalid.
        // 6. vkCreateBuffer and vkBindBufferMemory results are unchecked. On the failure path, the memory or buffer leaks.
        // buffer usage can't be ignored...
        min_alignment = xx memory_requirements.alignment;
        vkBindBufferMemory(logical_device.obj, buffer, memory, 0);
    }

    // vertices and indices should be packed without align padding
    // they can all be 
    if info.type == .VERTEX_BUFFER || info.type == .INDEX_BUFFER || info.type == .SKINNED_VERTEX_BUFFER {
        min_alignment = 1;
    }

    heap.* = GPU_Heap.{
        size                 = xx size,
        type                 = info.type,
        min_alignment        = min_alignment,
        renderer_data        = {
            memory               = memory,
            buffer               = buffer,
            buffer_usage         = buffer_usage,
        }
    };

    return true;
}

renderer_backend_free_gpu_heap :: (heap: *GPU_Heap) {
    if is_buffer_type(heap.type) {
        vkDestroyBuffer(logical_device.obj, heap.renderer_data.buffer, null);
    }
    vkFreeMemory(logical_device.obj, heap.renderer_data.memory, null);
    heap.* = {};
}

#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

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
    NONE;
    LINEAR;
    DYNAMIC;
}

DEPTH_VIEW_ATTACHMENT :: 0;
DEPTH_VIEW_SAMPLING   :: 1;

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

GPU_Image_View_Info :: struct {
    aspect_flags:    VkImageAspectFlags;
    expected_layout: VkImageLayout;
}

GPU_Image_View :: struct {
    obj:             VkImageView;
    using info: GPU_Image_View_Info;
}

GPU_Image :: struct {
    using #as allocation: GPU_Allocation;
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

get_allocator :: (image: *GPU_Image) -> GPU_Allocator {
    if image.source_heap < 0 {
        return .NONE;
    }
    heap := *gpu_heaps[image.source_heap];
    return heap.allocator;
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
create_gpu_image :: (allocator: GPU_Allocator, heap_type: GPU_Heap_Type, width: s32, height: s32, usage_flags: VkImageUsageFlags, format := VkFormat.R8G8B8A8_UNORM, mip_count: u32 = 1, layer_count: u32 = 1, premade_image: VkImage = null) ->  *GPU_Image {
    // if no allocator, must assign an image object
    render_check((premade_image != null) == (allocator == .NONE));

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

    if allocator != .NONE {
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
    } else {
        image.obj = premade_image;
    }

    align : int = xx memory_requirements.alignment;
    size  : int = xx memory_requirements.size;

    if allocator == {
    case .NONE;
    case .LINEAR;
        image.allocation = gpu_linear_allocate_aligned(size, align, heap_type, false);
    case .DYNAMIC;
        image.allocation = gpu_dynamic_allocate_aligned(size, heap_type);
    }

    if allocator != .NONE {
        heap := *gpu_heaps[image.allocation.source_heap];
        vkBindImageMemory(logical_device.obj, image.obj, heap.memory, xx image.allocation.source_heap_offset);
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
// to do that, you have to free the heap that a series of linear allocations are in
// OR keep the allocations and just reset the whole allocator with gpu_linear_allocator_reset.
// that approach is the easiest way to go for per-world stuff.
destroy_gpu_image :: (image_ptr: **GPU_Image) {
    image := image_ptr.*;
    if image == null {
        return;
    }

    allocator := get_allocator(image);

    for view : image.views {
        vkDestroyImageView(logical_device.obj, view.obj, null);
    }
    array_reset(*image.views);

    if image.obj != null && allocator != .NONE {
        vkDestroyImage(logical_device.obj, image.obj, null);
    }

    if allocator == .DYNAMIC {
        free_gpu_heap(image.source_heap);
    }

    pool_return(*images, image);
    image_ptr.* = null;
}

create_gpu_buffer :: (allocator: GPU_Allocator, heap_type: GPU_Heap_Type, size: int, usage_flags: VkBufferUsageFlags, temp := false) -> GPU_Buffer {
    render_check(is_buffer_type(heap_type));
    render_check(allocator != .NONE);

    if temp then render_check(allocator == .LINEAR);

    align := usage_alignment(usage_flags);
    buffer: GPU_Buffer;
    if allocator == .LINEAR {
        buffer = GPU_Buffer.{
            allocation = gpu_linear_allocate_aligned(size, align, heap_type, temp, usage_flags),
            usage_flags = usage_flags
        };
    } else {
        render_check(!temp);
        buffer = GPU_Buffer.{
            allocation = gpu_dynamic_allocate_aligned(size, heap_type, usage_flags),
            usage_flags = usage_flags
        };
    }

    return buffer;
}

gpu_dynamic_allocate_aligned :: (size: int, type: GPU_Heap_Type, usage_flags: VkBufferUsageFlags = 0) -> GPU_Allocation {
    return GPU_Allocation.{
        source_heap = allocate_gpu_heap(size, type, .DYNAMIC, usage_flags),
        size        = xx size
    };
}

allocate_material :: (mat: *Material) -> s32 {
    new_mat_index := pool_borrow(*materials);
    render_check(new_mat_index != -1);
    update_material(xx new_mat_index, mat);
    return xx new_mat_index;
}

determine_buffer_usage :: (heap_type: GPU_Heap_Type) -> VkBufferUsageFlags {
    if heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER {
        return .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT;
        // there can be only one vertex buffer, because all draws use one buffer for draw simplicity
        render_check(allocator.heaps.count == 0);
    } else if heap_type == .INDEX_BUFFER {
        return .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT;
        // there can be only one index buffer, because all draws use one buffer for draw simplicity
        render_check(allocator.heaps.count == 0);
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

allocate_gpu_heap :: (size: int, type: GPU_Heap_Type, allocator: GPU_Allocator, buffer_usage: VkBufferUsageFlags = 0) -> s16 {
    render_check(allocator != .NONE);
    render_check(size > 0);

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

    heap_index := cast(u16) pool_borrow(*gpu_heaps);
    heap := *gpu_heaps[heap_index];

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

free_gpu_heap :: (heap_index: s16) {
    heap := *gpu_heaps[heap_index];
    if is_buffer_type(heap.type) {
        vkDestroyBuffer(logical_device.obj, heap.buffer, null);
    }
    vkFreeMemory(logical_device.obj, heap.memory, null);
    pool_return(*gpu_heaps, heap_index);
}

initialize_allocators :: () -> bool {
    using engine.renderer;
    // images are bound into heaps that exist before the images do, so probe which memory types
    // images can use with a throwaway image. buffer heaps check their own buffer's requirements.
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
    dummy_image_requirements: VkMemoryRequirements;

    if !render_evaluate(vkCreateImage(logical_device.obj, *dummy_image_create_info, null, *dummy_image), "failed to create the memory type probe image") then return false;
    vkGetImageMemoryRequirements(logical_device.obj, dummy_image, *dummy_image_requirements);
    vkDestroyImage(logical_device.obj, dummy_image, null);

    physical_device.properties.image_memory_type_bits = dummy_image_requirements.memoryTypeBits;
    vkGetPhysicalDeviceMemoryProperties(physical_device.obj, *physical_device.properties.memory_properties);

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
    // shaders reach a buffer allocation at device_address + allocation offset
    device_address: VkDeviceAddress;
    // only valid for host visible heaps, which stay mapped for their whole lifetime
    mapped: *u8;
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
    // index into the shaders' texture array. -1 if the image isn't sampled through it.
    texture_slot:         s32 = -1;
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
    using engine.renderer;
    return !is_host_visible_type(heap_type);
}

is_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    using engine.renderer;
    return heap_type != .NONE && heap_type <= .INDEX_BUFFER;
}

is_image_type :: (heap_type: GPU_Heap_Type) -> bool {
    using engine.renderer;
    return heap_type >= .DEVICE_LOCAL_IMAGE;
}

// vertices and indices are packed without align padding
is_packed_buffer_type :: (heap_type: GPU_Heap_Type) -> bool {
    using engine.renderer;
    return heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER || heap_type == .INDEX_BUFFER;
}

is_host_visible_type :: (heap_type: GPU_Heap_Type) -> bool {
    using engine.renderer;
    if heap_type == {
    case .HOST_VISIBLE_BUFFER;
        return true;
    case .HOST_VISIBLE_IMAGE;
        return true;
    case .STAGING_BUFFER;
        return true;
    }
    return false;
}

// memory properties to try for a heap type, most preferred first
memory_property_preferences :: (heap_type: GPU_Heap_Type) -> []VkMemoryPropertyFlags {
    using engine.renderer;
    // host visible buffers hold data the cpu writes every frame and the gpu reads directly.
    // device local + host visible (resizable bar) makes those reads cheaper when available.
    HOST_VISIBLE_BUFFER_PREFERENCES :: VkMemoryPropertyFlags.[
        .DEVICE_LOCAL_BIT | .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
        .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT
    ];
    HOST_VISIBLE_PREFERENCES :: VkMemoryPropertyFlags.[.HOST_VISIBLE_BIT | .HOST_COHERENT_BIT];
    DEVICE_LOCAL_PREFERENCES :: VkMemoryPropertyFlags.[.DEVICE_LOCAL_BIT];

    if heap_type == .HOST_VISIBLE_BUFFER {
        return HOST_VISIBLE_BUFFER_PREFERENCES;
    } else if is_host_visible_type(heap_type) {
        return HOST_VISIBLE_PREFERENCES;
    } 
    return DEVICE_LOCAL_PREFERENCES;
}

// tries each preferred memory type in order. a preferred type's heap can run out (resizable bar
// is sometimes only 256MB), so a failed allocation falls through to the next preference.
allocate_heap_memory :: (heap_type: GPU_Heap_Type, memory_type_bits: u32, size: int) -> VkDeviceMemory, success: bool {
    using engine.renderer;
    flags_info := VkMemoryAllocateFlagsInfo.{flags = .DEVICE_ADDRESS_BIT};

    for props : memory_property_preferences(heap_type) {
        memory_index := find_index_of_memory_type(memory_type_bits, props, *physical_device.properties.memory_properties);
        if memory_index == INVALID_MEMORY_TYPE_INDEX {
            continue;
        }

        allocate_info := VkMemoryAllocateInfo.{
            allocationSize  = xx size,
            memoryTypeIndex = memory_index
        };
        if is_buffer_type(heap_type) {
            allocate_info.pNext = *flags_info;
        }

        memory: VkDeviceMemory;
        if vkAllocateMemory(logical_device.obj, *allocate_info, null, *memory) == .SUCCESS {
            return memory, true;
        }
    }
    return null, false;
}

usage_alignment :: inline (usage_flags: VkBufferUsageFlags) -> int {
    using engine.renderer;
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
    using engine.renderer;
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
    using engine.renderer;
    push_allocator(allocator, align, .{type = heap_type});
    memory := alloc(size);
    return unmask_gpu_allocation(memory), memory != null;
}

gpu_free :: (allocator: Allocator, allocation: GPU_Allocation) {
    using engine.renderer;
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
    using engine.renderer;
    // if no allocator, must assign an image object
    render_check((premade_image != null) == (allocator.proc == null));

    // allocated individually so that pointers to images stay valid and there's no image limit
    image := New(GPU_Image);

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

        render_evaluate(vkCreateImage(logical_device.obj, *create_info, null, *image.obj), "failed to create an image");
        vkGetImageMemoryRequirements(logical_device.obj, image.obj, *memory_requirements);
        render_check((memory_requirements.memoryTypeBits & physical_device.properties.image_memory_type_bits) != 0, "image can't use the memory types image heaps are made with");

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
    using engine.renderer;
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

// the image's view made for this layout, or null if it has none
get_image_view :: (image: *GPU_Image, expected_layout: VkImageLayout) -> VkImageView {
    for image.views {
        if it.expected_layout == expected_layout {
            return it.obj;
        }
    }
    return null;
}

image_view_create_info :: inline (format: VkFormat, image: VkImage, aspect_flags: VkImageAspectFlags, mip_levels: u32 = 1) -> VkImageViewCreateInfo {
    using engine.renderer;
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
    using engine.renderer;
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

    release_texture_slot(image);
    free(image);
    image_ptr.* = null;
}

// usage_flags is how this buffer will be used. it determines alignment, and has to be a subset of
// the usage of the heap type's buffers (see determine_buffer_usage).
create_gpu_buffer :: (allocator: Allocator, heap_type: GPU_Heap_Type, size: int, usage_flags: VkBufferUsageFlags) -> GPU_Buffer {
    using engine.renderer;
    render_check(is_buffer_type(heap_type));
    render_check(allocator.proc != null);
    render_check((usage_flags & ~determine_buffer_usage(heap_type)) == 0, "usage % not supported by heap type %", usage_flags, heap_type);

    // packed buffers only need 4 byte alignment: vertices are pulled as 4 byte scalars, indices are u32
    align := ifx is_packed_buffer_type(heap_type) then 4 else max(usage_alignment(usage_flags), 1);

    buffer := GPU_Buffer.{allocator = allocator, size = size, usage_flags = usage_flags};
    success: bool;
    buffer.allocation, success = gpu_alloc(allocator, heap_type, size, align);
    render_check(success, "failed to allocate % bytes for a buffer of heap type %", size, heap_type);
    return buffer;
}

destroy_gpu_buffer :: (buffer: *GPU_Buffer) {
    using engine.renderer;
    if buffer.allocator.proc != null {
        gpu_free(buffer.allocator, buffer.allocation);
    }
    buffer.* = {};
}

allocate_material :: (mat: *Material) -> s32 {
    using engine.renderer;
    new_mat_index := pool_borrow(*materials);
    render_check(new_mat_index != -1);
    update_material(xx new_mat_index, mat);
    return xx new_mat_index;
}

// every buffer in a heap shares the heap's VkBuffer, so usage is per heap type.
// shaders read every buffer through its device address, including vertices (vertex pulling).
determine_buffer_usage :: (heap_type: GPU_Heap_Type) -> VkBufferUsageFlags {
    using engine.renderer;
    if heap_type == .VERTEX_BUFFER || heap_type == .SKINNED_VERTEX_BUFFER {
        return .STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT;
    } else if heap_type == .INDEX_BUFFER {
        return .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT;
    } else if is_buffer_type(heap_type) {
        return
              .TRANSFER_SRC_BIT
            | .TRANSFER_DST_BIT
            | .UNIFORM_TEXEL_BUFFER_BIT
            | .STORAGE_TEXEL_BUFFER_BIT
            | .UNIFORM_BUFFER_BIT
            | .STORAGE_BUFFER_BIT
            | .INDIRECT_BUFFER_BIT
            | .SHADER_DEVICE_ADDRESS_BIT;
    }
    return 0;
}

// the address shaders use to reach this buffer
gpu_address :: inline (buffer: GPU_Buffer) -> VkDeviceAddress {
    using engine.renderer;
    heap := get_heap(*heap_allocator, buffer.allocation);
    return heap.renderer_data.device_address + buffer.allocation.offset;
}

// where the cpu writes this buffer's contents. only for buffers in host visible heaps.
gpu_mapped :: inline (buffer: GPU_Buffer) -> *u8 {
    using engine.renderer;
    heap := get_heap(*heap_allocator, buffer.allocation);
    render_check(heap.renderer_data.mapped != null, "buffer isn't in a host visible heap");
    return heap.renderer_data.mapped + buffer.allocation.offset;
}

// the VkBuffer and offset to pass to commands that take buffers (copies, index binding, indirect draws)
gpu_vk_buffer :: inline (buffer: GPU_Buffer) -> VkBuffer, VkDeviceSize {
    using engine.renderer;
    heap := get_heap(*heap_allocator, buffer.allocation);
    return heap.renderer_data.buffer, buffer.allocation.offset;
}

renderer_backend_allocate_gpu_heap :: (heap: *GPU_Heap, size: int, info: GPU_Alloc_Info) -> bool {
    using engine.renderer;
    render_check(size > 0);

    buffer: VkBuffer;
    buffer_usage := determine_buffer_usage(info.type);
    memory_type_bits := physical_device.properties.image_memory_type_bits;
    allocation_size := size;
    min_alignment: u32 = 0;

    if is_buffer_type(info.type) {
        create_info := VkBufferCreateInfo.{
            size        = xx size,
            usage       = buffer_usage,
            sharingMode = .EXCLUSIVE
        };
        if !render_evaluate(vkCreateBuffer(logical_device.obj, *create_info, null, *buffer), "failed to create the buffer for a heap of type %, size %", info.type, size) {
            return false;
        }

        memory_requirements: VkMemoryRequirements;
        vkGetBufferMemoryRequirements(logical_device.obj, buffer, *memory_requirements);
        memory_type_bits = memory_requirements.memoryTypeBits;
        allocation_size  = xx memory_requirements.size;
        min_alignment    = xx memory_requirements.alignment;
    }

    memory, allocated := allocate_heap_memory(info.type, memory_type_bits, allocation_size);
    if !render_evaluate(allocated, "failed to allocate a heap of type %, size %", info.type, allocation_size) {
        if buffer != null then vkDestroyBuffer(logical_device.obj, buffer, null);
        return false;
    }

    device_address: VkDeviceAddress;
    if is_buffer_type(info.type) {
        if !render_evaluate(vkBindBufferMemory(logical_device.obj, buffer, memory, 0), "failed to bind a heap's buffer to its memory") {
            vkDestroyBuffer(logical_device.obj, buffer, null);
            vkFreeMemory(logical_device.obj, memory, null);
            return false;
        }
        address_info := VkBufferDeviceAddressInfo.{buffer = buffer};
        device_address = vkGetBufferDeviceAddress(logical_device.obj, *address_info);
    }

    mapped: *u8;
    if is_host_visible_type(info.type) {
        if !render_evaluate(vkMapMemory(logical_device.obj, memory, 0, VK_WHOLE_SIZE, 0, xx *mapped), "failed to map a host visible heap") {
            if buffer != null then vkDestroyBuffer(logical_device.obj, buffer, null);
            vkFreeMemory(logical_device.obj, memory, null);
            return false;
        }
    }

    // vertices and indices are packed with only the 4 byte alignment their scalars need
    if is_packed_buffer_type(info.type) {
        min_alignment = 4;
    }

    heap.* = GPU_Heap.{
        size                 = xx size,
        type                 = info.type,
        min_alignment        = min_alignment,
        renderer_data        = {
            memory               = memory,
            buffer               = buffer,
            buffer_usage         = buffer_usage,
            device_address       = device_address,
            mapped               = mapped,
        }
    };

    return true;
}

renderer_backend_free_gpu_heap :: (heap: *GPU_Heap) {
    using engine.renderer;
    if heap.renderer_data.mapped != null {
        vkUnmapMemory(logical_device.obj, heap.renderer_data.memory);
    }
    if is_buffer_type(heap.type) {
        vkDestroyBuffer(logical_device.obj, heap.renderer_data.buffer, null);
    }
    vkFreeMemory(logical_device.obj, heap.renderer_data.memory, null);
    heap.* = {};
}

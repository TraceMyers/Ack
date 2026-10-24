Renderer_Backend :: struct {
    using #as base: Renderer_Backend_Base;

    API          :: "vulkan";
    API_VERSION  :: #run VK_MAKE_VERSION(1, 3, 0);

    DEPTH_STENCIL_FORMATS          :: VkFormat.[.D24_UNORM_S8_UINT, .D32_SFLOAT_S8_UINT];
    INVALID_MEMORY_TYPE_INDEX : u32 : 0xffff_ffff;
    FRAMES_IN_FLIGHT               :: 2;
    RENDER_TARGET_FORMAT           :: VkFormat.R16G16B16A16_SFLOAT;

    should_recreate_swapchain: bool;

    vk_instance:     VkInstance;
    surface:         VkSurfaceKHR;
    physical_device: Physical_Device;
    logical_device:  Logical_Device;
    swapchain:       Swapchain;
    render_target:   *GPU_Image;
    depth_buffer:    *GPU_Image;
    graphics_queue:  VkQueue; // per thread?
    transfer_queue:  VkQueue; // per thread?

    frames: []GPU_Frame;

    // vulkan objects that frames in flight may still use. destroyed once those frames finish.
    deferred_destroys: [..]Deferred_Destroy;

    // the only descriptor set. holds the bindless texture array. buffers are reached by address.
    textures: Texture_Descriptors;
    sampler_table: Table(u32, VkSampler);

    uploads: Upload_State;

    // one GPU_Material per entry in the materials pool
    materials_buffer: GPU_Buffer;

    // every pipeline uses this layout: the texture set + Push_Constants
    pipeline_layout: VkPipelineLayout;
    pipelines: [GRAPHICS_PIPELINE_COUNT]VkPipeline;
}

Deferred_Destroy :: struct {
    // destroyed once rendered_frame_count reaches this
    retire_frame: u64;
    type: enum u8 {
        DESCRIPTOR_POOL;
        TEXTURE_SLOT;
    };
    descriptor_pool: VkDescriptorPool;
    texture_slot: s32;
}

defer_destroy :: (item: Deferred_Destroy) {
    using engine.renderer;
    destroy := item;
    destroy.retire_frame = rendered_frame_count + xx frames.count;
    array_add(*deferred_destroys, destroy);
}

// call after waiting on the current frame's fence
process_deferred_destroys :: () {
    using engine.renderer;
    for < deferred_destroys {
        if it.retire_frame > rendered_frame_count {
            continue;
        }
        if it.type == {
        case .DESCRIPTOR_POOL;
            vkDestroyDescriptorPool(logical_device.obj, it.descriptor_pool, null);
        case .TEXTURE_SLOT;
            array_add(*textures.free_slots, it.texture_slot);
        }
        remove it;
    }
}

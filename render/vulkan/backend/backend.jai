Renderer_Backend :: struct {
    using #as base: Renderer_Backend_Base;

    API          :: "vulkan";
    API_VERSION  :: #run VK_MAKE_VERSION(1, 3, 0);
    DEPTH_FORMAT :: VkFormat.D24_UNORM_S8_UINT;
    INVALID_MEMORY_TYPE_INDEX : u32 : 0xffff_ffff;

    should_recreate_swapchain: bool;

    vk_instance: VkInstance;
    surface:     VkSurfaceKHR;
    graphics_queue: VkQueue; // per thread?
    transfer_queue: VkQueue; // per thread?

    pipelines:              [..]VkPipeline;
    pipeline_layouts:       [..]VkPipelineLayout;
    descriptor_sets:        [..]VkDescriptorSet;
    descriptor_set_layouts: [..]VkDescriptorSetLayout;

    linear_allocators: [GPU_HEAP_TYPE_COUNT]GPU_Linear_Allocator;
}


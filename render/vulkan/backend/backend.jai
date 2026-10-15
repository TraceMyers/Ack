Renderer_Backend :: struct {
    using #as base: Renderer_Backend_Base;

    API         :: "vulkan";
    API_VERSION :: VK_API_VERSION_1_3;

    should_recreate_swapchain: bool;

    // instead, should reference swapchain image size
    // window_dimensions: Vector2i;

    pipelines:              [..]VkPipeline;
    pipeline_layouts:       [..]VkPipelineLayout;
    descriptor_sets:        [..]VkDescriptorSet;
    descriptor_set_layouts: [..]VkDescriptorSetLayout;
}


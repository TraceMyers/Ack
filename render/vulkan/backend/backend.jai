Renderer_Backend :: struct {
    using #as base: Renderer_Backend_Base;

    in_the_middle_of_rendering: bool;
    should_recreate_swapchain: bool;

    pipelines:              [..]VkPipeline;
    pipeline_layouts:       [..]VkPipelineLayout;
    descriptor_sets:        [..]VkDescriptorSet;
    descriptor_set_layouts: [..]VkDescriptorSetLayout;
}


GPU_Frame :: struct {
    command_pool:               VkCommandPool;
    command_buffer:             VkCommandBuffer;

    image_available_semaphore:  VkSemaphore;
    render_fence:               VkFence;

    // reset at the start of the frame. per-frame shader data (Frame_Data, instances, draw
    // sections, joints, draw commands) is written straight into this from the cpu.
    temp_allocator: GPU_Linear_Allocator;
}

get_current_frame :: () -> frame: *GPU_Frame, index: int {
    using engine.renderer;

    index := cast(int) (rendered_frame_count % xx frames.count);
    return *frames[index], index;
}

create_frames :: () -> bool {
    using engine.renderer;

    render_check(frames.data == null);
    frames = NewArray(FRAMES_IN_FLIGHT, GPU_Frame);

    command_pool_info := VkCommandPoolCreateInfo.{
        flags            = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = physical_device.queue_family_indices.graphics_index
    };
    // signaled so the first wait on each frame doesn't block
    fence_info     := VkFenceCreateInfo.{flags = .SIGNALED_BIT};
    semaphore_info := VkSemaphoreCreateInfo.{};

    for *frames {
        if !render_evaluate(vkCreateCommandPool(logical_device.obj, *command_pool_info, null, *it.command_pool), "failed to create a frame command pool") then return false;

        command_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool        = it.command_pool,
            commandBufferCount = 1,
            level              = .PRIMARY
        };
        if !render_evaluate(vkAllocateCommandBuffers(logical_device.obj, *command_alloc_info, *it.command_buffer), "failed to allocate a frame command buffer") then return false;
        if !render_evaluate(vkCreateFence(logical_device.obj, *fence_info, null, *it.render_fence), "failed to create a frame render fence") then return false;
        if !render_evaluate(vkCreateSemaphore(logical_device.obj, *semaphore_info, null, *it.image_available_semaphore), "failed to create a frame semaphore") then return false;

        it.temp_allocator.heap_allocator = *heap_allocator;
        gpu_linear_allocator_startup(*it.temp_allocator);
    }

    render_log("created frames. max frames in flight %", frames.count, flags=.VERBOSE_ONLY);
    return true;
}

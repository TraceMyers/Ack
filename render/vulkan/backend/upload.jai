// copying data into gpu buffers and images.
//
// host visible buffers are written directly through their mapping. device local buffers and images
// are staged: call begin_upload, upload as much as you want, then end_upload, which submits
// everything at once and waits for it. uploads run on the graphics queue, so nothing has to
// change queue family ownership.

Upload_State :: struct {
    command_pool:      VkCommandPool;
    command_buffer:    VkCommandBuffer;
    fence:             VkFence;
    staging_allocator: GPU_Linear_Allocator;
    recording:         bool;
}

create_upload_state :: () -> bool {
    using engine.renderer;

    pool_info := VkCommandPoolCreateInfo.{
        flags            = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = physical_device.queue_family_indices.graphics_index
    };
    if !render_evaluate(vkCreateCommandPool(logical_device.obj, *pool_info, null, *uploads.command_pool), "failed to create the upload command pool") then return false;

    alloc_info := VkCommandBufferAllocateInfo.{
        commandPool        = uploads.command_pool,
        commandBufferCount = 1,
        level              = .PRIMARY
    };
    if !render_evaluate(vkAllocateCommandBuffers(logical_device.obj, *alloc_info, *uploads.command_buffer), "failed to allocate the upload command buffer") then return false;

    fence_info := VkFenceCreateInfo.{};
    if !render_evaluate(vkCreateFence(logical_device.obj, *fence_info, null, *uploads.fence), "failed to create the upload fence") then return false;

    uploads.staging_allocator.heap_allocator = *heap_allocator;
    gpu_linear_allocator_startup(*uploads.staging_allocator);
    return true;
}

begin_upload :: () {
    using engine.renderer;
    render_check(!uploads.recording, "begin_upload called twice without end_upload");
    begin_command_buffer(uploads.command_buffer);
    uploads.recording = true;
}

// submits everything recorded since begin_upload and waits for it to finish
end_upload :: () -> bool {
    using engine.renderer;
    render_check(uploads.recording, "end_upload called without begin_upload");
    uploads.recording = false;
    cmd := uploads.command_buffer;

    // make the copies visible to everything submitted after this
    barrier := VkMemoryBarrier2.{
        srcStageMask  = VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT,
        srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT,
        dstStageMask  = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        dstAccessMask = VK_ACCESS_2_MEMORY_READ_BIT
    };
    dependency := VkDependencyInfo.{memoryBarrierCount = 1, pMemoryBarriers = *barrier};
    vkCmdPipelineBarrier2(cmd, *dependency);

    if !render_evaluate(vkEndCommandBuffer(cmd), "failed to end the upload command buffer") then return false;

    cmd_info    := VkCommandBufferSubmitInfo.{commandBuffer = cmd};
    submit_info := VkSubmitInfo2.{commandBufferInfoCount = 1, pCommandBufferInfos = *cmd_info};
    if !render_evaluate(vkQueueSubmit2(graphics_queue, 1, *submit_info, uploads.fence), "failed to submit uploads") then return false;
    if !render_evaluate(vkWaitForFences(logical_device.obj, 1, *uploads.fence, VK_TRUE, U64_MAX), "failed waiting for uploads") then return false;
    vkResetFences(logical_device.obj, 1, *uploads.fence);

    gpu_linear_allocator_reset_keeping_memory(*uploads.staging_allocator);
    return true;
}

upload_buffer :: (dst: GPU_Buffer, data: *void, size: int, dst_offset := 0) {
    using engine.renderer;
    render_check(dst_offset >= 0 && dst_offset + size <= dst.size, "upload of % bytes at offset % doesn't fit in a % byte buffer", size, dst_offset, dst.size);
    if size == 0 {
        return;
    }

    heap := get_heap(*heap_allocator, dst.allocation);
    if heap.renderer_data.mapped != null {
        memcpy(gpu_mapped(dst) + dst_offset, data, size);
        return;
    }

    render_check(uploads.recording, "uploads to device local buffers go between begin_upload and end_upload");
    staging := create_gpu_buffer(uploads.staging_allocator, .HOST_VISIBLE_BUFFER, size, .TRANSFER_SRC_BIT);
    memcpy(gpu_mapped(staging), data, size);

    src_buffer, src_offset := gpu_vk_buffer(staging);
    dst_buffer, dst_base   := gpu_vk_buffer(dst);
    region := VkBufferCopy.{
        srcOffset = src_offset,
        dstOffset = dst_base + xx dst_offset,
        size      = xx size
    };
    vkCmdCopyBuffer(uploads.command_buffer, src_buffer, dst_buffer, 1, *region);
}

upload_buffer :: inline (dst: GPU_Buffer, array: []$T, dst_offset := 0) {
    upload_buffer(dst, array.data, array.count * size_of(T), dst_offset);
}

// fills mip 0 of a 2d image and leaves it ready for sampling. pixels must cover the whole image.
upload_image :: (image: *GPU_Image, pixels: *void, size: int) {
    using engine.renderer;
    render_check(uploads.recording, "image uploads go between begin_upload and end_upload");
    render_check(image.format == .R8G8B8A8_UNORM || image.format == .R8G8B8A8_SRGB, "upload_image only handles 4 byte rgba formats");
    render_check(size == image.extent.width * image.extent.height * 4, "upload of % bytes doesn't match a %x% rgba image", size, image.extent.width, image.extent.height);

    staging := create_gpu_buffer(uploads.staging_allocator, .HOST_VISIBLE_BUFFER, size, .TRANSFER_SRC_BIT);
    memcpy(gpu_mapped(staging), pixels, size);
    src_buffer, src_offset := gpu_vk_buffer(staging);

    cmd := uploads.command_buffer;
    transition_image(cmd, image, .TRANSFER_DST_OPTIMAL);

    region := VkBufferImageCopy.{
        bufferOffset     = src_offset,
        imageSubresource = .{aspectMask = .COLOR_BIT, layerCount = 1},
        imageExtent      = image.extent
    };
    vkCmdCopyBufferToImage(cmd, src_buffer, image.obj, .TRANSFER_DST_OPTIMAL, 1, *region);

    transition_image(cmd, image, .SHADER_READ_ONLY_OPTIMAL);
}

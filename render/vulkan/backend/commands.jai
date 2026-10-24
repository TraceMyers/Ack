begin_command_buffer :: (cmd: VkCommandBuffer) -> bool {
    using engine.renderer;
    begin_info := VkCommandBufferBeginInfo.{flags = .ONE_TIME_SUBMIT_BIT};
    return render_evaluate(vkBeginCommandBuffer(cmd, *begin_info), "failed to begin a command buffer");
}

// a full barrier around the layout change. simple and fine for the handful of transitions per frame.
transition_image :: (cmd: VkCommandBuffer, image: *GPU_Image, new_layout: VkImageLayout) {
    using engine.renderer;
    aspect: VkImageAspectFlags = .COLOR_BIT;
    if image.usage & .DEPTH_STENCIL_ATTACHMENT_BIT {
        aspect = .DEPTH_BIT | .STENCIL_BIT;
    }

    barrier := VkImageMemoryBarrier2.{
        srcStageMask     = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        srcAccessMask    = VK_ACCESS_2_MEMORY_WRITE_BIT,
        dstStageMask     = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        dstAccessMask    = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
        oldLayout        = image.layout,
        newLayout        = new_layout,
        image            = image.obj,
        subresourceRange = .{
            aspectMask = aspect,
            levelCount = VK_REMAINING_MIP_LEVELS,
            layerCount = VK_REMAINING_ARRAY_LAYERS
        }
    };
    dependency := VkDependencyInfo.{imageMemoryBarrierCount = 1, pImageMemoryBarriers = *barrier};
    vkCmdPipelineBarrier2(cmd, *dependency);
    image.layout = new_layout;
}

// copies all of src onto all of dst, scaling if the sizes differ.
// src must be TRANSFER_SRC_OPTIMAL and dst TRANSFER_DST_OPTIMAL.
blit_image :: (cmd: VkCommandBuffer, src: *GPU_Image, dst: *GPU_Image) {
    using engine.renderer;
    region := VkImageBlit2.{
        srcSubresource = .{aspectMask = .COLOR_BIT, layerCount = 1},
        dstSubresource = .{aspectMask = .COLOR_BIT, layerCount = 1},
    };
    region.srcOffsets[1] = .{xx src.extent.width, xx src.extent.height, 1};
    region.dstOffsets[1] = .{xx dst.extent.width, xx dst.extent.height, 1};

    blit_info := VkBlitImageInfo2.{
        srcImage       = src.obj,
        srcImageLayout = .TRANSFER_SRC_OPTIMAL,
        dstImage       = dst.obj,
        dstImageLayout = .TRANSFER_DST_OPTIMAL,
        regionCount    = 1,
        pRegions       = *region,
        filter         = .LINEAR
    };
    vkCmdBlitImage2(cmd, *blit_info);
}

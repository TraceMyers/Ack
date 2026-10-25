// records, submits and presents one frame. returns false if no frame was presented.
render_frame :: () -> bool {
    using engine.renderer;
    auto_release_temp();

    if !is_window_open() || is_window_minimized() then return false;

    currently_updating_renderer = true;
    defer currently_updating_renderer = false;

    frame := get_current_frame();

    if !render_evaluate(vkWaitForFences(logical_device.obj, 1, *frame.render_fence, VK_TRUE, NANOSECONDS_PER_SECOND), "timed out waiting for the frame fence") then return false;

    // everything this frame slot used last time is done now
    gpu_linear_allocator_reset_keeping_memory(*frame.temp_allocator);
    process_deferred_destroys();

    // the swapchain is sized to the window, so a resize means remaking it
    if swapchain.extent.width != xx window_width || swapchain.extent.height != xx window_height {
        should_recreate_swapchain = true;
    }
    if should_recreate_swapchain {
        if !create_swapchain_and_attachments() then return false;
    }

    swapchain_image_index: u32;
    acquire_result := vkAcquireNextImageKHR(logical_device.obj, swapchain.obj, U64_MAX, frame.image_available_semaphore, null, *swapchain_image_index);
    if acquire_result == .ERROR_OUT_OF_DATE_KHR {
        should_recreate_swapchain = true;
        return false;
    } else if acquire_result == .SUBOPTIMAL_KHR {
        // still presentable. recreate next frame.
        should_recreate_swapchain = true;
    } else if !render_evaluate(acquire_result, "failed to acquire a swapchain image") {
        return false;
    }

    // only reset once this frame is sure to submit, or the next wait would never finish
    vkResetFences(logical_device.obj, 1, *frame.render_fence);

    swapchain_image := swapchain.images[swapchain_image_index];
    extent := swapchain.extent;

    frame_data := write_frame_data(frame, .{xx extent.width, xx extent.height});
    mesh_draws := prepare_mesh_draws(frame);
    line_draws := prepare_line_draws(frame);

    cmd := frame.command_buffer;
    vkResetCommandBuffer(cmd, 0);
    if !begin_command_buffer(cmd) then return false;

    // render target and depth are fully redrawn, so their previous contents don't matter
    render_target.layout = .UNDEFINED;
    depth_buffer.layout  = .UNDEFINED;
    transition_image(cmd, render_target, .COLOR_ATTACHMENT_OPTIMAL);
    transition_image(cmd, depth_buffer,  .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

    color_attachment := VkRenderingAttachmentInfo.{
        imageView   = get_image_view(render_target, .COLOR_ATTACHMENT_OPTIMAL),
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp      = .CLEAR,
        storeOp     = .STORE,
    };
    clear_color := config.clear_color;
    color_attachment.clearValue.color._float32 = .[clear_color.r, clear_color.g, clear_color.b, clear_color.a];

    // reversed depth: 1 is near, 0 is far
    depth_attachment := VkRenderingAttachmentInfo.{
        imageView   = get_image_view(depth_buffer, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL),
        imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        loadOp      = .CLEAR,
        storeOp     = .DONT_CARE,
    };
    depth_attachment.clearValue.depthStencil = .{depth = 0, stencil = 0};

    rendering_info := VkRenderingInfo.{
        renderArea           = .{extent = extent},
        layerCount           = 1,
        colorAttachmentCount = 1,
        pColorAttachments    = *color_attachment,
        pDepthAttachment     = *depth_attachment,
        pStencilAttachment   = *depth_attachment,
    };
    vkCmdBeginRendering(cmd, *rendering_info);

    viewport := VkViewport.{width = xx extent.width, height = xx extent.height, minDepth = 0, maxDepth = 1};
    scissor  := VkRect2D.{extent = extent};
    vkCmdSetViewport(cmd, 0, 1, *viewport);
    vkCmdSetScissor(cmd, 0, 1, *scissor);
    vkCmdSetLineWidth(cmd, 1);

    // the texture set is bound once. everything else is reached through push constants.
    vkCmdBindDescriptorSets(cmd, .GRAPHICS, pipeline_layout, 0, 1, *textures.set, 0, null);

    constants: Push_Constants;
    constants.frame     = gpu_address(frame_data);
    constants.materials = gpu_address(materials_buffer);
    if mesh_draws.instances.allocator.proc != null then constants.instances = gpu_address(mesh_draws.instances);
    if mesh_draws.joints.allocator.proc    != null then constants.joints    = gpu_address(mesh_draws.joints);
    if line_draws.vertices.allocator.proc  != null then constants.vertices  = gpu_address(line_draws.vertices);

    // each layer after the first one drawn starts with a clear depth buffer, so it draws over
    // everything before it
    drew_a_layer := false;
    for layer : DRAW_LAYER_ORDER {
        if !layer_has_draws(layer, *mesh_draws, *line_draws) {
            continue;
        }
        if drew_a_layer {
            clear_depth(cmd, extent);
        }
        drew_a_layer = true;

        draw_mesh_buckets(cmd, *mesh_draws, layer, .STATIC,   pipelines[Graphics_Pipeline.OPAQUE_STATIC_MESH],   *constants);
        draw_mesh_buckets(cmd, *mesh_draws, layer, .SKELETAL, pipelines[Graphics_Pipeline.OPAQUE_SKELETAL_MESH], *constants);
        draw_line_batches(cmd, *line_draws, layer, *constants);
    }

    vkCmdEndRendering(cmd);

    // copy the render target onto the swapchain image
    transition_image(cmd, render_target, .TRANSFER_SRC_OPTIMAL);
    swapchain_image.layout = .UNDEFINED;
    transition_image(cmd, swapchain_image, .TRANSFER_DST_OPTIMAL);
    blit_image(cmd, render_target, swapchain_image);
    transition_image(cmd, swapchain_image, .PRESENT_SRC_KHR);

    if !render_evaluate(vkEndCommandBuffer(cmd), "failed to end the frame command buffer") then return false;

    image_rendered := swapchain.image_rendered[swapchain_image_index];
    cmd_info    := VkCommandBufferSubmitInfo.{commandBuffer = cmd};
    wait_info   := VkSemaphoreSubmitInfo.{semaphore = frame.image_available_semaphore, stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
    signal_info := VkSemaphoreSubmitInfo.{semaphore = image_rendered, stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT};
    submit_info := VkSubmitInfo2.{
        waitSemaphoreInfoCount   = 1,
        pWaitSemaphoreInfos      = *wait_info,
        commandBufferInfoCount   = 1,
        pCommandBufferInfos      = *cmd_info,
        signalSemaphoreInfoCount = 1,
        pSignalSemaphoreInfos    = *signal_info,
    };
    if !render_evaluate(vkQueueSubmit2(graphics_queue, 1, *submit_info, frame.render_fence), "failed to submit the frame") then return false;

    present_info := VkPresentInfoKHR.{
        waitSemaphoreCount = 1,
        pWaitSemaphores    = *image_rendered,
        swapchainCount     = 1,
        pSwapchains        = *swapchain.obj,
        pImageIndices      = *swapchain_image_index,
    };
    present_result := vkQueuePresentKHR(graphics_queue, *present_info);
    if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR {
        should_recreate_swapchain = true;
    } else if !render_evaluate(present_result, "failed to present") {
        return false;
    }

    rendered_frame_count += 1;
    return true;
}

#scope_file

write_frame_data :: (frame: *GPU_Frame, viewport: Vector2) -> GPU_Buffer {
    using engine.renderer;
    buffer := create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, size_of(Frame_Data), .STORAGE_BUFFER_BIT);
    data := cast(*Frame_Data) gpu_mapped(buffer);

    // layers don't share the depth range. each gets the whole range and a cleared depth buffer.
    data.view            = make_camera_view_matrix(camera_position, camera_orientation);
    data.view_projection = make_camera_projection_matrix(camera_info, viewport) * data.view;
    data.camera_position = camera_position;
    data.camera_forward  = get_fore_direction(camera_orientation);
    data.camera_up       = get_up_direction(camera_orientation);
    data.camera_right    = get_right_direction(camera_orientation);
    data.light_direction = light_direction;
    data.time            = global_shader_time;
    data.delta_time      = global_shader_delta_time;
    data.camera_near     = camera_info.near_plane;
    data.camera_far      = camera_info.far_plane;
    data.depth_view_mode_max_distance = config.depth_view_mode_max_distance;

    return buffer;
}

layer_has_draws :: (layer: Draw_Layer, mesh_draws: *Mesh_Draws, line_draws: *Line_Draws) -> bool {
    for mesh_draws.buckets {
        if it.layer == layer && it.draw_count > 0 return true;
    }
    for line_draws.batches {
        if it.layer == layer return true;
    }
    return false;
}

clear_depth :: (cmd: VkCommandBuffer, extent: VkExtent2D) {
    clear := VkClearAttachment.{aspectMask = .DEPTH_BIT | .STENCIL_BIT};
    clear.clearValue.depthStencil = .{depth = 0, stencil = 0};
    rect := VkClearRect.{rect = .{extent = extent}, layerCount = 1};
    vkCmdClearAttachments(cmd, 1, *clear, 1, *rect);
}

draw_mesh_buckets :: (cmd: VkCommandBuffer, mesh_draws: *Mesh_Draws, layer: Draw_Layer, type: Mesh_Type, pipeline: VkPipeline, constants: *Push_Constants) {
    using engine.renderer;
    bound := false;

    for mesh_draws.buckets {
        if it.layer != layer || it.type != type || it.draw_count == 0 continue;

        if !bound {
            vkCmdBindPipeline(cmd, .GRAPHICS, pipeline);
            bound = true;
        }

        // gl_DrawID restarts at 0 for each indirect draw, so each bucket gets its own sections pointer
        constants.sections = gpu_address(it.sections);
        push_constants(cmd, constants);

        vkCmdBindIndexBuffer(cmd, it.index_buffer, 0, .UINT32);
        commands_buffer, commands_offset := gpu_vk_buffer(it.commands);
        vkCmdDrawIndexedIndirect(cmd, commands_buffer, commands_offset, it.draw_count, size_of(VkDrawIndexedIndirectCommand));
    }
}

draw_line_batches :: (cmd: VkCommandBuffer, line_draws: *Line_Draws, layer: Draw_Layer, constants: *Push_Constants) {
    using engine.renderer;
    bound := false;

    for line_draws.batches {
        if it.layer != layer continue;

        if !bound {
            vkCmdBindPipeline(cmd, .GRAPHICS, pipelines[Graphics_Pipeline.OPAQUE_LINE]);
            push_constants(cmd, constants);
            bound = true;
        }

        vkCmdSetLineWidth(cmd, it.width);
        vkCmdDraw(cmd, it.vertex_count, 1, it.first_vertex, 0);
    }
    if bound {
        vkCmdSetLineWidth(cmd, 1);
    }
}

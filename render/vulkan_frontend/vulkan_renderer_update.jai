
update_render_dimensions :: (width: u32, height: u32) {
    if render_target_width != width || render_target_height != height {
        render_target_width = width;
        render_target_height = height;
        should_recreate_swapchain = true;
    }
}

update_renderer :: (thread_local_renderer: *Renderer) -> bool {
    scope_set_renderer(thread_local_renderer);
    using context.renderer;
    auto_release_temp();

    in_the_middle_of_rendering = true;
    defer in_the_middle_of_rendering = false;

    current_frame := get_current_frame();

    defer array_reset_keeping_memory(*particle_draws);
    defer array_reset_keeping_memory(*static_mesh_draws);
    defer array_reset_keeping_memory(*skinned_mesh_draws);
    defer array_reset_keeping_memory(*line_draws);
    defer array_reset_keeping_memory(*in_front_line_draws);
    defer array_reset_keeping_memory(*transparent_in_front_line_draws);
    defer array_reset_keeping_memory(*skinning_joints);
    defer array_reset_keeping_memory(*prepared_opaque_static_mesh_draw_commands);
    defer array_reset_keeping_memory(*prepared_opaque_skinned_mesh_draw_commands);
    defer array_reset_keeping_memory(*prepared_line_draw_batches);
    defer array_reset_keeping_memory(*prepared_in_front_line_draw_batches);
    defer array_reset_keeping_memory(*prepared_transparent_in_front_line_draw_batches);
    defer array_reset_keeping_memory(*mesh_draw_specializations);

    for < *timed_in_front_line_draws {
        array_add(*in_front_line_draws, it.draw);
        it.time_remaining -= unscaled_delta_time;
        if it.time_remaining <= 0 {
            array_unordered_remove_by_index(*timed_in_front_line_draws, it_index);
        }
    }

    for < *timed_line_draws {
        array_add(*line_draws, it.draw);
        it.time_remaining -= unscaled_delta_time;
        if it.time_remaining <= 0 {
            array_unordered_remove_by_index(*timed_line_draws, it_index);
        }
    }

    defer for 0..GPU_HEAP_TYPE_COUNT-1 {
        gpu_linear_allocator_reset(*current_frame.temp_allocators[it]);
    }

    if !is_window_open(window) || is_window_minimized(window) then return false;

    frame_fences := VkFence.[current_frame.render_fence, current_frame.present_fence];
    if !render_check(.LOW, vkWaitForFences(logical.obj, frame_fences.count, frame_fences.data, VK_TRUE, NANOSECONDS_PER_SECOND), "timed out waiting for frame fences") then return false;

    if !render_check(.LOW, vkResetFences(logical.obj, frame_fences.count, frame_fences.data), "failed to reset frame fences") then return false;

    if should_recreate_swapchain && !render_check(.LOW, create_swapchain_and_attachments(), "failed to recreate the swapchain when it was expected") then return false;

    swapchain_image_index, acquire_success := acquire_next_swapchain_image(current_frame);
    render_target := swapchain.images[swapchain_image_index];
    render_target_view := swapchain.image_views[swapchain_image_index];

    if render_target_width == 0 || render_target_height == 0 then return false;

    viewport := Vector2.{xx render_target_width, xx render_target_height};

    cmd := begin_command_buffer(current_frame);
    // begin_command_buffer(transfer_command_buffer);

    // note: UNDEFINED treats the previous data in the image as garbage, which doesn't allow
    // reading from it at this stage. probably want to change this in the future.
    transition_image(cmd, render_target, .UNDEFINED, .COLOR_ATTACHMENT_OPTIMAL);
    transition_image(cmd, depth_buffer.obj, .UNDEFINED, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);

    // note : frames in flight blech. will get memory tearing without buffer copies.

    per_frame_uniform: Per_Frame_Uniform_Buffer;
    {
        // todo: do math to make it so z buffer overlap doesn't happen or is easy to avoid
        projection_matrix_game   := make_camera_projection_matrix(camera_info, viewport, 0.       , 0.5);
        projection_matrix_layer5 := make_camera_projection_matrix(camera_info, viewport, 0.5000001, 0.6);
        projection_matrix_layer4 := make_camera_projection_matrix(camera_info, viewport, 0.6000001, 0.7);
        projection_matrix_layer3 := make_camera_projection_matrix(camera_info, viewport, 0.7000001, 0.8);
        projection_matrix_layer2 := make_camera_projection_matrix(camera_info, viewport, 0.8000001, 0.9);
        projection_matrix_layer1 := make_camera_projection_matrix(camera_info, viewport, 0.9000001, 1.0);
        per_frame_uniform.view                    = make_camera_view_matrix(camera_position, camera_orientation);
        per_frame_uniform.view_projection_game    = projection_matrix_game * per_frame_uniform.view;
        per_frame_uniform.view_projection_layer_1 = projection_matrix_layer1 * per_frame_uniform.view;
        per_frame_uniform.view_projection_layer_2 = projection_matrix_layer2 * per_frame_uniform.view;
        per_frame_uniform.view_projection_layer_3 = projection_matrix_layer3 * per_frame_uniform.view;
        per_frame_uniform.view_projection_layer_4 = projection_matrix_layer4 * per_frame_uniform.view;
        per_frame_uniform.view_projection_layer_5 = projection_matrix_layer5 * per_frame_uniform.view;
        per_frame_uniform.camera_position         = camera_position;
        per_frame_uniform.camera_forward          = get_fore_direction(camera_orientation);
        per_frame_uniform.camera_up               = get_up_direction(camera_orientation);
        per_frame_uniform.camera_right            = get_right_direction(camera_orientation);
        per_frame_uniform.light_direction         = light_direction;
        per_frame_uniform.time                    = global_shader_time;
        per_frame_uniform.delta_time              = global_shader_delta_time;

        copy_to_gpu_buffer(*current_frame.per_frame_uniform_buffer, *per_frame_uniform, command_buffer=cmd);
    }

    prepare_draw_meshes(cmd, current_frame, static_mesh_draws);
    prepare_draw_meshes(cmd, current_frame, skinned_mesh_draws);
    prepare_draw_billboard_particles(cmd, current_frame);
    prepare_draw_lines(cmd, current_frame, true, false);
    prepare_draw_lines(cmd, current_frame, false, false);
    prepare_draw_lines(cmd, current_frame, true, true);

    add_buffer_transfer_barrier(cmd);

    // clear render target, among other things
    begin_rendering(cmd, render_target_view);

    vkCmdBindDescriptorSets(
        cmd, .GRAPHICS, billboard_pipeline_layout, 0, 1, *textures_descriptor_set, 0, null
    );
    vkCmdBindDescriptorSets(
        cmd, .GRAPHICS, billboard_pipeline_layout, 1, 1, *materials_storage_buffer_descriptor_set, 0, null
    );
    vkCmdBindDescriptorSets(
        cmd, .GRAPHICS, billboard_pipeline_layout, 2, 1, *current_frame.per_frame_uniform_descriptor_set, 0, null
    );

    draw_meshes(cmd, current_frame, static_mesh_draws);
    draw_meshes(cmd, current_frame, skinned_mesh_draws);
    draw_billboard_particles(cmd, current_frame);
    draw_lines(cmd, current_frame);
    draw_dev_gui(cmd);

    vkCmdEndRendering(cmd);

    // vkCmdDescriptorSets is for some reason designed s.t. you give it a pipeline layout it
    // must be compatible with.
    transition_image(cmd, render_target, .COLOR_ATTACHMENT_OPTIMAL, .PRESENT_SRC_KHR);

    if !render_check(.LOW, vkEndCommandBuffer(cmd), "failed to end the main command buffer") then return false;

    submit_command_info := command_buffer_submit_info(cmd);
    wait_info := semaphore_submit_info(
        VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 
        current_frame.image_available_semaphore
    );
    signal_info := semaphore_submit_info(
        VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT, 
        current_frame.image_rendered_semaphore
    );
    submit_info := roll_submit_info(*submit_command_info, *wait_info, *signal_info);

    if !render_check(.LOW, vkQueueSubmit2(graphics_queue, 1, *submit_info, current_frame.render_fence), "failed to submit draw commands to the graphics queue") then return false;

    present_fence_info := VkSwapchainPresentFenceInfoEXT.{
        swapchainCount = 1,
        pFences=*current_frame.present_fence,
    };

    present_info := VkPresentInfoKHR.{
        pSwapchains = *swapchain.obj,
        swapchainCount = 1,
        pWaitSemaphores = *current_frame.image_rendered_semaphore,
        waitSemaphoreCount = 1,
        pImageIndices = *swapchain_image_index,
        pNext = *present_fence_info
    };

    if !render_check(.LOW, vkQueuePresentKHR(graphics_queue, *present_info), "failed to present the render target") then return false;

    rendered_frame_count += 1;
    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

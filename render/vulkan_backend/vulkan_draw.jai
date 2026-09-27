prepare_draw_billboard_particles :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame) {
    using context.renderer;

    if particle_draws.count == 0 {
        return;
    }

    quick_sort(particle_draws, draw => -distance_squared(draw.position, context.renderer.camera_position));

    copy_to_gpu_buffer(*current_frame.billboard_instance_buffer, particle_draws, command_buffer=cmd);
}

draw_billboard_particles :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame) {
    using context.renderer;

    if particle_draws.count == 0 {
        return;
    }

    vkCmdBindDescriptorSets(cmd, .GRAPHICS, billboard_pipeline_layout, 3, 1, *current_frame.billboard_instance_buffer_descriptor_set, 0, null);
    vkCmdBindPipeline(cmd, .GRAPHICS, billboard_pipeline);
    bind_vertex_buffer(cmd, billboard_vertex_buffer);
    vkCmdDraw(cmd, xx billboard_vertices.count, xx particle_draws.count, 0, 0); 
}

prepare_draw_lines :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame, in_front: bool, transparent: bool) {
    using context.renderer;

    draws: []Line_Draw;
    if transparent {
        draws = transparent_in_front_line_draws;
    } else {
        draws = ifx in_front then in_front_line_draws else line_draws;
    }

    if draws.count == 0 {
        return;
    }

    quick_sort(draws, draw => draw.width);

    temp_draw_batch := make_dynamic_array(Static_Mesh_Vertex, draws.count*2,, temp);
    batch_width := draws[0].width;

    array_add(*temp_draw_batch, {position=draws[0].a, color=to_color4f(draws[0].color)});
    array_add(*temp_draw_batch, {position=draws[0].b, color=to_color4f(draws[0].color)});

    for 1..draws.count {
        if it == draws.count || draws[it].width != batch_width {
            draw_batch: *Line_Draw_Batch;
            if transparent {
                if in_front {
                    draw_batch = array_add(*prepared_transparent_in_front_line_draw_batches);
                } else {
                    render_check(.LOW, false, "don't support non-front transparent lines");
                }
            } else {
                if in_front {
                    draw_batch = array_add(*prepared_in_front_line_draw_batches);
                } else {
                    draw_batch = array_add(*prepared_line_draw_batches);
                }
            }

            draw_batch.width = batch_width;
            draw_batch.buffer = gpu_linear_allocate(.VERTEX_BUFFER, size_of(Static_Mesh_Vertex) * temp_draw_batch.count, .VERTEX_BUFFER_BIT, true);
            draw_batch.count = xx temp_draw_batch.count;

            copy_to_gpu_buffer(*draw_batch.buffer, temp_draw_batch, command_buffer=cmd);

            if it == draws.count {
                break;
            }

            batch_width = draws[it].width;
            array_reset_keeping_memory(*temp_draw_batch);
        }

        array_add(*temp_draw_batch, {position=draws[it].a, color=to_color4f(draws[it].color)});
        array_add(*temp_draw_batch, {position=draws[it].b, color=to_color4f(draws[it].color)});
    }
}

draw_lines :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame) {
    using context.renderer;

    vkCmdBindDescriptorSets(cmd, .GRAPHICS, opaque_mesh_pipeline_layout, 3, 1, *current_frame.skinned_mesh_instances_shader_data_descriptor_set, 0, null);
    vkCmdBindDescriptorSets(cmd, .GRAPHICS, opaque_mesh_pipeline_layout, 4, 1, *current_frame.skinned_mesh_sections_shader_data_descriptor_set, 0, null);

    if in_front_line_draws.count != 0 {
        vkCmdBindPipeline(cmd, .GRAPHICS, draw_in_front_opaque_line_pipeline);

        for prepared_in_front_line_draw_batches {
            vkCmdSetLineWidth(cmd, it.width);
            bind_vertex_buffer(cmd, it.buffer);
            vkCmdDraw(cmd, xx it.count, 1, 0, 0);
        }
    }

    if line_draws.count != 0 {
        vkCmdBindPipeline(cmd, .GRAPHICS, opaque_line_pipeline);

        for prepared_line_draw_batches {
            vkCmdSetLineWidth(cmd, it.width);
            bind_vertex_buffer(cmd, it.buffer);
            vkCmdDraw(cmd, xx it.count, 1, 0, 0);
        }
    }

    if transparent_in_front_line_draws.count != 0 {
        vkCmdBindPipeline(cmd, .GRAPHICS, draw_in_front_transparent_line_pipeline);

        for prepared_transparent_in_front_line_draw_batches {
            vkCmdSetLineWidth(cmd, it.width);
            bind_vertex_buffer(cmd, it.buffer);
            vkCmdDraw(cmd, xx it.count, 1, 0, 0);
        }
    }
}

prepare_draw_meshes :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame, draws: []$mesh_draw_type) {
    using context.renderer;

    DRAWING_SKINNED_MESHES :: mesh_draw_type == Skinned_Mesh_Draw;

    #if DRAWING_SKINNED_MESHES {
        prepared_draw_commands := *prepared_opaque_skinned_mesh_draw_commands;
        gpu_instances_shader_data := *current_frame.skinned_mesh_instances_shader_data;
        gpu_sections_shader_data := *current_frame.skinned_mesh_sections_shader_data;
        gpu_skinning_joints := *current_frame.skinning_joints_buffer;
        gpu_draw_commands := *current_frame.opaque_skinned_mesh_draw_commands;
        instance_type :: Skinned_Mesh_Instance_Shader_Data;
        vertex_type :: Skeletal_Mesh_Vertex;
    } else {
        prepared_draw_commands := *prepared_opaque_static_mesh_draw_commands;
        gpu_instances_shader_data := *current_frame.mesh_instances_shader_data;
        gpu_sections_shader_data := *current_frame.mesh_sections_shader_data;
        gpu_draw_commands := *current_frame.opaque_mesh_draw_commands;
        instance_type :: Mesh_Instance_Shader_Data;
        vertex_type :: Static_Mesh_Vertex;
    }

    if draws.count == 0 {
        return;
    }

    // todo: now that meshes are pre-sorted for instancing, draws should be stored per-mesh as well

    quick_sort(draws, draw => draw.ref.index);

    mesh_instances := make_static_array(instance_type, draws.count,, temp);
    mesh_sections  := make_dynamic_array(Mesh_Section_Shader_Data, draws.count*8,, temp);

    instances_begin_index := 0;
    instances_count       := 1;
    instances_ref         := draws[0].ref;
    next_ref              := Mesh_Ref.{};

    instance_count_total:  s32;

    flush_draws: bool;

    for 1..draws.count {
        prev_draw  := *draws[it-1];

        inst := *mesh_instances[it-1];

        if prev_draw.specialization != -1 {
            inst.specialization = mesh_draw_specializations[prev_draw.specialization];
        }

        inst.layer = prev_draw.layer;
        
        prev_transform   := *inst.transform;

        scale       := make_scale_matrix4(prev_draw.scale);
        rotation    := rotation_matrix(Matrix4, prev_draw.orientation);
        translation := make_translation_matrix4(prev_draw.position);

        prev_transform.* = translation * rotation * scale;

        #if DRAWING_SKINNED_MESHES {
            mesh_instances[it-1].joint_offset = xx prev_draw.joint_offset;
        }

        if it == draws.count {
            flush_draws = true;
        } else {
            cur_draw := *draws[it];
            if instances_ref != cur_draw.ref {
                flush_draws = true;
                next_ref = cur_draw.ref;
            }
        }

        if flush_draws {
            render_check(.LOW, instances_count > 0);
            
            mesh := get_mesh(instances_ref);

            for section : mesh.sections {
                array_add(*mesh_sections, Mesh_Section_Shader_Data.{
                    cast(s32) instance_count_total, 
                    cast(s32) instances_count, 
                    cast(s32) section.material.index
                });
                array_add(prepared_draw_commands, {
                    indexCount    = xx section.indices.count,
                    instanceCount = xx instances_count,
                    firstIndex    = xx (section.indices.gpu_allocation.source_heap_offset / size_of(u32)),
                    vertexOffset  = xx (section.vertices.gpu_allocation.source_heap_offset / size_of(vertex_type)),
                    firstInstance = 0
                });
            }

            instance_count_total += cast(s32) instances_count;

            instances_ref = next_ref;
            instances_begin_index = it;
            instances_count = 0;
            flush_draws = false;
        }

        instances_count += 1;
    }

    copy_to_gpu_buffer(gpu_instances_shader_data, mesh_instances, command_buffer=cmd);
    copy_to_gpu_buffer(gpu_sections_shader_data,  mesh_sections, command_buffer=cmd);
    copy_to_gpu_buffer(gpu_draw_commands, prepared_draw_commands.*, command_buffer=cmd);

    #if DRAWING_SKINNED_MESHES {
        copy_to_gpu_buffer(gpu_skinning_joints, skinning_joints, command_buffer=cmd);
    }
}

draw_meshes :: (cmd: VkCommandBuffer, current_frame: *Graphics_Frame, draws: []$mesh_draw_type) {
    using context.renderer;

    DRAWING_SKINNED_MESHES :: mesh_draw_type == Skinned_Mesh_Draw;

    #if DRAWING_SKINNED_MESHES {
        prepared_draw_commands := *prepared_opaque_skinned_mesh_draw_commands;
        gpu_instances_descriptor_set := *current_frame.skinned_mesh_instances_shader_data_descriptor_set;
        gpu_sections_descriptor_set := *current_frame.skinned_mesh_sections_shader_data_descriptor_set;
        gpu_skinning_joints_descriptor_set := *current_frame.skinning_joints_buffer_descriptor_set;
        gpu_draw_commands := *current_frame.opaque_skinned_mesh_draw_commands;
        pipeline := opaque_skinned_mesh_pipeline;
        vbo := get_skinned_vbo();
    } else {
        prepared_draw_commands := *prepared_opaque_static_mesh_draw_commands;
        gpu_instances_descriptor_set := *current_frame.mesh_instances_shader_data_descriptor_set;
        gpu_sections_descriptor_set := *current_frame.mesh_sections_shader_data_descriptor_set;
        gpu_draw_commands := *current_frame.opaque_mesh_draw_commands;
        pipeline := opaque_mesh_pipeline;
        vbo := get_vbo();
    }

    if vbo == null {
        return;
    }

    if draws.count == 0 {
        return;
    }

    vkCmdBindDescriptorSets(
        cmd, .GRAPHICS, opaque_mesh_pipeline_layout, 3, 1, gpu_instances_descriptor_set, 0, null
    );
    vkCmdBindDescriptorSets(
        cmd, .GRAPHICS, opaque_mesh_pipeline_layout, 4, 1, gpu_sections_descriptor_set, 0, null
    );

    #if DRAWING_SKINNED_MESHES {
        vkCmdBindDescriptorSets(cmd, .GRAPHICS, opaque_skinned_mesh_pipeline_layout, 5, 1, gpu_skinning_joints_descriptor_set, 0, null);
    }

    vkCmdBindIndexBuffer(cmd, get_ibo(), 0, .UINT32);
    vbo_offset: u64;
    vkCmdBindVertexBuffers(cmd, 0, 1, *vbo, *vbo_offset);
    vkCmdBindPipeline(cmd, .GRAPHICS, pipeline);

    draw_command_buffer := gpu_heap_pool[gpu_draw_commands.source_heap].buffer;

    vkCmdDrawIndexedIndirect(
        cmd,
        draw_command_buffer,
        xx gpu_draw_commands.source_heap_offset,
        cast(u32) prepared_draw_commands.count,
        size_of(VkDrawIndexedIndirectCommand)
    );
}

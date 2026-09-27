upload_mesh_to_gpu :: (renderer: *Renderer, mesh: *Mesh) {
    scope_set_renderer(renderer);
    using context.renderer;

    for *buf : mesh.texture_buffers {
        buf.index = -1;
    }

    texture_counter: int;

    found_static_mesh_section: bool;
    found_skinned_mesh_section: bool;

    // todo: playback params on mesh or something I don't know
    for *anim, ai : mesh.skeleton.animations {
    //     for ref.playback {
    //         if it.animation == ai {
    //             anim.speed = it.speed;
    //             break;
    //         }
    //     }
    //     if anim.speed == 0 {
            anim.speed = 1;
    //     }
    }

    // todo: free vertices & indices?
    for *section : mesh.sections {
        {
            using section.indices;
            if type == .U16 {
                auto_release_temp();
                render_check(.LOW, cpu_allocation._u16.count == count);
                // all indices are converted to u32 so the can all go in a single buffer.
                temp_u32_buffer := make_static_array(u32, count,, temp);
                for 0..cpu_allocation._u16.count-1 {
                    temp_u32_buffer[it] = cpu_allocation._u16[it];
                }
                create_gpu_index_buffer(*gpu_allocation, temp_u32_buffer);
            } else {
                render_check(.LOW, cpu_allocation._u32.count == count);
                create_gpu_index_buffer(*gpu_allocation, cpu_allocation._u32);
            }
        }
        {
            using section.vertices;
            if type == .STATIC {
                render_check(.LOW, cpu_allocation.static.count == count);
                // all sections must be either static or skinned, for simplicity. renderer requires it.
                render_check(.LOW, !found_skinned_mesh_section); 
                create_gpu_vertex_buffer(*gpu_allocation, cpu_allocation.static);
                found_static_mesh_section = true;
            } else {
                render_check(.LOW, cpu_allocation.skinned.count == count);
                // all sections must be either static or skinned, for simplicity. renderer requires it.
                render_check(.LOW, !found_static_mesh_section);

                // forcing normalization of skinning weights
                for *vertex : cpu_allocation.skinned {
                    vertex.color.a = 0.5;
                    sum := 0.0;
                    for *weight : vertex.weights {
                        weight.* = max(weight.*, 0);
                        sum += weight.*;
                    }
                    if sum > 0 {
                        inv_sum := 1.0 / sum;
                        for *weight : vertex.weights {
                            weight.* *= inv_sum;
                        }
                    }
                }

                create_gpu_skinned_vertex_buffer(*gpu_allocation, cpu_allocation.skinned);
                found_skinned_mesh_section = true;
            }
        }

        upload_texture(*section.material.albedo_texture, mesh, *texture_counter);
        upload_texture(*section.material.normal_texture, mesh, *texture_counter);
        upload_texture(*section.material.emissive_texture, mesh, *texture_counter);
        upload_texture(*section.material.orm_texture, mesh, *texture_counter);

        // todo: the material is stored twice. this is annoying. fix it!
        // also index type misalignment
        section.material.index = xx allocate_material(*section.material);
    }
}

#scope_file

upload_texture :: (using tex: *Texture, mesh: *Mesh, counter: *int) {
    if local_buffer != -1 {
        buffer := *mesh.texture_buffers[local_buffer];

        // todo: texture buffer sharing with filtering per-texture
        if buffer.index != -1 {
            global_buffer = buffer.index;
            return;
        }

        counter.* += 1;

        sampler := get_or_add_sampler(min_filter, mag_filter, horizontal_wrap, vertical_wrap);

        // assuming all textures are unique -> adding one buffer per texture
        // render_check(.LOW, buffer.gpu_allocation == -1);

        buffer.index = add_gpu_image_for_sampling(buffer.cpu_allocation.data, buffer.width, buffer.height, sampler).pool_index;
        global_buffer = buffer.index;

        stbi_image_free(buffer.cpu_allocation.data);
        buffer.cpu_allocation.data = null;
        buffer.cpu_allocation.count = 0;
    } else {
        global_buffer = -1;
    }
}

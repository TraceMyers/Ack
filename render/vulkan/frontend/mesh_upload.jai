// mirrored by Material in shaders/src/header.glsl
GPU_Material :: struct {
    albedo_factor:    Vector4;
    emissive_factor:  Vector4;
    metallic_factor:  float;
    roughness_factor: float;

    alpha_cutoff: float;

    albedo_uv:    s32;
    metallic_uv:  s32;
    roughness_uv: s32;
    normal_uv:    s32;
    occlusion_uv: s32;
    emissive_uv:  s32;

    // texture slots, -1 if none
    albedo_tex:   s32;
    normal_tex:   s32;
    emissive_tex: s32;
    orm_tex:      s32;
}

create_materials_buffer :: () -> bool {
    using engine.renderer;
    size := creation_settings.max_materials * size_of(GPU_Material);
    materials_buffer = create_gpu_buffer(general_allocator, .DEVICE_LOCAL_BUFFER, size, .STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT);
    return true;
}

update_material :: (index: s32, mat: *Material) {
    using engine.renderer;
    materials[index] = mat.*;
    gpu_mat := convert_material_to_gpu_format(mat);

    // uploads are batched by the caller when it's already uploading, e.g. while uploading a mesh
    own_upload := !uploads.recording;
    if own_upload then begin_upload();
    upload_buffer(materials_buffer, *gpu_mat, size_of(GPU_Material), index * size_of(GPU_Material));
    if own_upload then end_upload();
}

upload_mesh_to_gpu :: (renderer: *Renderer, mesh: *Mesh) {
    using engine.renderer;
    auto_release_temp();

    // todo: playback params on mesh or something I don't know
    for *anim : mesh.skeleton.animations {
        anim.speed = 1;
    }

    begin_upload();

    found_static_mesh_section:  bool;
    found_skinned_mesh_section: bool;

    for *section : mesh.sections {
        {
            using section.indices;
            // all indices are u32, so every index heap can be bound the same way
            indices_u32: []u32;
            if type == .U16 {
                render_check(cpu_allocation._u16.count == count);
                indices_u32 = make_static_array(u32, count,, temp);
                for cpu_allocation._u16 {
                    indices_u32[it_index] = it;
                }
            } else {
                render_check(cpu_allocation._u32.count == count);
                indices_u32 = cpu_allocation._u32;
            }
            gpu_allocation = create_gpu_buffer(general_allocator, .INDEX_BUFFER, indices_u32.count * size_of(u32), .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT);
            upload_buffer(gpu_allocation, indices_u32);
        }
        {
            using section.vertices;
            vertex_usage :: VkBufferUsageFlags.STORAGE_BUFFER_BIT | .TRANSFER_DST_BIT | .SHADER_DEVICE_ADDRESS_BIT;
            if type == .STATIC {
                render_check(cpu_allocation.static.count == count);
                // all sections must be either static or skinned, for simplicity. renderer requires it.
                render_check(!found_skinned_mesh_section);
                gpu_allocation = create_gpu_buffer(general_allocator, .VERTEX_BUFFER, count * size_of(Static_Mesh_Vertex), vertex_usage);
                upload_buffer(gpu_allocation, cpu_allocation.static);
                found_static_mesh_section = true;
            } else {
                render_check(cpu_allocation.skinned.count == count);
                // all sections must be either static or skinned, for simplicity. renderer requires it.
                render_check(!found_static_mesh_section);

                // forcing normalization of skinning weights
                for *vertex : cpu_allocation.skinned {
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

                gpu_allocation = create_gpu_buffer(general_allocator, .SKINNED_VERTEX_BUFFER, count * size_of(Skeletal_Mesh_Vertex), vertex_usage);
                upload_buffer(gpu_allocation, cpu_allocation.skinned);
                found_skinned_mesh_section = true;
            }
        }

        // color textures are stored in srgb. data textures (normals, occlusion/roughness/metallic) are linear.
        upload_texture(*section.material.albedo_texture,   mesh, srgb=true);
        upload_texture(*section.material.normal_texture,   mesh, srgb=false);
        upload_texture(*section.material.emissive_texture, mesh, srgb=true);
        upload_texture(*section.material.orm_texture,      mesh, srgb=false);

        // todo: the material is stored twice. this is annoying. fix it!
        section.material.index = xx allocate_material(*section.material);
    }

    end_upload();
}

// whether upload_mesh_to_gpu has run for this mesh
is_mesh_uploaded :: (mesh: *Mesh) -> bool {
    return mesh.sections.count > 0 && mesh.sections[0].indices.gpu_allocation.allocator.proc != null;
}

#scope_file

convert_material_to_gpu_format :: inline (mat: *Material) -> GPU_Material {
    gpu_mat: GPU_Material;

    gpu_mat.albedo_factor    = mat.albedo_factor;
    gpu_mat.emissive_factor  = mat.emissive_factor;
    gpu_mat.metallic_factor  = mat.metallic_factor;
    gpu_mat.roughness_factor = mat.roughness_factor;

    gpu_mat.alpha_cutoff = mat.discard_alpha_cutoff_if_masked_alpha;

    gpu_mat.albedo_uv    = mat.albedo_uv;
    gpu_mat.metallic_uv  = mat.metallic_uv;
    gpu_mat.roughness_uv = mat.roughness_uv;
    gpu_mat.normal_uv    = mat.normal_uv;
    gpu_mat.occlusion_uv = mat.occlusion_uv;
    gpu_mat.emissive_uv  = mat.emissive_uv;

    gpu_mat.albedo_tex   = mat.albedo_texture.global_buffer;
    gpu_mat.normal_tex   = mat.normal_texture.global_buffer;
    gpu_mat.emissive_tex = mat.emissive_texture.global_buffer;
    gpu_mat.orm_tex      = mat.orm_texture.global_buffer;

    return gpu_mat;
}

// uploads the texture's buffer if it isn't uploaded yet, and points the texture at its slot.
// texture buffers can be shared by several textures in a mesh.
upload_texture :: (using tex: *Texture, mesh: *Mesh, srgb: bool) {
    using engine.renderer;
    if local_buffer == -1 {
        global_buffer = -1;
        return;
    }

    buffer := *mesh.texture_buffers[local_buffer];
    if buffer.image == null {
        render_check(buffer.cpu_allocation.data != null, "texture buffer has no pixels to upload");

        // todo: texture buffer sharing with filtering per-texture. the first texture's sampler and
        // color space win.
        sampler := get_or_add_sampler(min_filter, mag_filter, horizontal_wrap, vertical_wrap);

        format := ifx srgb then VkFormat.R8G8B8A8_SRGB else .R8G8B8A8_UNORM;
        image := create_gpu_image(general_allocator, .DEVICE_LOCAL_IMAGE, buffer.width, buffer.height, .SAMPLED_BIT | .TRANSFER_DST_BIT, format);
        create_image_views(image, .{.COLOR_BIT, .SHADER_READ_ONLY_OPTIMAL});
        upload_image(image, buffer.cpu_allocation.data, buffer.cpu_allocation.count * size_of(Color4b));
        register_sampled_image(image, sampler);
        buffer.image = image;

        stbi_image_free(buffer.cpu_allocation.data);
        buffer.cpu_allocation.data  = null;
        buffer.cpu_allocation.count = 0;
    }

    global_buffer = buffer.image.texture_slot;
}

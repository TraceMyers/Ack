// turns the managed mesh instances into per-frame shader data. everything is written straight
// into the frame's host visible memory, which the gpu reads directly, so there are no copies.
//
// meshes already group their instances, so each mesh's visible instances in a layer become one
// contiguous range of Instance_Data, and each of the mesh's sections becomes one indirect draw
// whose firstInstance is the start of that range. draws are bucketed by layer, mesh type (which
// picks the pipeline) and index heap (which needs its own index buffer bind). normally there's
// one bucket per mesh type in the game layer.

// mirrored by Frame_Data in shaders/src/header.glsl
Frame_Data :: struct {
    view:            Matrix4;
    view_projection: Matrix4;
    camera_position: Vector3;
    camera_forward:  Vector3;
    camera_up:       Vector3;
    camera_right:    Vector3;
    light_direction: Vector3;

    time:        float;
    delta_time:  float;
    camera_near: float;
    camera_far:  float;
    depth_view_mode_max_distance: float;
}

// mirrored by Draw_Section in shaders/src/header.glsl. one per indirect draw.
Draw_Section :: struct {
    vertices: VkDeviceAddress;
    material: s32;
    _pad:     s32; // jai pads the struct to 16 bytes. the shader's scalar layout doesn't.
}

// mirrored by Instance_Data in shaders/src/header.glsl. entity_id sits right after the matrices
// so it's 8 byte aligned without padding, which keeps the jai and scalar glsl layouts identical.
Instance_Data :: struct {
    transform:                   Matrix4;
    inverse_transpose_transform: Matrix4;
    entity_id:                   u64; // user_types.entity_id_to_u64 of the instance's entity
    joint_offset:                s32 = -1;
    draw_fx:                     Draw_FX;
}
#assert size_of(Instance_Data) == 168;

Mesh_Draws :: struct {
    instances: GPU_Buffer; // Instance_Data, for every bucket
    joints:    GPU_Buffer; // Matrix4, for every skeletal bucket
    buckets:   [..]Draw_Bucket;
}

Draw_Bucket :: struct {
    layer:                Draw_Layer;
    type:                 Mesh_Type;
    index_buffer:         VkBuffer;
    sections:             GPU_Buffer; // Draw_Section
    commands:             GPU_Buffer; // VkDrawIndexedIndirectCommand
    draw_count:           u32;
    processed_draw_count: u32;
}

prepare_mesh_draws :: (frame: *GPU_Frame) -> Mesh_Draws {
    using engine.renderer;

    mesh_draws: Mesh_Draws;
    mesh_draws.buckets.allocator = temp;

    // first pass: count, so every array can be allocated at its exact size
    instance_count, joint_count: int;
    view_frustum := make_view_frustum(camera_info, camera_position, camera_orientation, get_window_viewport());

    for *instanced, mesh_index : meshes.instanced_meshes {
        if !is_mesh_uploaded(*instanced.mesh) {
            continue;
        }

        layer_counts := count_instances_per_layer(instanced, *view_frustum);

        for count, layer_index : layer_counts {
            if count == 0 {
                continue;
            }

            instance_count += count;

            if instanced.instances.type == .SKELETAL {
                joint_count += count * instanced.mesh.skeleton.joints.count;
            }

            for *section : instanced.mesh.sections {
                bucket := get_draw_bucket(*mesh_draws, xx layer_index, instanced.instances.type, section);
                bucket.draw_count += 1;
            }
        }
    }

    if instance_count == 0 {
        return mesh_draws;
    }

    allocate_mesh_draws(frame, *mesh_draws, instance_count, joint_count);

    // second pass: fill
    instance_data := cast(*Instance_Data) gpu_mapped(mesh_draws.instances);
    joint_data    := ifx joint_count > 0 then cast(*Matrix4) gpu_mapped(mesh_draws.joints) else null;
    instance_cursor, joint_cursor: s32;

    for *instanced, mesh_index : meshes.instanced_meshes {
        if !is_mesh_uploaded(*instanced.mesh) {
            continue;
        }

        for layer_index : 0..DRAW_LAYER_COUNT-1 {
            layer : Draw_Layer = xx layer_index;
            first_instance := instance_cursor;

            if instanced.instances.type == .STATIC {
                for instanced.instances.static {
                    inst := it.component;

                    if !should_draw_instance_on_layer(inst, layer) then continue;

                    instance_data[instance_cursor] = make_instance_data(inst, it.entity_id);
                    instance_cursor += 1;
                }
            } else {
                joints_per_instance := instanced.mesh.skeleton.joints.count;
                for instanced.instances.skeletal {
                    inst := it.component;

                    if !should_draw_instance_on_layer(inst, layer) then continue;

                    data := make_instance_data(inst, it.entity_id);
                    skinning_joints := inst.pose.skinning_joints;

                    render_check(skinning_joints.count == joints_per_instance, "skeletal mesh instance pose has % joints, its mesh has %", skinning_joints.count, joints_per_instance, level=.HIGH);

                    memcpy(joint_data + joint_cursor, skinning_joints.data, skinning_joints.count * size_of(Matrix4));
                    data.joint_offset = joint_cursor;
                    joint_cursor += xx skinning_joints.count;

                    instance_data[instance_cursor] = data;
                    instance_cursor += 1;
                }
            }

            visible_count := instance_cursor - first_instance;
            if visible_count == 0 {
                continue;
            }

            for *section : instanced.mesh.sections {
                bucket   := get_draw_bucket(*mesh_draws, layer, instanced.instances.type, section);
                sections := cast(*Draw_Section)                 gpu_mapped(bucket.sections);
                commands := cast(*VkDrawIndexedIndirectCommand) gpu_mapped(bucket.commands);

                _, index_heap_offset := gpu_vk_buffer(section.indices.gpu_allocation);
                sections[bucket.processed_draw_count] = .{
                    vertices = gpu_address(section.vertices.gpu_allocation),
                    material = section.material.index
                };
                commands[bucket.processed_draw_count] = .{
                    indexCount    = xx section.indices.count,
                    instanceCount = xx visible_count,
                    firstIndex    = xx (index_heap_offset / size_of(u32)),
                    vertexOffset  = 0, // vertices are pulled from the section's own address
                    firstInstance = xx first_instance
                };
                bucket.processed_draw_count += 1;
            }
        }
    }

    return mesh_draws;
}

#scope_file

count_instances_per_layer :: (instanced: *Instanced_Mesh, view_frustum: *View_Frustum) -> [DRAW_LAYER_COUNT]int {
    counts: [DRAW_LAYER_COUNT]int;
    if instanced.instances.type == .STATIC {
        for instanced.instances.static {
            it.component.should_draw_this_frame = should_draw_instance(it.component, it.entity_id, view_frustum, instanced.cull_radius);
            if it.component.should_draw_this_frame {
                counts[it.component.layer] += 1;
            }
        }
    } else for instanced.instances.skeletal {
        it.component.should_draw_this_frame = should_draw_instance(it.component, it.entity_id, view_frustum, instanced.cull_radius);
        if it.component.should_draw_this_frame {
            counts[it.component.layer] += 1;
        }
    }
    return counts;
}

make_instance_data :: (inst: *Mesh_Instance, entity_id: user_types.entity_id_type) -> Instance_Data {
    using engine.renderer;
    // todo: attaching to another mesh's skeletal joint
    render_check(inst.attachment.skeletal_mesh_joint == NO_JOINT, "mesh instances attached to joints aren't supported yet");

    entity := user_types.id_to_entity_proc(entity_id);
    render_check(entity != null, "mesh instance % has no entity", inst.*);
    entity_transform := make_transform_matrix(entity.position, entity.orientation, entity.scale);

    attachment := inst.attachment;
    attachment_transform := make_transform_matrix(attachment.translation, attachment.rotation, attachment.scale);

    data: Instance_Data;
    data.transform = entity_transform * attachment_transform;
    success, inverse := inverse(data.transform);
    if success {
        data.inverse_transpose_transform = transpose(inverse);
    } else {
        data.inverse_transpose_transform = data.transform;
    }

    data.draw_fx = ifx inst.draw_fx == -1 then Draw_FX.{} else meshes.draw_fxs[inst.draw_fx];
    data.entity_id = user_types.entity_id_to_u64(entity_id);

    return data;
}

// the bucket for this layer, mesh type, and the index heap this section's indices are in. the
// counting pass adds buckets and counts their draw_count. the filling pass finds them again and
// uses processed_draw_count as its write cursor.
get_draw_bucket :: (mesh_draws: *Mesh_Draws, layer: Draw_Layer, type: Mesh_Type, section: *Mesh_Section) -> *Draw_Bucket {
    index_buffer, _ := gpu_vk_buffer(section.indices.gpu_allocation);
    for *mesh_draws.buckets {
        if it.layer == layer && it.type == type && it.index_buffer == index_buffer {
            return it;
        }
    }
    bucket := array_add(*mesh_draws.buckets);
    bucket.layer        = layer;
    bucket.type         = type;
    bucket.index_buffer = index_buffer;
    return bucket;
}

allocate_mesh_draws :: (frame: *GPU_Frame, mesh_draws: *Mesh_Draws, instance_count: int, joint_count: int) {
    using engine.renderer;
    mesh_draws.instances = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, instance_count * size_of(Instance_Data), .STORAGE_BUFFER_BIT);

    if joint_count > 0 {
        mesh_draws.joints = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, joint_count * size_of(Matrix4), .STORAGE_BUFFER_BIT);
    }

    for *bucket : mesh_draws.buckets {
        bucket.sections = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, bucket.draw_count * size_of(Draw_Section), .STORAGE_BUFFER_BIT);
        bucket.commands = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, bucket.draw_count * size_of(VkDrawIndexedIndirectCommand), .INDIRECT_BUFFER_BIT);
    }
}

should_draw_instance_on_layer :: inline (inst: *$T, layer: Draw_Layer) -> bool {
    return inst.layer == layer && inst.should_draw_this_frame;
}

should_draw_instance :: inline (inst: *$T, entity_id: user_types.entity_id_type, view_frustum: *View_Frustum, mesh_cull_radius: float) -> bool {
    if !inst.visible {
        return false;
    }
    if inst.frustum_cull {
        entity := user_types.id_to_entity_proc(entity_id);

        position  := inst.attachment.translation + entity.position;
        scale     := inst.attachment.scale * entity.scale;
        scalar    := max(scale);

        inst_cull_radius := scalar * mesh_cull_radius;

        if !does_frustum_intersect_sphere(view_frustum, position, inst_cull_radius) {
            return false;
        }
    }
    return true;
}


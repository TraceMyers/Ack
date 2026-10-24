// turns the managed mesh instances and immediate mesh draws into per-frame shader data. everything
// is written straight into the frame's host visible memory, which the gpu reads directly, so
// there are no copies.
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

// mirrored by Instance_Data in shaders/src/header.glsl
Instance_Data :: struct {
    transform:      Matrix4;
    joint_offset:   s32 = -1;
    entity_id:      s32;
    specialization: Mesh_Specialization;
}

Mesh_Draws :: struct {
    instances: GPU_Buffer; // Instance_Data, for every bucket
    joints:    GPU_Buffer; // Matrix4, for every skeletal bucket
    buckets:   [..]Draw_Bucket;
}

Draw_Bucket :: struct {
    layer:        Draw_Layer;
    type:         Mesh_Type;
    index_buffer: VkBuffer;
    sections:     GPU_Buffer; // Draw_Section
    commands:     GPU_Buffer; // VkDrawIndexedIndirectCommand
    count:        u32;
}

prepare_mesh_draws :: (frame: *GPU_Frame) -> Mesh_Draws {
    using engine.renderer;

    mesh_draws: Mesh_Draws;
    mesh_draws.buckets.allocator = temp;

    managed := get_managed_mesh_data();
    if managed == null {
        return mesh_draws;
    }

    immediate := group_immediate_draws_by_mesh(managed);

    // first pass: count, so every array can be allocated at its exact size
    instance_count, joint_count: int;

    for *instanced, mesh_index : managed.instanced_meshes {
        if !is_mesh_uploaded(*instanced.mesh) {
            continue;
        }

        layer_counts := count_instances_per_layer(instanced, immediate.ranges[mesh_index], immediate.draws);
        for count, layer_index : layer_counts {
            if count == 0 continue;
            instance_count += count;
            if instanced.instances.type == .SKELETAL {
                joint_count += count * instanced.mesh.skeleton.joints.count;
            }
            for *section : instanced.mesh.sections {
                bucket_for(*mesh_draws, xx layer_index, instanced.instances.type, section).count += 1;
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

    for *instanced, mesh_index : managed.instanced_meshes {
        if !is_mesh_uploaded(*instanced.mesh) {
            continue;
        }

        immediate_range := immediate.ranges[mesh_index];

        for layer_index : 0..DRAW_LAYER_COUNT-1 {
            layer : Draw_Layer = xx layer_index;
            first_instance := instance_cursor;

            if instanced.instances.type == .STATIC {
                for instanced.instances.static {
                    inst := it.component;
                    if !inst.visible || inst.layer != layer continue;
                    instance_data[instance_cursor] = make_instance_data(inst, it.entity_id);
                    instance_cursor += 1;
                }
            } else {
                joints_per_instance := instanced.mesh.skeleton.joints.count;
                for instanced.instances.skeletal {
                    inst := it.component;
                    if !inst.visible || inst.layer != layer continue;
                    data := make_instance_data(inst, it.entity_id);

                    skinning_joints := inst.pose.skinning_joints;
                    render_check(skinning_joints.count == joints_per_instance, "skeletal mesh instance pose has % joints, its mesh has %", skinning_joints.count, joints_per_instance);
                    memcpy(joint_data + joint_cursor, skinning_joints.data, skinning_joints.count * size_of(Matrix4));
                    data.joint_offset = joint_cursor;
                    joint_cursor += xx skinning_joints.count;

                    instance_data[instance_cursor] = data;
                    instance_cursor += 1;
                }
            }

            for immediate_index : immediate_range.begin..immediate_range.end-1 {
                draw := *immediate.draws[immediate_index];
                if draw.layer != layer continue;
                instance_data[instance_cursor] = .{transform = draw.transform, specialization = draw.specialization};
                instance_cursor += 1;
            }

            visible_count := instance_cursor - first_instance;
            if visible_count == 0 {
                continue;
            }

            for *section : instanced.mesh.sections {
                bucket   := bucket_for(*mesh_draws, layer, instanced.instances.type, section);
                sections := cast(*Draw_Section)                 gpu_mapped(bucket.sections);
                commands := cast(*VkDrawIndexedIndirectCommand) gpu_mapped(bucket.commands);

                _, index_heap_offset := gpu_vk_buffer(section.indices.gpu_allocation);
                sections[bucket.count] = .{
                    vertices = gpu_address(section.vertices.gpu_allocation),
                    material = section.material.index
                };
                commands[bucket.count] = .{
                    indexCount    = xx section.indices.count,
                    instanceCount = xx visible_count,
                    firstIndex    = xx (index_heap_offset / size_of(u32)),
                    vertexOffset  = 0, // vertices are pulled from the section's own address
                    firstInstance = xx first_instance
                };
                bucket.count += 1;
            }
        }
    }

    return mesh_draws;
}

#scope_file

Immediate_Range :: struct {
    begin: int;
    end:   int;
}

Grouped_Immediate_Draws :: struct {
    draws:  []Immediate_Mesh_Draw;
    // indexed by mesh pool index
    ranges: []Immediate_Range;
}

group_immediate_draws_by_mesh :: (managed: *Managed_Meshes) -> Grouped_Immediate_Draws {
    using engine.renderer;
    grouped: Grouped_Immediate_Draws;
    grouped.ranges = make_static_array(Immediate_Range, managed.instanced_meshes.items.count,, temp);
    if draws.meshes.count == 0 {
        return grouped;
    }

    grouped.draws = array_copy(draws.meshes,, temp);
    quick_sort(grouped.draws, draw => draw.ref.index);

    for grouped.draws {
        range := *grouped.ranges[it.ref.index];
        if range.begin == range.end {
            range.begin = it_index;
        }
        range.end = it_index + 1;
    }
    return grouped;
}

count_instances_per_layer :: (instanced: *Instanced_Mesh, immediate_range: Immediate_Range, immediate_draws: []Immediate_Mesh_Draw) -> [DRAW_LAYER_COUNT]int {
    counts: [DRAW_LAYER_COUNT]int;
    if instanced.instances.type == .STATIC {
        for instanced.instances.static {
            if it.component.visible then counts[it.component.layer] += 1;
        }
    } else {
        for instanced.instances.skeletal {
            if it.component.visible then counts[it.component.layer] += 1;
        }
    }
    for immediate_range.begin..immediate_range.end-1 {
        counts[immediate_draws[it].layer] += 1;
    }
    return counts;
}

// entity_transform_proc is optional in user_types, so games written before it existed still compile
USER_TYPES_HAS_ENTITY_TRANSFORM :: #run -> bool {
    for (cast(*Type_Info_Struct) type_info(user_types)).members {
        if it.name == "entity_transform_proc" return true;
    }
    return false;
};

make_instance_data :: (inst: *Mesh_Instance, entity_id: user_types.entity_id_type) -> Instance_Data {
    using engine.renderer;
    // todo: attaching to another mesh's skeletal joint
    render_check(inst.attachment.skeletal_mesh_joint == NO_JOINT, "mesh instances attached to joints aren't supported yet");

    attachment := inst.attachment;
    attachment_transform := make_transform_matrix(attachment.translation, attachment.rotation, attachment.scale);

    data: Instance_Data;
    #if USER_TYPES_HAS_ENTITY_TRANSFORM {
        data.transform = user_types.entity_transform_proc(entity_id) * attachment_transform;
    } else {
        // without entity transforms, instances are placed by their attachment alone
        data.transform = attachment_transform;
    }
    data.specialization = get_specialization(inst);
    #if type_info(user_types.entity_id_type).type == .INTEGER {
        data.entity_id = xx entity_id;
    }
    return data;
}

// the bucket for this layer, mesh type, and the index heap this section's indices are in. the
// counting pass adds buckets and counts their draws. the filling pass finds them again with
// count reset to 0.
bucket_for :: (mesh_draws: *Mesh_Draws, layer: Draw_Layer, type: Mesh_Type, section: *Mesh_Section) -> *Draw_Bucket {
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
    for *mesh_draws.buckets {
        it.sections = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, it.count * size_of(Draw_Section), .STORAGE_BUFFER_BIT);
        it.commands = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, it.count * size_of(VkDrawIndexedIndirectCommand), .INDIRECT_BUFFER_BIT);
        it.count = 0;
    }
}

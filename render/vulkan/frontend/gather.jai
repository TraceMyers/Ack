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
    entity_id:                   u64; // Entity_ID.index of the instance's entity (generation dropped, must fit in 32 bits)
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

    // instances live in one component storage per type, so they're grouped by (mesh, layer) here
    // with a counting sort. each group's visible instances become one contiguous range of
    // Instance_Data, which is what each section's indirect draw points at.
    range_count := (meshes.instanced_meshes.top + 1) * DRAW_LAYER_COUNT;
    if range_count <= 0 {
        return mesh_draws;
    }
    counts := NewArray(range_count, s32,, temp); // visible instances per range
    starts := NewArray(range_count, s32,, temp); // first instance per range, then the fill cursor

    // first pass: cull and count, so every array can be allocated at its exact size
    instance_count, joint_count: int;
    view_frustum := make_view_frustum(camera_info, camera_position, camera_orientation, get_window_viewport());

    count_visible_instances(Static_Mesh_Instance,   counts, *view_frustum, *instance_count, *joint_count);
    count_visible_instances(Skeletal_Mesh_Instance, counts, *view_frustum, *instance_count, *joint_count);

    if instance_count == 0 {
        return mesh_draws;
    }

    for *instanced, mesh_index : meshes.instanced_meshes {
        for layer_index : 0..DRAW_LAYER_COUNT-1 {
            if counts[range_index(mesh_index, layer_index)] == 0 {
                continue;
            }
            for *section : instanced.mesh.sections {
                bucket := get_draw_bucket(*mesh_draws, xx layer_index, instanced.type, section);
                bucket.draw_count += 1;
            }
        }
    }

    allocate_mesh_draws(frame, *mesh_draws, instance_count, joint_count);

    // second pass: prefix sum. every range's first instance and count are known now, so the
    // draw commands can be written before any instance data.
    running_first_instance: s32;

    for *instanced, mesh_index : meshes.instanced_meshes {
        for layer_index : 0..DRAW_LAYER_COUNT-1 {
            ri := range_index(mesh_index, layer_index);
            first_instance := running_first_instance;
            visible_count  := counts[ri];
            starts[ri] = first_instance;
            running_first_instance += visible_count;

            if visible_count == 0 {
                continue;
            }

            for *section : instanced.mesh.sections {
                bucket   := get_draw_bucket(*mesh_draws, xx layer_index, instanced.type, section);
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

    // third pass: fill. instance writes are in order within a range but jump between ranges.
    // joints don't need grouping (joint_offset is per instance), so they're written sequentially.
    instance_data := cast(*Instance_Data) gpu_mapped(mesh_draws.instances);
    joint_data    := ifx joint_count > 0 then cast(*Matrix4) gpu_mapped(mesh_draws.joints) else null;
    joint_cursor: s32;

    for component_loop(Static_Mesh_Instance) {
        inst := it.data;
        if !inst.should_draw_this_frame then continue;

        ri := range_index(inst.ref.index, xx inst.layer);
        instance_data[starts[ri]] = make_instance_data(inst, it.entity);
        starts[ri] += 1;
    }

    for component_loop(Skeletal_Mesh_Instance) {
        inst := it.data;
        if !inst.should_draw_this_frame then continue;

        data := make_instance_data(inst, it.entity);
        skinning_joints := inst.pose.skinning_joints;

        joints_per_instance := get_instanced_mesh(inst.ref).mesh.skeleton.joints.count;
        render_check(skinning_joints.count == joints_per_instance, "skeletal mesh instance pose has % joints, its mesh has %", skinning_joints.count, joints_per_instance, level=.HIGH);

        memcpy(joint_data + joint_cursor, skinning_joints.data, skinning_joints.count * size_of(Matrix4));
        data.joint_offset = joint_cursor;
        joint_cursor += xx skinning_joints.count;

        ri := range_index(inst.ref.index, xx inst.layer);
        instance_data[starts[ri]] = data;
        starts[ri] += 1;
    }

    return mesh_draws;
}

#scope_file

range_index :: inline (mesh_index: int, layer_index: int) -> int {
    return mesh_index * DRAW_LAYER_COUNT + layer_index;
}

count_visible_instances :: ($T: Type, counts: []s32, view_frustum: *View_Frustum, instance_count: *int, joint_count: *int) {
    for component_loop(T) {
        inst := it.data;
        instanced := get_instanced_mesh(inst.ref);

        inst.should_draw_this_frame = is_mesh_uploaded(*instanced.mesh) && should_draw_instance(inst, it.entity, view_frustum, instanced.cull_radius);
        if !inst.should_draw_this_frame then continue;

        counts[range_index(inst.ref.index, xx inst.layer)] += 1;
        instance_count.* += 1;

        #if T == Skeletal_Mesh_Instance {
            joint_count.* += instanced.mesh.skeleton.joints.count;
        }
    }
}

make_instance_data :: (inst: *Mesh_Instance, entity: *Entity) -> Instance_Data {
    using engine.renderer;
    // todo: attaching to another mesh's skeletal joint
    render_check(inst.attachment.skeletal_mesh_joint == NO_JOINT, "mesh instances attached to joints aren't supported yet");

    render_check(entity != null, "mesh instance % has no entity", inst.*);
    t := get_component(entity, Transform);
    render_check(t != null, "mesh instance %'s entity has no Transform", inst.*);
    entity_transform := make_transform_matrix(t.position, t.orientation, t.scale);

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
    // index only: entity_click_selection.glsl packs (depth << 32) | entity_id, so it must fit in 32 bits
    data.entity_id = cast(u64) cast(u32) entity.id.index;

    return data;
}

// the bucket for this layer, mesh type, and the index heap this section's indices are in. the
// counting pass adds buckets and counts their draw_count. the prefix pass finds them again and
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

should_draw_instance :: inline (inst: *$T, entity: *Entity, view_frustum: *View_Frustum, mesh_cull_radius: float) -> bool {
    if !inst.visible {
        return false;
    }
    if inst.frustum_cull {
        render_check(entity != null, "mesh instance has no entity");
        t := get_component(entity, Transform);
        render_check(t != null, "mesh instance's entity has no Transform");

        position  := inst.attachment.translation + t.position;
        scale     := inst.attachment.scale * t.scale;
        scalar    := max(scale);

        inst_cull_radius := scalar * mesh_cull_radius;

        if !does_frustum_intersect_sphere(view_frustum, position, inst_cull_radius) {
            return false;
        }
    }
    return true;
}


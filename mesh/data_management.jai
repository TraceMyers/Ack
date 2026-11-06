Mesh_Ref :: #type,isa Gen_Ref;

Mesh_Type :: enum u8 { STATIC; SKELETAL; }

Instanced_Mesh :: struct {
    mesh: Mesh;
    centroid_offset: Vector3;
    cull_radius: float;
    // instances live in the Static_Mesh_Instance / Skeletal_Mesh_Instance component storages.
    // they're grouped by mesh at gather time (see prepare_mesh_draws).
    type: Mesh_Type;
}

// lives on the renderer (engine.renderer.meshes)
Managed_Meshes :: struct {
    path_lookup_table: Table(string, Mesh_Ref);
    instanced_meshes: Pool(Instanced_Mesh) = .{track_generation = true};
    animation_instances: Pool(Skeletal_Mesh_Animation_Instance);
    draw_fxs: Pool(Draw_FX);
}

Skeletal_Animation_Playback_Control :: struct {
    animation: s32;
    speed: float;
}

// one mesh instance per entity. for a skeletal mesh, the skeletal fields are reached with
// get_component(entity, Skeletal_Mesh_Instance).
add_mesh :: (entity: *Entity, mesh_ref: Mesh_Ref) -> *Mesh_Instance {
    instanced := get_instanced_mesh(mesh_ref);

    inst: *Mesh_Instance;
    if instanced.type == .STATIC {
        engine_check(is_static_mesh(*instanced.mesh));
        inst = add_component(entity, Static_Mesh_Instance);
    } else { // .SKELETAL
        engine_check(is_skeletal_mesh(*instanced.mesh));
        inst = add_component(entity, Skeletal_Mesh_Instance);
    }

    inst.ref = mesh_ref;
    return inst;
}

get_mesh_instance :: (entity: *Entity) -> *Mesh_Instance {
    inst := get_component(entity, Static_Mesh_Instance);
    if inst == null {
        inst = get_component(entity, Skeletal_Mesh_Instance);
    }
    return inst;
}

remove_mesh :: (entity: *Entity) {
    inst := get_mesh_instance(entity);
    engine_check(inst != null, "entity has no mesh instance");

    if inst.draw_fx != -1 {
        pool_return(*engine.renderer.meshes.draw_fxs, inst.draw_fx);
        inst.draw_fx = -1;
    }

    if get_instanced_mesh(inst.ref).type == .STATIC {
        remove_component(entity, Static_Mesh_Instance);
    } else { // .SKELETAL
        remove_component(entity, Skeletal_Mesh_Instance);
    }
}

get_mesh :: inline (inst: *Mesh_Instance) -> mesh: *Mesh {
    return get_mesh(inst.ref);
}

get_mesh :: inline (ref: Mesh_Ref) -> mesh: *Mesh {
    return *get_instanced_mesh(ref).mesh;
}

get_instanced_mesh :: (ref: Mesh_Ref) -> mesh: *Instanced_Mesh {
    meshes := *engine.renderer.meshes;
    instanced := *meshes.instanced_meshes[ref.index];
    engine_check(ref.generation == pool_get_item_generation(*meshes.instanced_meshes, ref.index));
    return instanced;
}

// load .trm mesh from file
load_mesh :: (path: string, renderer: *Renderer, set_mesh_path_on_load := true) -> Mesh_Ref {
    engine_check(path.count > 0);

    meshes := *renderer.meshes;
    ref, newly_added := find_or_add(*meshes.path_lookup_table, path);
    engine_check((ref.generation == 0) == newly_added);

    if !newly_added {
        return ref;
    }

    // doesn't seem like the option to temp allocate on-struct data is valuable
    engine_check(context.allocator.proc != temp.proc);
    auto_release_temp();

    inst_index := pool_borrow(*meshes.instanced_meshes);
    instanced := *meshes.instanced_meshes[inst_index];

    ref.index      = xx inst_index;
    ref.generation = xx pool_get_item_generation(*meshes.instanced_meshes, inst_index);

    mesh := *instanced.mesh;
    mesh.* = {allocator = context.allocator};

    file := read_entire_file(path,, temp);
    pos: int;
    header := read_string(file, *pos, 16);
    engine_check(header == TeRM_Mesh_Header);

    version := read_s32(file, *pos);
    engine_check(version == 1);
 
    array_reset(*context.ack_mesh_buffer_table);
    array_reserve(*context.ack_mesh_buffer_table, 256,, temp);
    array_reset(*context.ack_mesh_texture_buffer_table);
    array_reserve(*context.ack_mesh_texture_buffer_table, 128,, temp);
    array_reset(*context.ack_mesh_self_allocation);
    array_reserve(*context.ack_mesh_self_allocation, 16 * 1024 * 1024,, temp);

    mesh_sections_header := read_block_header(file, *pos);
    animations_header    := read_block_header(file, *pos);
    joints_header        := read_block_header(file, *pos);

    if mesh_sections_header.item_count > 0 {
        mesh.sections = allocate_self_array(Mesh_Section, mesh_sections_header.item_count);
        pos = mesh_sections_header.offset_to_block;

        for *section : mesh.sections {
            section_name_pos := read_s32(file, *pos);
            section_name, section_name_type := alloc_or_look_up_buffer(file, section_name_pos, true);
            engine_check(section_name_type == .BYTE, "incorrect section type: %", section_name_type);
            section.name = string.{section_name.count, section_name.data};

            ibuf_pos := read_s32(file, *pos);
            index_buffer, index_buffer_type := alloc_or_look_up_buffer(file, ibuf_pos);

            section.indices.count = xx index_buffer.count;
            // union'd with u32 index array
            section.indices._u16.data  = xx index_buffer.data;
            section.indices._u16.count = index_buffer.count;

            if index_buffer_type == {
            case .U16;
                section.indices.type = .U16;
            case .U32;
                section.indices.type = .U32;
            case;
                engine_check(false, "invalid index buffer type %", index_buffer_type);
            }
            
            vbuf_pos := read_s32(file, *pos);
            vertex_buffer, vertex_buffer_type := alloc_or_look_up_buffer(file, vbuf_pos);

            section.vertices.count = xx vertex_buffer.count;
            // union'd with skinned vertex array
            section.vertices.static.data  = xx vertex_buffer.data;
            section.vertices.static.count = vertex_buffer.count;

            if vertex_buffer_type == {
            case .STATIC_VERTEX;
                section.vertices.type = .STATIC;
                expand_cull_radius(*instanced.cull_radius, section.vertices.static);
            case .SKELETAL_VERTEX;
                section.vertices.type = .SKELETAL;
                expand_cull_radius(*instanced.cull_radius, section.vertices.skinned);
            case;
                engine_check(false, "invalid vertex buffer type %", vertex_buffer_type);
            }

            matbuf_name_pos := read_s32(file, *pos);
            matbuf_name, matbuf_name_type := alloc_or_look_up_buffer(file, matbuf_name_pos, true);
            engine_check(matbuf_name_type == .BYTE);

            using section.material;
            name = string.{matbuf_name.count, matbuf_name.data};
            alpha_mode    = cast(Material_Alpha_Mode) read_s32(file, *pos);
            albedo_uv     = cast(s8) read_s32(file, *pos);
            metallic_uv   = cast(s8) read_s32(file, *pos);
            roughness_uv  = cast(s8) read_s32(file, *pos);
            normal_uv     = cast(s8) read_s32(file, *pos);
            occlusion_uv  = cast(s8) read_s32(file, *pos);
            emissive_uv   = cast(s8) read_s32(file, *pos);

            discard_alpha_cutoff_if_masked_alpha = read_float(file, *pos);

            albedo_factor    = read_color4f(file, *pos);
            metallic_factor  = read_float(file, *pos);
            roughness_factor = read_float(file, *pos);
            emissive_factor  = read_color4f(file, *pos);

            read_texture(*albedo_texture, file, *pos);
            read_texture(*normal_texture, file, *pos);
            read_texture(*emissive_texture, file, *pos);
            read_texture(*orm_texture, file, *pos);
        }
    }

    if joints_header.item_count > 0 {
        mesh.skeleton.joints = allocate_self_array(Joint, joints_header.item_count);
        pos = joints_header.offset_to_block;

        mesh.skeleton.joint_name_hashes = allocate_self_array(u32, mesh.skeleton.joints.count);
        for *joint, ji : mesh.skeleton.joints {
            read_joint(joint, file, *pos);
            mesh.skeleton.joint_name_hashes[ji] = get_hash(joint.name);
        }
    }

    if animations_header.item_count > 0 {
        mesh.skeleton.animations = allocate_self_array(Skeletal_Animation, animations_header.item_count);
        pos = animations_header.offset_to_block;

        for *animation : mesh.skeleton.animations {
            name_pos := read_s32(file, *pos);
            anim_name, anim_name_type := alloc_or_look_up_buffer(file, name_pos, true);
            engine_check(anim_name_type == .BYTE);

            animation.name = string.{anim_name.count, anim_name.data};
            animation.interpolate = cast(bool) read_s32(file, *pos);
            
            timestamps_pos := read_s32(file, *pos);
            timestamps, timestamps_type := alloc_or_look_up_buffer(file, timestamps_pos, true);
            engine_check(timestamps_type == .FLOAT);
            animation.timestamps = cast,force([]float) timestamps;

            transforms_pos := read_s32(file, *pos);
            transforms, transforms_type := alloc_or_look_up_buffer(file, transforms_pos, true);
            engine_check(transforms_type == .JOINT_TRANSFORM);
            animation.transforms = cast,force([]Joint_Transform) transforms;

            engine_check(animation.transforms.count == animation.timestamps.count * mesh.skeleton.joints.count);
        }
    }

    if context.ack_mesh_texture_buffer_table.count > 0 {
        mesh.texture_buffers = allocate_self_array(Texture_Buffer, context.ack_mesh_texture_buffer_table.count);
        for temp_item : context.ack_mesh_texture_buffer_table {
            temp_buf := *temp_item.texture_buffer;
            out_buf := *mesh.texture_buffers[it_index];
            out_buf.* = temp_buf.*;
        }
    }

    // little awkward, but allocating on-struct arrays into a temp buffer then copying stuff over
    // and fixing the pointers avoids making a bunch of spaced-out allocations.
    mesh.self_cpu_allocation = alloc_string(context.ack_mesh_self_allocation.count);

    old_allocation := context.ack_mesh_self_allocation.data;
    new_allocation := mesh.self_cpu_allocation.data;
    memcpy(new_allocation, old_allocation, mesh.self_cpu_allocation.count);

    // pointer fixing needs to be done in layers...

    // layer 1
    move_pointer(xx *mesh.sections.data,                   old_allocation, new_allocation);
    move_pointer(xx *mesh.texture_buffers.data,            old_allocation, new_allocation);
    move_pointer(xx *mesh.skeleton.joints.data,            old_allocation, new_allocation);
    move_pointer(xx *mesh.skeleton.animations.data,        old_allocation, new_allocation);
    move_pointer(xx *mesh.skeleton.joint_name_hashes.data, old_allocation, new_allocation);

    // layer 2
    for *section : mesh.sections {
        move_pointer(xx *section.name.data,          old_allocation, new_allocation);
        move_pointer(xx *section.material.name.data, old_allocation, new_allocation);
    }
    for *joint : mesh.skeleton.joints {
        move_pointer(xx *joint.name.data, old_allocation, new_allocation);
    }
    for *animation : mesh.skeleton.animations {
        move_pointer(xx *animation.name.data,       old_allocation, new_allocation);
        move_pointer(xx *animation.timestamps.data, old_allocation, new_allocation);
        move_pointer(xx *animation.transforms.data, old_allocation, new_allocation);
    }

    if set_mesh_path_on_load {
        mesh.path = copy_string(path);
    }

    instanced.type = ifx is_static_mesh(mesh) then Mesh_Type.STATIC else .SKELETAL;

    upload_mesh_to_gpu(renderer, mesh);

    engine_log("mesh % loaded", path);

    return ref;
}

expand_cull_radius :: (radius: *float, vertices: []$T) {
    greatest_dist_sq: float;
    for v : vertices {
        dist_sq := length_squared(v.position);
        greatest_dist_sq = max(dist_sq, greatest_dist_sq);
    }
    radius.* = max(sqrt(greatest_dist_sq), radius.*);
}

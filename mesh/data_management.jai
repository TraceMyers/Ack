Mesh_Ref :: #type,isa Gen_Ref;

Mesh_Type :: enum u8 { STATIC; SKELETAL; }

Instanced_Mesh :: struct {
    mesh: Mesh;
    instances: union type: Mesh_Type {
        .STATIC   ,, static:   Component_Storage(Static_Mesh_Instance);
        .SKELETAL ,, skeletal: Component_Storage(Skeletal_Mesh_Instance);
    };
}

Managed_Meshes :: struct {
    path_lookup_table: Table(string, Mesh_Ref);
    instanced_meshes: Pool(Instanced_Mesh);
    animation_instances: Pool(Skeletal_Mesh_Animation_Instance);
    specializations: Pool(Mesh_Specialization_Params);
}

Skeletal_Animation_Playback_Control :: struct {
    animation: s32;
    speed: float;
}

set_managed_mesh_data :: (in_managed: *Managed_Meshes) {
    managed = in_managed;
    managed.instanced_meshes.track_generation = true;
}

create_mesh_instance :: (mesh_ref: Mesh_Ref, entity_ref: user_types.entity_id_type, component_or_array: *$T) -> *Skeletal_Mesh_Instance 
#modify { 
    return T == *Skeletal_Mesh_Instance || T == [..]*Skeletal_Mesh_Instance;
} {
    inst: *Skeletal_Mesh_Instance;

    instanced := get_instanced_mesh(mesh_ref);
    engine_check(.LOW, is_skeletal_mesh(*instanced.mesh));
    engine_check(.LOW, instanced.instances.type == .SKELETAL);

    #if T == {
    case *Skeletal_Mesh_Instance;
        inst = create_component(*instanced.instances.skeletal, entity_ref, component_or_array);
    case [..]*Skeletal_Mesh_Instance;
        engine_check(.LOW, component_or_array != null);
        inst = create_component_in_array(*instanced.instances.skeletal, entity_ref, component_or_array);
    }

    inst.ref = mesh_ref;
    return inst;
}

create_mesh_instance :: (mesh_ref: Mesh_Ref, entity_ref: user_types.entity_id_type, component_or_array: *$T) -> *Static_Mesh_Instance 
#modify { 
    return T == *Static_Mesh_Instance || T == [..]*Static_Mesh_Instance;
} {
    inst: *Static_Mesh_Instance;

    instanced := get_instanced_mesh(mesh_ref);
    engine_check(.LOW, is_static_mesh(*instanced.mesh));
    engine_check(.LOW, instanced.instances.type == .STATIC);

    #if T == {
    case *Static_Mesh_Instance;
        inst = create_component(*instanced.instances.static, entity_ref, component_or_array);
    case [..]*Static_Mesh_Instance;
        engine_check(.LOW, component_or_array != null);
        inst = create_component_in_array(*instanced.instances.static, entity_ref, component_or_array);
    }

    inst.ref = mesh_ref;
    return inst;
}

destroy_mesh_instance :: (entity_ref: user_types.entity_id_type, inst: **$T/Mesh_Instance, auto_shrink_instance_storage := false, reset_array_on_entity_if_empty := true) {
    instanced := get_instanced_mesh(inst.*.ref);

    if inst.*.specialization_params != -1 {
        pool_return(*managed.specializations, inst.*.specialization_params);
    }

    if instanced.instances.type == .STATIC {
        engine_check(.LOW, is_static_mesh(*instanced.mesh));
        destroy_component(*instanced.instances.static, entity_ref, xx inst, auto_shrink_instance_storage, reset_array_on_entity_if_empty);
    } else { // .SKELETAL
        engine_check(.LOW, is_skeletal_mesh(*instanced.mesh));
        destroy_component(*instanced.instances.skeletal, entity_ref, xx inst, auto_shrink_instance_storage, reset_array_on_entity_if_empty);
    }
}

get_mesh :: inline (inst: *Mesh_Instance) -> mesh: *Mesh {
    return get_mesh(inst.ref);
}

get_mesh :: inline (ref: Mesh_Ref) -> mesh: *Mesh {
    return *get_instanced_mesh(ref).mesh;
}

get_instanced_mesh :: inline (ref: Mesh_Ref) -> mesh: *Instanced_Mesh {
    instanced := *managed.instanced_meshes[ref.index];
    engine_check(.LOW, ref.generation == pool_get_item_generation(*managed.instanced_meshes, ref.index));
    return instanced;
}

// load .trm mesh from file
load_mesh :: (path: string, renderer: *Renderer, set_mesh_path_on_load := true) -> Mesh_Ref {
    engine_check(.LOW, path.count > 0);

    ref, newly_added := find_or_add(*managed.path_lookup_table, path);
    engine_check(.LOW, (ref.generation == 0) == newly_added);

    if !newly_added {
        return ref;
    }

    // doesn't seem like the option to temp allocate on-struct data is valuable
    engine_check(.LOW, context.allocator.proc != temp.proc);
    auto_release_temp();

    inst_index := pool_borrow(*managed.instanced_meshes);
    instanced := *managed.instanced_meshes[inst_index];

    ref.index      = xx inst_index;
    ref.generation = xx pool_get_item_generation(*managed.instanced_meshes, inst_index);

    mesh := *instanced.mesh;
    mesh.* = {allocator = context.allocator};

    file := read_entire_file(path,, temp);
    pos: int;
    header := read_string(file, *pos, 16);
    engine_check(.LOW, header == TeRM_Mesh_Header);

    version := read_s32(file, *pos);
    engine_check(.LOW, version == 1);
 
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
            engine_check(.LOW, section_name_type == .BYTE, "incorrect section type: %", section_name_type);
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
                engine_check(.LOW, false, "invalid index buffer type %", index_buffer_type);
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
            case .SKELETAL_VERTEX;
                section.vertices.type = .SKELETAL;
            case;
                engine_check(.LOW, false, "invalid vertex buffer type %", vertex_buffer_type);
            }

            matbuf_name_pos := read_s32(file, *pos);
            matbuf_name, matbuf_name_type := alloc_or_look_up_buffer(file, matbuf_name_pos, true);
            engine_check(.LOW, matbuf_name_type == .BYTE);

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
            engine_check(.LOW, anim_name_type == .BYTE);

            animation.name = string.{anim_name.count, anim_name.data};
            animation.interpolate = cast(bool) read_s32(file, *pos);
            
            timestamps_pos := read_s32(file, *pos);
            timestamps, timestamps_type := alloc_or_look_up_buffer(file, timestamps_pos, true);
            engine_check(.LOW, timestamps_type == .FLOAT);
            animation.timestamps = cast,force([]float) timestamps;

            transforms_pos := read_s32(file, *pos);
            transforms, transforms_type := alloc_or_look_up_buffer(file, transforms_pos, true);
            engine_check(.LOW, transforms_type == .JOINT_TRANSFORM);
            animation.transforms = cast,force([]Joint_Transform) transforms;

            engine_check(.LOW, animation.transforms.count == animation.timestamps.count * mesh.skeleton.joints.count);
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

    if is_static_mesh(mesh) {
        instanced.instances.type = .STATIC;
        engine_check(.LOW, instanced.instances.static.chunks.count == 0 && instanced.instances.static.chunks.data == null);
    } else {
        instanced.instances.type = .SKELETAL;
        engine_check(.LOW, instanced.instances.skeletal.chunks.count == 0 && instanced.instances.skeletal.chunks.data == null);
    }

    upload_mesh_to_gpu(renderer, mesh);

    engine_log(.MEDIUM, "mesh % loaded", path);

    return ref;
}

// there is no free_mesh / destroy_mesh procedure because that would require general
// purpose gpu allocation. since that adds complexity to the renderer, I'm going to
// leave that feature out for now.

#scope_file

managed: *Managed_Meshes;

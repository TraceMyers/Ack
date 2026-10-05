#load "animation.jai";
#load "convex.jai";
#load "data_management.jai";
#load "merge.jai";

NO_JOINT : s16 : -1;

Static_Mesh_Vertex :: struct {
    position: Vector3;
    normal:   Vector3;
    tangent:  Vector4;
    uv_0:     Vector2;
    uv_1:     Vector2;
    color:    Color4f;
}

// having a using #as Static_Mesh_Vertex field would make sense, but I like parsing the vertex
// input binding format from the struct rather than handmaking the bindings, and it's easier
// to do that when the type is composed of up to one layer of non-primitive types. 
// (vertex type -> Vector3 -> float rather than vertex type -> other vertex type -> Vector3 -> float)
Skeletal_Mesh_Vertex :: struct {
    position: Vector3;
    normal:   Vector3;
    tangent:  Vector4;
    uv_0:     Vector2;
    uv_1:     Vector2;
    color:    Color4f;
    joints:   [4]u16;
    weights:  [4]float32;
}

Mesh_Index_Buffer :: struct {
    type:  enum { U16; U32; };
    count: s32;
    gpu_allocation: GPU_Buffer;
    using cpu_allocation: union {
        _u16: []u16;
        _u32: []u32;
    }
}

Mesh_Vertex_Buffer :: struct {
    type: enum { STATIC; SKELETAL; };
    count: s32;
    gpu_allocation: GPU_Buffer;
    using cpu_allocation: union {
        static:  []Static_Mesh_Vertex;
        skinned: []Skeletal_Mesh_Vertex;
    }
}

Texture_Buffer :: struct {
    width: s32;
    height: s32;
    index: s16;
    // may not be allocated on cpu
    cpu_allocation: []Color4b;
}

is_static_mesh :: inline (ref: Mesh_Ref) -> bool {
    return is_static_mesh(get_mesh(ref));
}

is_static_mesh :: inline (inst: *Mesh_Instance) -> bool {
    return is_static_mesh(get_mesh(inst));
}

is_static_mesh :: inline (mesh: *Mesh) -> bool {
    return mesh.skeleton.joints.count == 0;
}

is_skeletal_mesh :: inline (ref: Mesh_Ref) -> bool {
    return is_skeletal_mesh(get_mesh(ref));
}

is_skeletal_mesh :: inline (inst: *Mesh_Instance) -> bool {
    return is_skeletal_mesh(get_mesh(inst));
}

is_skeletal_mesh :: inline (mesh: *Mesh) -> bool {
    return !is_static_mesh(mesh);
}

Mesh :: struct {
    path: string;

    sections:        []Mesh_Section;
    texture_buffers: []Texture_Buffer;
    skeleton:        Skeleton;

    self_cpu_allocation: string;
    // texture buffers are allocated with stbi. others use this one. (strings are 'self')
    allocator: Allocator;
}

Mesh_Section :: struct {
    name: string;
    indices:  Mesh_Index_Buffer;
    vertices: Mesh_Vertex_Buffer;
    material: Material;
}

Texture :: struct {
    mag_filter: Texture_Filter;
    min_filter: Texture_Filter;
    horizontal_wrap: Texture_Wrap;
    vertical_wrap:   Texture_Wrap;
    local_buffer: s16 = -1;
    global_buffer: s16 = -1;
}

Material :: struct {
    name: string;

    alpha_mode: Material_Alpha_Mode;

    albedo_uv:    s8;
    metallic_uv:  s8;
    roughness_uv: s8;
    normal_uv:    s8;
    occlusion_uv: s8;
    emissive_uv:  s8;

    index: s16;

    discard_alpha_cutoff_if_masked_alpha := 0.5;

    // default values are meant to look obviously unconfigured
    albedo_factor    := COLOR4F_MAGENTA;
    emissive_factor  := COLOR4F_WHITE;
    metallic_factor  := 1.0; 
    roughness_factor := 1.0;

    albedo_texture:    Texture;
    normal_texture:    Texture;
    emissive_texture:  Texture;
    // occlusion, roughness, metallic
    orm_texture: Texture;
}

Joint :: struct {
    name:               string;
    parent:             s16;  // -1 = root
    inverse_bind_pose:  Matrix4;
    local_rest_pose:    Joint_Transform;
}

Joint_Transform :: struct {
    translation: Vector3;
    rotation:    Quaternion;
    scale:       Vector3;
}

Skeleton :: struct {
    joints:     []Joint;
    animations: []Skeletal_Animation;
    joint_name_hashes: []u32;
}

Skeletal_Pose :: struct {
    allocation:      []u8;
    local_joints:    []Joint_Transform;
    model_joints:    []Matrix4;    // local accumulated up the hierarchy
    skinning_joints: []Matrix4;    // world * inverse_bind_pose, uploaded to gpu
}

Skeletal_Mesh_Animation_Instance :: struct {
    index:             s32;
    real_time:         float;
    time:              float;
    speed:             float = 1;
    root_translation:  Root_Translation;
    blend_alpha:       float = 1;

    loop:              bool;
    loop_counter:      s32;

    // user_data:         [4]float;

    // for storage. animation instances are an embedded linked list.
    next:      s32 = -1;
    prev:      s32 = -1;
}

Mesh_Attachment :: struct {
    translation: Vector3;
    rotation: Quaternion;
    scale := Vector3.{1,1,1};
    skeletal_mesh_joint: s16 = NO_JOINT; 
}

Mesh_Instance :: struct {
    ref: Mesh_Ref;
    attachment: Mesh_Attachment;
    specialization_params: s32 = -1;
    visible := true;
}

Static_Mesh_Instance :: Mesh_Instance;

Skeletal_Mesh_Instance :: struct {
    using #as base: Mesh_Instance; 
    // points to a single entry in world.skeletal_mesh_animation_instances
    idle: s32 = -1;
    // points to the first entry in this mesh's linked list of animations within world.skeletal_mesh_animation_instances
    animations: s32 = -1;
    default_root_translation: Root_Translation;
    playback: []Skeletal_Animation_Playback_Control;

    pose: Skeletal_Pose;
    first_animation_instance: s32 = -1;

    move_alpha: float32;
    move_speed: float32;
}

Material_Alpha_Mode :: enum u8 {
    OPAQUE;
    MASK;
    BLEND;
}

Texture_Filter :: enum u8 {
    LINEAR;
    NEAREST;
}

Texture_Wrap :: enum u8 {
    CLAMP_TO_EDGE;
    MIRRORED_REPEAT;
    REPEAT;
}

TeRM_Mesh_Header :: "TeRM-Mesh\0\0\0\0\0\0\0";

Block_Header :: struct {
    item_count: s32;
    size_of_one_item: s32;
    offset_to_block: s32;
}

Buffer_Table_Item :: struct {
    file_position: s32;
    bytes: []u8;
    type: Buffer_Type;
    // if the table item is a texture buffer, this will be set.
    texture_buffer: Texture_Buffer;
    is_texture_buffer: bool;
}

Texture_Buffer_Table_Item :: struct {
    file_position: s32;
    texture_buffer: Texture_Buffer;
}

Buffer_Type :: enum s32 {
    BYTE;
    U16;
    U32;
    FLOAT;
    STATIC_VERTEX;
    SKELETAL_VERTEX;
    JOINT_TRANSFORM;
    NONE :: S32_MAX;
}

#scope_module

read_u16     :: #bake_arguments read_primitive(T=u16);
read_s32     :: #bake_arguments read_primitive(T=s32);
read_float   :: #bake_arguments read_primitive(T=float32);
read_vector2 :: #bake_arguments read_primitive(T=Vector2);
read_vector3 :: #bake_arguments read_primitive(T=Vector3);
read_vector4 :: #bake_arguments read_primitive(T=Vector4);
read_color4f :: #bake_arguments read_primitive(T=Color4f);
read_matrix4 :: #bake_arguments read_primitive(T=Matrix4);
read_mesh_static_vertex :: #bake_arguments read_primitive(T=Static_Mesh_Vertex);

read_block_header :: (file: string, location: *int) -> Block_Header {
    header: Block_Header;
    header.item_count       = read_s32(file, location);
    header.size_of_one_item = read_s32(file, location);
    header.offset_to_block  = read_s32(file, location);
    return header;
}

read_string :: inline (file: string, location: *int, length: int) -> string {
    engine_check(.LOW, location.* + length <= file.count);
    str := string.{length, file.data + location.*};
    location.* += length;
    return str;
}

read_primitive :: inline (file: string, location: *int, $T: Type) -> T {
    engine_check(.LOW, location.* + size_of(T) <= file.count);
    val := (cast(*T) (file.data + location.*)).*;
    location.* += size_of(T);
    return val;
}

read_array :: inline (array: []$T, file: string, location: *int, count: int) {
    for 0..count-1 {
        array[it] = read_primitive(file, location, T);
    }
}

read_mesh_skinned_vertex :: inline (vert: *Skeletal_Mesh_Vertex, file: string, location: *int) {
    static := cast(*Static_Mesh_Vertex) vert;
    static.* = read_mesh_static_vertex(file, location);
    read_array(vert.joints, file, location, 4);
    read_array(vert.weights, file, location, 4);
}

read_joint :: inline (joint: *Joint, file: string, location: *int) {
    offset_to_name := read_s32(file, location);
    joint_name_bytes := alloc_buffer(file, offset_to_name, true);
    joint.name              = {joint_name_bytes.count, joint_name_bytes.data};
    joint.parent            = xx read_s32(file, location);
    joint.inverse_bind_pose = read_matrix4(file, location);
    read_joint_transform(*joint.local_rest_pose, file, location);
}

read_joint_transform :: inline (tform: *Joint_Transform, file: string, location: *int) {
    tform.translation = read_vector3(file, location);
    tform.rotation    = xx,force read_vector4(file, location);
    tform.scale       = read_vector3(file, location);
}

read_texture :: (tex: *Texture, file: string, pos: *int) {
    offset_to_buffer := read_s32(file, pos);
    if offset_to_buffer == -1 {
        tex.local_buffer = -1;
    } else {
        tex.local_buffer = xx alloc_or_look_up_texture_buffer(file, offset_to_buffer);
    }
    tex.mag_filter      = cast(Texture_Filter) read_s32(file, pos);
    tex.min_filter      = cast(Texture_Filter) read_s32(file, pos);
    tex.horizontal_wrap = cast(Texture_Wrap) read_s32(file, pos);
    tex.vertical_wrap   = cast(Texture_Wrap) read_s32(file, pos);
}

allocate_self_array :: ($T: Type, count: int) -> []T {
    buf_pos := align_up(context.ack_mesh_self_allocation.count, #run align_of(T));
    buf_end := buf_pos + size_of(T) * count;
    engine_check(.LOW, context.ack_mesh_self_allocation.allocated >= buf_end);
    array_resize(*context.ack_mesh_self_allocation, buf_end);
    array: []T = ---;
    array.data = xx (context.ack_mesh_self_allocation.data + buf_pos);
    array.count = count;
    return array;
}

move_pointer :: inline (ptr: **u8, old_allocation: *u8, new_allocation: *u8) {
    offset := cast(s64) ptr.* - cast(s64) old_allocation;
    ptr.* = new_allocation + offset;
}

clear_mesh_loading_arrays :: () {
    array_reset(*context.ack_mesh_self_allocation); 
    array_reset(*context.ack_mesh_buffers_allocation);
}

alloc_or_look_up_texture_buffer :: (file: string, start_pos: int) -> s32 {
    for item : context.ack_mesh_texture_buffer_table {
        if item.file_position == start_pos {
            return xx it_index;
        }
    }

    new_item := array_add(*context.ack_mesh_texture_buffer_table);
    new_item.file_position = xx start_pos;

    pos := start_pos;

    type             := cast(Buffer_Type) read_s32(file, *pos);
    count            := read_s32(file, *pos);
    size_of_one_item := read_s32(file, *pos);
    
    channels: s32;
    buf := *new_item.texture_buffer;
    buf.cpu_allocation.data = xx stbi_load_from_memory(file.data + pos, count, *buf.width, *buf.height, *channels, 4);
    engine_check(.LOW, channels == 4);
    buf.cpu_allocation.count = count / 4;

    return xx (context.ack_mesh_texture_buffer_table.count-1);
}

alloc_or_look_up_buffer :: (file: string, start_pos: int, self_allocation := false) -> []u8, Buffer_Type {
    for item : context.ack_mesh_buffer_table {
        if item.file_position == start_pos {
            return item.bytes, item.type;
        }
    }
    new_item := array_add(*context.ack_mesh_buffer_table);
    new_item.file_position = xx start_pos;
    new_item.bytes, new_item.type = alloc_buffer(file, start_pos, self_allocation);
    return new_item.bytes, new_item.type;
}

alloc_buffer :: (file: string, start_pos: int, self_allocation: bool) -> []u8, Buffer_Type {
    pos := start_pos;

    type             := cast(Buffer_Type) read_s32(file, *pos);
    count            := read_s32(file, *pos);
    size_of_one_item := read_s32(file, *pos);

    bytes: []u8;
    
    if type == {
    case .BYTE;
        engine_check(.LOW, size_of_one_item == 1);
        bytes = ifx self_allocation 
            then allocate_self_array(u8, count) 
            else make_static_array(u8, count);
        read_array(bytes, file, *pos, count);
    case .U16;
        engine_check(.LOW, size_of_one_item == 2);
        bytes = cast,force([]u8) ifx self_allocation 
            then allocate_self_array(u16, count) 
            else make_static_array(u16, count);
        read_array(cast,force([]u16) bytes, file, *pos, count);
    case .U32;
        engine_check(.LOW, size_of_one_item == 4);
        bytes = cast,force([]u8) ifx self_allocation 
            then allocate_self_array(u32, count) 
            else make_static_array(u32, count);
        read_array(cast,force([]u32) bytes, file, *pos, count);
    case .FLOAT;
        engine_check(.LOW, size_of_one_item == 4);
        bytes = cast,force([]u8) ifx self_allocation 
            then allocate_self_array(float, count)
            else make_static_array(float, count);
        read_array(cast,force([]float32) bytes, file, *pos, count);
    case .STATIC_VERTEX;
        engine_check(.LOW, size_of_one_item == size_of(Static_Mesh_Vertex));
        bytes = xx,force make_static_array(Static_Mesh_Vertex, count);
        vertices := cast,force([]Static_Mesh_Vertex) bytes;
        for *v : vertices {
            v.* = read_mesh_static_vertex(file, *pos);
        }
    case .SKELETAL_VERTEX;
        engine_check(.LOW, size_of_one_item == size_of(Skeletal_Mesh_Vertex));
        bytes = xx,force make_static_array(Skeletal_Mesh_Vertex, count);
        vertices := cast,force([]Skeletal_Mesh_Vertex) bytes;
        for *v : vertices {
            read_mesh_skinned_vertex(v, file, *pos);
        }
    case .JOINT_TRANSFORM;
        engine_check(.LOW, size_of_one_item == size_of(Joint_Transform));
        bytes = xx,force ifx self_allocation
            then allocate_self_array(Joint_Transform, count)
            else make_static_array(Joint_Transform, count);
        transforms := cast,force([]Joint_Transform) bytes;
        for *t : transforms {
            read_joint_transform(t, file, *pos);
        }
    case;
        engine_check(.LOW, false, "invalid buffer type % read from ack mesh file", type);
    }

    return bytes, type;
}


// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

#version 460
#extension GL_EXT_nonuniform_qualifier   : require
#extension GL_EXT_scalar_block_layout    : require
#extension GL_EXT_buffer_reference       : require
// uint64_t,int64_t
#extension GL_EXT_shader_explicit_arithmetic_types_int64 : require
// for depth compute
#extension GL_EXT_samplerless_texture_functions : require


// ------------------------------------------------------------ types
// every struct here mirrors a jai struct, and blocks use scalar layout, which matches jai's
// packing as long as every field is a 4 byte scalar or made of them. 8 byte scalars also match,
// as long as they're placed at 8 byte aligned offsets and the struct's size stays a multiple of 8.

// mirrors Frame_Data
struct Frame_Data {
    mat4  view;
    mat4  view_projection;
    vec3  camera_position;
    vec3  camera_forward;
    vec3  camera_up;
    vec3  camera_right;
    vec3  light_direction;

    float time;
    float delta_time;
    float camera_near;
    float camera_far;
    float depth_view_mode_max_distance;
};

// mirrors GPU_Material
struct Material {
    vec4 albedo_factor;
    vec4 emissive_factor;
    float metallic_factor;
    float roughness_factor;

    float alpha_cutoff;

    int albedo_uv;
    int metallic_uv;
    int roughness_uv;
    int normal_uv;
    int occlusion_uv;
    int emissive_uv;

    int albedo_tex;
    int normal_tex;
    int emissive_tex;
    int orm_tex;
};

// todo: billboards aren't ported to the new renderer yet
struct Billboard_Instance {
    vec3 position;      float _pad0;
    vec4 tint;
    vec2 scale;
    vec2 uv_offset;
    vec2 uv_scale;
    uint texture_index;
    int layer;
};

// mirrors Draw_Section. one per indirect draw, indexed by gl_DrawID.
struct Draw_Section {
    uint64_t vertices; // address of this section's vertices
    int      material;
    int      _pad;
};

// mirrors Draw_FX
struct Draw_FX {
    int   flags;            // 0x1 = flash, 0x2 = tint (Draw_FX_Flags, in Draw_FX member order)
    float flash_rate;
    float flash_value;
    float flash_begin_time;
    vec3  tint;
};

// mirrors Instance_Data. indexed by gl_InstanceIndex.
struct Instance_Data {
    mat4 transform;
    mat4 inverse_transpose_transform;
    uint64_t entity_id; // user_types.entity_id_to_u64 of the instance's entity
    int  joint_offset;  // -1 if not skinned
    Draw_FX draw_fx;
};

// mirrors Line_Vertex
struct Line_Vertex {
    vec3 position;
    vec4 color;
};

// mirrors Static_Mesh_Vertex
struct Static_Mesh_Vertex {
    vec3 position;
    vec3 normal;
    vec4 tangent;
    vec2 uv_0;
    vec2 uv_1;
    vec4 color;
};

// mirrors Skeletal_Mesh_Vertex. jai's joints are [4]u16, read as two packed uints.
struct Skeletal_Mesh_Vertex {
    vec3 position;
    vec3 normal;
    vec4 tangent;
    vec2 uv_0;
    vec2 uv_1;
    vec4 color;
    uint joints_packed[2];
    vec4 weights;
};

uvec4 unpack_joints(uint packed[2]) {
    return uvec4(packed[0] & 0xffff, packed[0] >> 16, packed[1] & 0xffff, packed[1] >> 16);
}

// ---------------------------------------------- buffer references
// buffers are reached by device address rather than descriptors

layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Frame_Ref            { Frame_Data           data; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Sections_Ref         { Draw_Section         s[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Instances_Ref        { Instance_Data        i[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Joints_Ref           { mat4                 m[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Materials_Ref        { Material             m[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Static_Vertices_Ref  { Static_Mesh_Vertex   v[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Skinned_Vertices_Ref { Skeletal_Mesh_Vertex v[]; };
layout(buffer_reference, scalar, buffer_reference_align=4) readonly buffer Line_Vertices_Ref    { Line_Vertex          v[]; };

// ----------------------------------------------- universal bindings

// mirrors Push_Constants
layout(push_constant, scalar) uniform Push_Constants {
    Frame_Ref     frame;
    Sections_Ref  sections;
    Instances_Ref instances;
    Joints_Ref    joints;
    Materials_Ref materials;
    Line_Vertices_Ref vertices;
} pc;

#define frame (pc.frame.data)

// the only descriptor set
layout(set=0, binding=0) uniform sampler2D textures[];

// ------------------------------------------------------- procedures


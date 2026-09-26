#version 460
#extension GL_EXT_nonuniform_qualifier   : require
#extension GL_EXT_scalar_block_layout    : require
#extension GL_ARB_shader_draw_parameters : enable

// -------------------------------------------------------- constants

#define MAX_MATERIALS 1024

// ------------------------------------------------------- procedures

// ------------------------------------------------------------ types

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

struct Billboard_Instance {
    vec3 position;      float _pad0;
    vec4 tint;
    vec2 scale;
    vec2 uv_offset;
    vec2 uv_scale;  
    uint texture_index;
    int layer;
};

struct Mesh_Section_Shader_Data {
    int mesh_instance_offset;
    int mesh_instance_count;
    int material;
};

struct Mesh_Specialization {
    int flags;
    float flash_rate;
    float flash_value;
    float flash_begin_time;
    vec3 tint;
};

struct Skinned_Mesh_Instance_Shader_Data {
    mat4 transform;
    int layer;
    int joint_transform_offset;
    Mesh_Specialization specialization;
};

struct Mesh_Instance_Shader_Data {
    mat4 transform;
    int layer;
    Mesh_Specialization specialization;
};

// ----------------------------------------------- universal bindings

layout(set=0, binding=0) uniform sampler2D textures[];

layout(set=1, binding=0, scalar) readonly buffer Material_Block {
    Material materials[];
} material_block;

layout(set=2, binding=0) uniform Per_Frame_Uniform_Buffer {
    mat4  view;
    mat4  view_projections[6];
    vec3  camera_position; float _pad0;
    vec3  camera_forward;  float _pad1;
    vec3  camera_up;       float _pad2;
    vec3  camera_right;    float _pad3;
    vec3  light_direction; float _pad4;
    float time;
    float delta_time;
} frame;

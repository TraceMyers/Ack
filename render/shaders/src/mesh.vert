layout(location=0) in vec3 in_position;
layout(location=1) in vec3 in_normal;
layout(location=2) in vec4 in_tangent;
layout(location=3) in vec2 in_uv_0;
layout(location=4) in vec2 in_uv_1;
layout(location=5) in vec4 in_color;

layout(location=0) out      mat3 out_tbn;
// 1, 2 = mat cols
layout(location=3) out      vec2 out_uv_0;
layout(location=4) out      vec2 out_uv_1;
layout(location=5) out      vec4 out_color;
layout(location=6) out      vec4 add_color;
layout(location=7) out      vec4 tint;
layout(location=8) out flat int  out_material_id;

layout(set=3, binding=0, scalar) readonly buffer Mesh_Instance_Data {
    Mesh_Instance_Shader_Data array[];
} mesh_instances;

layout(set=4, binding=0, scalar) readonly buffer Mesh_Section_Data {
    Mesh_Section_Shader_Data array[];
} mesh_sections;

void main() {
    Mesh_Section_Shader_Data  mesh_section = mesh_sections.array[gl_DrawID];
    int mesh_instance_index = mesh_section.mesh_instance_offset + gl_InstanceIndex;
    Mesh_Instance_Shader_Data mesh_inst = mesh_instances.array[mesh_instance_index];

    mat4 model = mesh_inst.transform;

    // generating the orthonormal axes of this triangle in world space
    vec3 T = normalize(vec3(vec4(in_tangent.xyz, 0.0) * model));
    vec3 N = normalize(vec3(vec4(in_normal.xyz,  0.0) * model));
    vec3 B = cross(N, T) * in_tangent.w; // handedness - which direction does this ortho vector point of the two?

    add_color = vec4(0,0,0,0);
    tint = vec4(1,1,1,1);

    gl_Position = vec4(in_position, 1.0) * model * frame.view_projections[mesh_inst.layer];

    ## mesh_specialization

    out_tbn         = mat3(T, B, N);
    out_uv_0        = in_uv_0;
    out_uv_1        = in_uv_1;
    out_color       = in_color * tint;
    out_material_id = mesh_section.material;
}

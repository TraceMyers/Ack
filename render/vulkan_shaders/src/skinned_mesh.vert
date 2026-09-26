layout(location=0) in vec3  in_position;
layout(location=1) in vec3  in_normal;
layout(location=2) in vec4  in_tangent;
layout(location=3) in vec2  in_uv_0;
layout(location=4) in vec2  in_uv_1;
layout(location=5) in vec4  in_color;
layout(location=6) in uvec4 in_joints;
layout(location=7) in vec4  in_weights;

layout(location=0) out      mat3 out_tbn;
// 1, 2 = mat cols
layout(location=3) out      vec2 out_uv_0;
layout(location=4) out      vec2 out_uv_1;
layout(location=5) out      vec4 out_color;
layout(location=6) out      vec4 add_color;
layout(location=7) out      vec4 tint;
layout(location=8) out flat int  out_material_id;

layout(set=3, binding=0, scalar) readonly buffer Mesh_Instance_Data {
    Skinned_Mesh_Instance_Shader_Data array[];
} mesh_instances;

layout(set=4, binding=0, scalar) readonly buffer Mesh_Section_Data {
    Mesh_Section_Shader_Data array[];
} mesh_sections;

layout(set=5, binding=0, scalar) readonly buffer Joint_Data {
    mat4 array[];
} skinning_joints;

vec4 skinned_mesh_transform_vector(vec4 vector) {
    Mesh_Section_Shader_Data mesh_section = mesh_sections.array[gl_DrawID];
    int mesh_instance_index = mesh_section.mesh_instance_offset + gl_InstanceIndex;
    Skinned_Mesh_Instance_Shader_Data mesh_inst = mesh_instances.array[mesh_instance_index];

    int joint_offset = mesh_inst.joint_transform_offset;

    mat4 skinning_mat_a = skinning_joints.array[in_joints[0] + joint_offset];
    vec4 skinned_position_a = (vector * skinning_mat_a) * in_weights[0];

    mat4 skinning_mat_b = skinning_joints.array[in_joints[1] + joint_offset];
    vec4 skinned_position_b = (vector * skinning_mat_b) * in_weights[1];

    mat4 skinning_mat_c = skinning_joints.array[in_joints[2] + joint_offset];
    vec4 skinned_position_c = (vector * skinning_mat_c) * in_weights[2];

    mat4 skinning_mat_d = skinning_joints.array[in_joints[3] + joint_offset];
    vec4 skinned_position_d = (vector * skinning_mat_d) * in_weights[3];

    return skinned_position_a + skinned_position_b + skinned_position_c + skinned_position_d;
}

void main() {
    Mesh_Section_Shader_Data mesh_section = mesh_sections.array[gl_DrawID];
    int mesh_instance_index = mesh_section.mesh_instance_offset + gl_InstanceIndex;
    Skinned_Mesh_Instance_Shader_Data mesh_inst = mesh_instances.array[mesh_instance_index];

    vec4 homogenous_position = vec4(in_position, 1.0);
    vec4 skinned_position = skinned_mesh_transform_vector(homogenous_position);
    mat4 model = mesh_inst.transform;

    gl_Position = skinned_position * model * frame.view_projections[mesh_inst.layer];

    vec4 skinned_tangent = normalize(skinned_mesh_transform_vector(in_tangent));
    vec4 skinned_normal  = normalize(skinned_mesh_transform_vector(vec4(in_normal.xyz, 1)));
    // vec4 skinned_tangent = in_tangent;
    // vec4 skinned_normal  = vec4(in_normal.xyz, 1);

    // generating the orthonormal axes of this vertex in world space
    vec3 T = normalize(vec3(vec4(skinned_tangent.xyz, 0.0) * model));
    vec3 N = normalize(vec3(vec4(skinned_normal.xyz,  0.0) * model));
    vec3 B = cross(N, T) * skinned_tangent.w; // handedness - which direction does this ortho vector point of the two?

    tint = vec4(1,1,1,1);
    add_color = vec4(0,0,0,0);

    ## mesh_specialization

    out_tbn         = mat3(T, B, N);
    out_uv_0        = in_uv_0;
    out_uv_1        = in_uv_1;
    out_color       = in_color;
    out_material_id = mesh_section.material;
}

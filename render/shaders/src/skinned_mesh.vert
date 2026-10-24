layout(location=0) out      mat3 out_tbn;
// 1, 2 = mat cols
layout(location=3) out      vec2 out_uv_0;
layout(location=4) out      vec2 out_uv_1;
layout(location=5) out      vec4 out_color;
layout(location=6) out      vec4 add_color;
layout(location=7) out      vec4 tint;
layout(location=8) out flat int  out_material_id;
layout(location=9) out flat int  out_entity_id;

vec4 skinned_mesh_transform_vector(vec4 vector, uvec4 joints, vec4 weights, int joint_offset) {
    vec4 skinned = vec4(0);
    for (int i = 0; i < 4; i += 1) {
        mat4 skinning_mat = pc.joints.m[joint_offset + int(joints[i])];
        skinned += (vector * skinning_mat) * weights[i];
    }
    return skinned;
}

void main() {
    // vertices are pulled from this draw's section. the index buffer gives gl_VertexIndex.
    Draw_Section section = pc.sections.s[gl_DrawID];
    Skeletal_Mesh_Vertex vertex = Skinned_Vertices_Ref(section.vertices).v[gl_VertexIndex];
    // the draw's firstInstance is where its instances start
    Instance_Data mesh_inst = pc.instances.i[gl_InstanceIndex];

    uvec4 joints = unpack_joints(vertex.joints_packed);
    int joint_offset = mesh_inst.joint_offset;

    vec4 skinned_position = skinned_mesh_transform_vector(vec4(vertex.position, 1.0), joints, vertex.weights, joint_offset);
    mat4 model = mesh_inst.transform;

    gl_Position = skinned_position * model * frame.view_projection;

    vec4 skinned_tangent = normalize(skinned_mesh_transform_vector(vertex.tangent, joints, vertex.weights, joint_offset));
    vec4 skinned_normal  = normalize(skinned_mesh_transform_vector(vec4(vertex.normal.xyz, 1), joints, vertex.weights, joint_offset));

    // generating the orthonormal axes of this vertex in world space
    vec3 T = normalize(vec3(vec4(skinned_tangent.xyz, 0.0) * model));
    vec3 N = normalize(vec3(vec4(skinned_normal.xyz,  0.0) * model));
    vec3 B = cross(N, T) * skinned_tangent.w; // handedness - which direction does this ortho vector point of the two?

    tint = vec4(1,1,1,1);
    add_color = vec4(0,0,0,0);

    ## mesh_specialization

    out_tbn         = mat3(T, B, N);
    out_uv_0        = vertex.uv_0;
    out_uv_1        = vertex.uv_1;
    out_color       = vertex.color;
    out_material_id = section.material;
    out_entity_id   = mesh_inst.entity_id;
}

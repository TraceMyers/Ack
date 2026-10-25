layout(location=0) out      mat3 out_tbn;
// 1, 2 = mat cols
layout(location=3) out      vec2 out_uv_0;
layout(location=4) out      vec2 out_uv_1;
layout(location=5) out      vec4 out_color;
layout(location=6) out      vec4 add_color;
layout(location=7) out      vec4 tint;
layout(location=8) out flat int  out_material_id;
layout(location=9) out flat uint64_t out_entity_id;

void main() {
    // vertices are pulled from this draw's section. the index buffer gives gl_VertexIndex.
    Draw_Section section = pc.sections.s[gl_DrawID];
    Static_Mesh_Vertex vertex = Static_Vertices_Ref(section.vertices).v[gl_VertexIndex];
    // the draw's firstInstance is where its instances start
    Instance_Data mesh_inst = pc.instances.i[gl_InstanceIndex];

    mat4 model = mesh_inst.transform;

    // generating the orthonormal axes of this triangle in world space
    vec3 T = normalize(vec3(vec4(vertex.tangent.xyz, 0.0) * model));
    vec3 N = normalize(vec3(vec4(vertex.normal.xyz,  0.0) * model));
    vec3 B = cross(N, T) * vertex.tangent.w; // handedness - which direction does this ortho vector point of the two?

    add_color = vec4(0,0,0,0);
    tint = vec4(1,1,1,1);

    gl_Position = vec4(vertex.position, 1.0) * model * frame.view_projection;

    ## mesh_draw_fx

    out_tbn         = mat3(T, B, N);
    out_uv_0        = vertex.uv_0;
    out_uv_1        = vertex.uv_1;
    out_color       = vertex.color * tint;
    out_material_id = section.material;
    out_entity_id   = mesh_inst.entity_id;
}

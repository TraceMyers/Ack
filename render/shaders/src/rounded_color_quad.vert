layout(location=0) out vec4  out_color;
layout(location=1) out vec2  out_uv;
layout(location=2) out vec2  out_dimensions;
layout(location=3) out float out_rounding;

void main() {
    Quad_Vertex vertex = pc.quad_vertices.v[gl_VertexIndex];
    gl_Position    = vec4(vertex.position, 0.0, 1.0);
    out_color      = vertex.color;
    out_uv         = vertex.uv;
    out_rounding   = vertex.rounding;
    out_dimensions = vertex.dimensions;
}

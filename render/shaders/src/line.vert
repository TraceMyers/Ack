layout(location=0) out vec4 out_color;

void main() {
    Line_Vertex vertex = pc.vertices.v[gl_VertexIndex];
    gl_Position = vec4(vertex.position, 1.0) * frame.view_projection;
    out_color = vertex.color;
}

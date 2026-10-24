layout(location=0) in vec3 in_position;
layout(location=1) in vec3 in_normal;
layout(location=2) in vec4 in_tangent;
layout(location=3) in vec2 in_uv_0;
layout(location=4) in vec2 in_uv_1;
layout(location=5) in vec4 in_color;

layout(location=0) out vec4 out_color;

// todo: not ported to the new renderer yet (vertex pulling, no pipeline)
void main() {
    gl_Position = vec4(in_position, 1.0) * frame.view_projection;
    out_color = in_color;
}

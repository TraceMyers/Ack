layout(location=0) in      vec2 in_uv;
layout(location=1) in      vec4 in_tint;
layout(location=2) in flat uint in_texture_index;

layout(location=0) out vec4 out_color;

void main() {
    out_color = texture(textures[nonuniformEXT(in_texture_index)], in_uv) * in_tint; 
}

layout(location=0) in mat3 in_tbn;
// 1,2 = mat cols
layout(location=3) in      vec2 in_uv_0;
layout(location=4) in      vec2 in_uv_1;
layout(location=5) in      vec4 in_color;
layout(location=6) in      vec4 add_color;
layout(location=7) in      vec4 tint;
layout(location=8) in flat int  in_material_id;

layout(location=0) out vec4 color;

void main() {
    Material mat = material_block.materials[in_material_id]; 
    vec2 uvs[2] = vec2[2](in_uv_0, in_uv_1);

    if (mat.albedo_tex != -1) {
        color = texture(textures[nonuniformEXT(mat.albedo_tex)], uvs[mat.albedo_uv]) * mat.albedo_factor * in_color;
    } else {
        color = mat.albedo_factor * in_color;
    }

    color *= tint;

    // todo: alt non-opaque/masked shader with parametric cutoff and pipeline has blending. use only
    // on sections that call for it
    // if (color.a < 0.5) {
    //     discard;
    // }

    vec3 map_normal;

    if (mat.normal_tex != -1) {
        map_normal = texture(textures[nonuniformEXT(mat.normal_tex)], uvs[mat.normal_uv]).rgb * 2.0 - 1.0;
    } else {
        map_normal = vec3(0,0,1);
    }

    vec3 world_normal = normalize(in_tbn * map_normal);

    float ambient_light = 0.4;
    float normal_dot_light = max(dot(frame.light_direction, -world_normal), 0);
    float light_value = normal_dot_light * (1.0 - ambient_light) + ambient_light;
    // float light_value = normal_dot_light;// + ambient_light;

    color.rgb *= light_value;

    color += add_color;
}

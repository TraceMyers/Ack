layout(location=0) in vec3 in_position;
layout(location=1) in vec3 in_normal;
layout(location=2) in vec4 in_tangent;
layout(location=3) in vec2 in_uv_0;
layout(location=4) in vec2 in_uv_1;
layout(location=5) in vec4 in_color;

layout(location=0) out      vec2 out_uv;
layout(location=1) out      vec4 out_tint;
layout(location=2) out flat uint out_texture_index;

// std430 makes it so arrays of data are packed correctly rather
// than having each element aligned to the struct's alignment.
// does nothing here probably a good idea to always use it.
layout(set=3, binding=0, std430) readonly buffer Instance_Data {
    Billboard_Instance instances[];
} instance_data;

void main() {
    Billboard_Instance inst = instance_data.instances[gl_InstanceIndex];

    float right_distance = in_position.x * inst.scale.x;
    float up_distance    = in_position.y * inst.scale.y;

    vec3 world_offset = frame.camera_up * up_distance + frame.camera_right * right_distance;
    vec3 world_pos    = inst.position.xyz + world_offset;

    gl_Position = vec4(world_pos, 1.0) * frame.view_projections[inst.layer];

    out_tint          = inst.tint;
    out_uv            = inst.uv_offset + in_uv_0 * inst.uv_scale;
    out_texture_index = inst.texture_index;
}

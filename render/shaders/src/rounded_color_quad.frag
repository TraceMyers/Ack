layout(location=0) in vec4  in_color;
layout(location=1) in vec2  in_uv;
layout(location=2) in vec2  in_dimensions;
layout(location=3) in float in_rounding;

layout(location=0) out vec4 out_color;

void main() {
    float corner_radius = in_rounding;
    vec2 local_pos = in_uv;

    vec2 corner_diff = max(corner_radius - local_pos, local_pos - (in_dimensions - corner_radius));
    corner_diff = max(corner_diff, 0.0);

    float corner_dist_sq   = dot(corner_diff, corner_diff);
    float corner_radius_sq = corner_radius * corner_radius;

    if (corner_dist_sq > corner_radius_sq) {
        float corner_dist = sqrt(corner_dist_sq);
        float diff = max(corner_radius - (corner_dist - 1.5), 0.0);
        out_color = vec4(in_color.rgb, in_color.a * (diff * 0.6666));
    } else {
        out_color = in_color;
    }
}

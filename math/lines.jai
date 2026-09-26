closest_point_on_each_line_segment :: (a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3, closest_pt_a: *Vector3, closest_pt_b: *Vector3) -> s: float, t: float {
    // from Real Time Collision Detection, by Christer Ericson
    a_diff          := a2 - a1;
    b_diff          := b2 - b1;
    b_to_a_diff     := a1 - b1;
    a_len_sq        := length_squared(a_diff);
    b_len_sq        := length_squared(b_diff);
    cos_t           := dot(b_diff, b_to_a_diff);

    // normalized distance along each segement where the respective closest points lie
    s, t: float = ---;

    MAX_ERROR :: VERY_SMALL_NUMBER;
    if a_len_sq <= MAX_ERROR {
        if b_len_sq <= MAX_ERROR {
            s, t = 0;
            closest_pt_a.* = a1;
            closest_pt_b.* = b1;
            return s, t;
        } else {
            s = 0;
            t = clamp(cos_t / b_len_sq, 0, 1);
        }
    } else {
        cos_p := dot(a_diff, b_to_a_diff);
        if b_len_sq <= MAX_ERROR {
            t = 0;
            s = clamp(-cos_p / a_len_sq, 0, 1);
        } else {
            // |a| |b| cos(q)
            scaled_cos_diffs := dot(a_diff, b_diff);
            // |a|^2 |b|^2 - (|a| |b| cos(q))^2 = (1 - cos(q)^2) |a|^2 |b|^2)
            denom := a_len_sq * b_len_sq - scaled_cos_diffs * scaled_cos_diffs; // book says always nonnegative

            if denom > MAX_ERROR {
                s = clamp((scaled_cos_diffs * cos_t - cos_p * b_len_sq) / denom, 0, 1);
            } else {
                // segments parallel
                // not from book; actually, everybody seems to get this wrong. both the book and some guy on stack overflow seem to think that picking an arbitrary value for s (like 0) here is fine, but this doesn't give a valuable answer in cases where the segments are non-overlapping along their parallel axis.
                // example: a1-------a2        b1--------b2
                // these two are parallel, but s should be 1 because a2 is closer to both b1 and b2
                // it's not pointless to make this distinction. i have found cases where it is important.
                b_to_a_dist_sq_1 := length_squared(a1 - b1);
                b_to_a_dist_sq_2 := length_squared(a2 - b2);    
                b_to_a_dist_sq_3 := length_squared(a1 - b2);    
                b_to_a_dist_sq_4 := length_squared(a2 - b1);
                min_dist_sq: float = ---;
                if b_to_a_dist_sq_1 < b_to_a_dist_sq_2 {
                    min_dist_sq = b_to_a_dist_sq_1;
                    s = 0;
                } else {
                    min_dist_sq = b_to_a_dist_sq_2;
                    s = 1;
                }
                if b_to_a_dist_sq_3 < min_dist_sq {
                    min_dist_sq = b_to_a_dist_sq_3;
                    s = 0;
                }
                if b_to_a_dist_sq_4 < min_dist_sq {
                    s = 1;
                }
            }

            t = (scaled_cos_diffs * s + cos_t) / b_len_sq;

            if t < 0 {
                t = 0;
                s = clamp(-cos_p / a_len_sq, 0, 1);
            } else if t > 1 {
                t = 1;
                s = clamp((scaled_cos_diffs - cos_p) / a_len_sq, 0, 1);
            }
        }
    }

    closest_pt_a.* = a1 + a_diff * s;
    closest_pt_b.* = b1 + b_diff * t;
    return s, t;
}

distance_between_line_segments :: (a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) -> float {
    closest_point_on_each_line_segment(a1, a2, b1, b2, closest_point_a, closest_point_b);
	return distance(closest_point_a.*, closest_point_b.*);
}

distance_squared_between_line_segments :: (a1: Vector3, a2: Vector3, b1: Vector3, b2: Vector3, closest_point_a: *Vector3, closest_point_b: *Vector3) -> float {
    closest_point_on_each_line_segment(a1, a2, b1, b2, closest_point_a, closest_point_b);
	return distance_squared(closest_point_a.*, closest_point_b.*);
}

line_projection_norm_dist :: inline (point: *$T, seg_beg: *T, seg_end: *T, out_toward_end: *T) -> t: float {
    out_toward_end.* = seg_end.* - seg_beg.*;
    toward_pt  := point.* - seg_beg.*;
    scaled_cos_t := dot(out_toward_end.*, toward_pt);
    segment_dist_sq := dot(out_toward_end.*, out_toward_end.*);
    return scaled_cos_t / segment_dist_sq;
}

closest_point_on_line_and_segment :: (point: Vector3, seg_beg: Vector3, seg_end: Vector3, out_point_on_line: *Vector3, out_point_on_segment: *Vector3) -> norm_dist: float {
    toward_end: Vector3 = ---;
    norm_dist := line_projection_norm_dist(*point, *seg_beg, *seg_end, *toward_end);
    out_point_on_line.* = seg_beg + toward_end * norm_dist;
    clamped_norm_dist := clamp(norm_dist, 0, 1);
    out_point_on_segment.* = seg_beg + toward_end * clamped_norm_dist;
    return norm_dist;
}

closest_point_on_line_segment :: (point: $T/VectorTypes, seg_beg: Vector3, seg_end: Vector3) -> Vector3, float {
    toward_end: Vector3 = ---;
    norm_dist := line_projection_norm_dist(*point, *seg_beg, *seg_end, *toward_end);
    clamped_norm_dist := clamp(norm_dist, 0, 1);
    return seg_beg + toward_end * clamped_norm_dist, clamped_norm_dist;
}

closest_point_on_line :: (point: $T/VectorTypes, seg_beg: T, seg_end: T) -> T, float {
    toward_end: T = ---;
    norm_dist := line_projection_norm_dist(*point, *seg_beg, *seg_end, *toward_end);
    return seg_beg + toward_end * norm_dist, norm_dist;
}

distance_from_line_segment :: inline (point: Vector3, seg_beg: Vector3, seg_end: Vector3) -> float {
    closest_point := closest_point_on_line_segment(point, seg_beg, seg_end);
    return distance(closest_point, point);
}

distance_squared_from_line_segment :: inline (point: Vector3, seg_beg: Vector3, seg_end: Vector3) -> float {
    closest_point := closest_point_on_line_segment(point, seg_beg, seg_end);
    return distance_squared(closest_point, point);
}

distance_from_line :: inline (point: Vector3, seg_beg: Vector3, seg_end: Vector3) -> float {
    closest_point := closest_point_on_line(point, seg_beg, seg_end);
    return distance(closest_point, point);
}

distance_squared_from_line :: inline (point: Vector3, seg_beg: Vector3, seg_end: Vector3) -> float {
    closest_point := closest_point_on_line(point, seg_beg, seg_end);
    return distance_squared(closest_point, point);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

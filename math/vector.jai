// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------- :Vectors

is_normalized :: (v: $V/VectorTypes, tolerance := 0.0001) -> bool {
    return abs(length_squared(v) - 1.0) < tolerance;
}

project_vector_onto_plane :: inline (vector: Vector3, plane_normal: Vector3) -> Vector3 {
    engine_check(.HIGH, is_normalized(plane_normal, SMALL_NUMBER));
    return vector - dot(vector, plane_normal) * plane_normal;
}

project_point_onto_plane :: inline (point: Vector3, point_on_plane: Vector3, plane_normal: Vector3) -> pos: Vector3, signed_dist: float {
    engine_check(.HIGH, is_normalized(plane_normal, SMALL_NUMBER));
    diff := point - point_on_plane;
    // distance along the plane normal
    signed_dist_along_normal := dot_product(plane_normal, diff);
    return point - plane_normal * signed_dist_along_normal, signed_dist_along_normal;
}

reflection_component :: inline (vector: Vector3, normal: Vector3) -> float {
    return 2.0 * dot(vector, -normal);
}

reflect :: inline (vector: Vector3, normal: Vector3) -> Vector3 {
    return vector + reflection_component(vector, normal) * normal; 
}

get_normal_and_length :: inline (v: $V/VectorTypes) -> normal: V, len: float {
    len_sq := length_squared(v);
    if len_sq <= VERY_SMALL_NUMBER {
        return {}, 0;
    }
    len := length(v);
    return v / len, len;
}

length_squared :: inline (q: Quaternion) -> float {
    return q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w;
}

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------- :Vector2 Extension

operator - :: inline (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x - scalar, a.y - scalar};
}

operator + :: inline (a: Vector2, scalar: float32) -> Vector2 {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator + :: inline (a: Vector3, scalar: float32) -> Vector3 {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------- :Vector2i

Vector2i :: struct {
    x: s32;
    y: s32;
}

operator + :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x * b.x, a.y * b.y};
}

operator / :: inline (a: Vector2i, b: Vector2i) -> Vector2i {
    return .{a.x / b.x, a.y / b.y};
}

operator + :: inline (a: Vector2i, scalar: s32) -> Vector2i #symmetric {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Vector2i, scalar: s32) -> Vector2i {
    return .{a.x - scalar, a.y - scalar};
}

operator - :: inline (scalar: s32, a: Vector2i) -> Vector2i {
    return .{scalar - a.x, scalar - a.y};
}

operator * :: inline (a: Vector2i, scalar: s32) -> Vector2i #symmetric {
    return .{a.x * scalar, a.y * scalar};
}

operator / :: inline (a: Vector2i, scalar: s32) -> Vector2i {
    return .{a.x / scalar, a.y / scalar};
}

operator / :: inline (scalar: s32, a: Vector2i) -> Vector2i {
    return .{scalar / a.x, scalar / a.y};
}

operator == :: inline (a: Vector2i, b: Vector2i) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}

to_vector2 :: inline (v: Vector2i) -> Vector2 {
    return .{xx v.x, xx v.y};
}

to_vector2i :: inline (v: Vector2) -> Vector2i {
    return .{xx v.x, xx v.y};
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------- :Vector3i

Vector3i :: struct {
    x: s32;
    y: s32;
    z: s32;

#overlay(x) xy: Vector2i = ---;
#overlay(y) yz: Vector2i = ---;
}

operator + :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x + b.x, a.y + b.y, a.z + b.z};
}

operator - :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x - b.x, a.y - b.y, a.z - b.z};
}

operator * :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x * b.x, a.y * b.y, a.z * b.z};
}

operator / :: inline (a: Vector3i, b: Vector3i) -> Vector3i {
    return .{a.x / b.x, a.y / b.y, a.z / b.z};
}

operator + :: inline (a: Vector3i, scalar: s32) -> Vector3i #symmetric {
    return .{a.x + scalar, a.y + scalar, a.z + scalar};
}

operator - :: inline (a: Vector3i, scalar: s32) -> Vector3i {
    return .{a.x - scalar, a.y - scalar, a.z - scalar};
}

operator - :: inline (scalar: s32, a: Vector3i) -> Vector3i {
    return .{scalar - a.x, scalar - a.y, scalar - a.z};
}

operator * :: inline (a: Vector3i, scalar: s32) -> Vector3i #symmetric {
    return .{a.x * scalar, a.y * scalar, a.z * scalar};
}

operator / :: inline (a: Vector3i, scalar: s32) -> Vector3i {
    return .{a.x / scalar, a.y / scalar, a.z / scalar};
}

operator / :: inline (scalar: s32, a: Vector3i) -> Vector3i {
    return .{scalar / a.x, scalar / a.y, scalar / a.z};
}

operator == :: inline (a: Vector3i, b: Vector3i) -> bool {
    return (a.x == b.x) && (a.y == b.y) && (a.z == b.z);
}

to_vector3 :: inline (v: Vector3i) -> Vector3 {
    return .{xx v.x, xx v.y, xx v.z};
}

to_vector3i :: inline (v: Vector3) -> Vector3i {
    return .{xx v.x, xx v.y, xx v.z};
}

abs :: inline (a: Vector3i) -> Vector3i {
    return .{abs(a.x), abs(a.y), abs(a.z)};
}

sum :: inline (a: Vector3i) -> s32 {
    return a.x + a.y + a.z;
}

vector :: inline (scalar: float) -> Vector3 {
    return Vector3.{scalar, scalar, scalar};
}

max :: (a: Vector3) -> float {
    return max(a.x, max(a.y, a.z));
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------- :Vector2d

Vector2d :: struct {
    x: float64;
    y: float64;
}

operator + :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x + b.x, a.y + b.y};
}

operator - :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x - b.x, a.y - b.y};
}

operator * :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x * b.x, a.y * b.y};
}

operator / :: inline (a: Vector2d, b: Vector2d) -> Vector2d {
    return .{a.x / b.x, a.y / b.y};
}

operator + :: inline (a: Vector2d, scalar: float64) -> Vector2d #symmetric {
    return .{a.x + scalar, a.y + scalar};
}

operator - :: inline (a: Vector2d, scalar: float64) -> Vector2d {
    return .{a.x - scalar, a.y - scalar};
}

operator - :: inline (scalar: float64, a: Vector2d) -> Vector2d {
    return .{scalar - a.x, scalar - a.y};
}

operator * :: inline (a: Vector2d, scalar: float64) -> Vector2d #symmetric {
    return .{a.x * scalar, a.y * scalar};
}

operator / :: inline (a: Vector2d, scalar: float64) -> Vector2d {
    return .{a.x / scalar, a.y / scalar};
}

operator / :: inline (scalar: float64, a: Vector2d) -> Vector2d {
    return .{scalar / a.x, scalar / a.y};
}

operator == :: inline (a: Vector2d, b: Vector2d) -> bool {
    return (a.x == b.x) && (a.y == b.y);
}

to_vector2 :: inline (v: Vector2d) -> Vector2 {
    return .{xx v.x, xx v.y};
}

to_vector2d :: inline (v: Vector2) -> Vector2d {
    return .{xx v.x, xx v.y};
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

Physics_Shape :: enum u8 {
    PLANE;
    CIRCLE;
    RECTANGLE;
    CYLINDER;
    BOX;
    SPHERE;
    CAPSULE;
    CONVEX;
    // raycast only
    TRIANGLE_U16;
    TRIANGLE_U32;
}

Shape_Plane :: struct {}

Shape_Circle :: struct {
    radius: float32;
}

Shape_Rectangle :: struct {
    half_height: float32;
    half_width: float32;
}

Shape_Cylinder :: struct {
    half_height: float32;
    radius: float32;
}

Shape_Box :: struct {
    half_height: float32;
    half_width: float32;
    half_length: float32;
}

Shape_Sphere :: struct {
    radius: float32;
}

Shape_Capsule :: struct {
    half_height: float32;
    radius: float32;
}

Shape_Convex :: struct {
    half_height: float32;
    data_index: s32;
}

Shape_Convex_Data :: struct {
    center: Vector3;
    points:  []Vector3;
    triangles: []u16;
}
 
Shape_Triangle_U16 :: struct {
    indices: [3]u16;
    #overlay(indices[0]) a: u16;
    #overlay(indices[1]) b: u16;
    #overlay(indices[2]) c: u16;
}

Shape_Triangle_U32 :: struct {
    indices: [3]u32;
    #overlay(indices[0]) a: u32;
    #overlay(indices[1]) b: u32;
    #overlay(indices[2]) c: u32;
}

has_extent :: inline (shape: Physics_Shape) -> bool {
    if shape == .PLANE {
        return false;
    } else return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

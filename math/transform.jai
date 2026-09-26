make_transform_matrix :: (position: Vector3, orientation: Quaternion, scale: Vector3) -> Matrix4 {
    matrix: Matrix4;
    matrix = make_translation_matrix4(position);
    matrix = rotate(matrix, orientation);
    scale_mat := make_scale_matrix4(scale);
    matrix *= scale_mat;
    return matrix;
}

decompose_transform_matrix :: (transform: *Matrix4, out_position: *Vector3, out_orientation: *Quaternion, out_scale: *Vector3) {
    out_position.* = Vector3.{transform._14, transform._24, transform._34};

    col0 := Vector3.{transform._11, transform._21, transform._31};
    col1 := Vector3.{transform._12, transform._22, transform._32};
    col2 := Vector3.{transform._13, transform._23, transform._33};

    out_scale.x = length(col0);
    out_scale.y = length(col1);
    out_scale.z = length(col2);

    right_axis := col0 / out_scale.x;
    fore_axis  := col1 / out_scale.y;
    up_axis    := col2 / out_scale.z;
    out_orientation.* = make_quat(fore_axis, right_axis, up_axis);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

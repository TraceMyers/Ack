find_farthest_point_along_axis :: (points: []Vector3, axis: Vector3) -> Vector3 {
    // todo: SIMD. have 2 sets of 3 float vectors (xyz) and two int vectors (index)
    // load them into first set of vectors like so

    // x0 x1 x2 x3
    // y0 y1 y2 y3
    // z0 z1 z2 z3
    // i0 i1 i2 i3

    // splat axis into its own set

    // xa xa xa xa
    // ya ya ya ya
    // za za za za

    // get first dot product, still parallel with indices

    // p0 p1 p2 p3
    // i0 i1 i2 i3

    // get second dot product

    // p4 p5 p6 p7
    // i4 i5 i6 i7

    // compare geq or ge across, and use that mask to create the winner
    // product and index vectors.
    // repeat with the rest
    // at the end, store into an array and just compare four values to get the final winner.

    farthest: int;
    max_distance_along_axis := -FLOAT32_MAX;

    for point : points {
        distance_along_axis := dot(point, axis);
        if distance_along_axis > max_distance_along_axis {
            farthest = it_index;
            max_distance_along_axis = distance_along_axis;
        }
    }
    return points[farthest];
}

calculate_support :: inline (points_a: []Vector3, points_b: []Vector3, axis: Vector3) -> Vector3 {
    return find_farthest_point(points_a, axis) - find_farthest_point(points_b, -axis);
}

// convex shapes must be pre-processed into world space
// (triangles array and half_height not necessary.)
gjk :: (a: Shape_Convex, b: Shape_Convex, max_iterations := 1_000) -> bool {
    axis := a.center - b.center;
    axis_len_sq := length_squared(axis);
    if axis_len_sq < VERY_SMALL_NUMBER {
        return true;
    } else {
        axis /= sqrt(axis_len_sq);
    }

    support := calculate_support(a.points, b.points, axis);

    simplex: Simplex;
    add_point(*simplex, support);

    axis = -support;

    i := 0;
    while i < max_iterations {
        defer i += 1;

        support = calculate_support(a.points, b.points, axis);

        // volumes that don't overlap along any given axis can't overlap at all
        // |<-->| air gap
        // in other words, if we start from a support and point toward the origin, the next
        // support will be on the other side of the origin if an overlap is possible,
        // because the support volume must contain the origin if there is an overlap.
        if dot(support, axis) <= 0 {
            return false;
        }

        add_point(*simplex, support);

        if narrow_search_space_toward_origin(*simplex, *axis) {
            return true;
        }
    }

    return false;
}

#scope_module

Simplex :: struct {
    points: [4]Vector3;
    point_count: s32;
    #overlay(points) line:        struct { b, a: Vector3; };
    #overlay(points) triangle:    struct { c, b, a: Vector3; };
    #overlay(points) tetrahedron: struct { d, c, b, a: Vector3; };
}

add_point :: inline (simplex: *Simplex, point: Vector3) {
    simplex.points[simplex.point_count] = point;
    simplex.point_count += 1;
}

// returns true if the tetrahedron simplex contains the origin
narrow_search_space_toward_origin :: (simplex: *Simplex, axis: *Vector3) -> bool {
    if simplex.point_count == {
    case 2;
        evaluate_support_line(simplex, axis);
    case 3;
        evaluate_support_triangle(simplex, axis);
    case 4;
        return evaluate_support_tetrahedron(simplex, axis);
    }
    return false;
}

evaluate_support_line :: inline (using simplex: *Simplex, axis: *Vector3) {
    ab :=  line.b - line.a;
    ao := -line.a;
    // triple product ((a,b),a) will be perpendicular to a, in the direction of b
    axis.* = cross(cross(ab, ao), ab); // search toward origin
}

evaluate_support_triangle :: inline (using simplex: *Simplex, axis: *Vector3) {
    ab :=  triangle.b - triangle.a;
    ac :=  triangle.c - triangle.a;
    ao := -triangle.a;

    // get plane normals pointing away from the triangle
    ab_outside_normal := cross(ab, cross(ab, ac));
    ac_outside_normal := cross(ac, cross(ac, ab));

    if dot(ao, ab_outside_normal) > 0 {
        // triangle does not contain point
        axis.* = ab_outside_normal;
        // 0 = b, 1 = a
        points[0] = triangle.b;
        points[1] = triangle.a;
        point_count = 2;
    } else if dot(ao, ac_outside_normal) > 0 {
        // triangle does not contain point
        axis.* = ac_outside_normal;
        // 0 = c, 1 = a
        points[1] = triangle.a;
        point_count = 2;
    } else {
        // triangle contains point. search in direction of triangle normal
        axis.* = cross(ab, ac);
        if dot(axis.*, ao) < 0 {
            axis.* *= -1;
        }
    }
}

evaluate_support_tetrahedron :: inline (using simplex: *Simplex, axis: *Vector3) -> bool {
    ab :=  tetrahedron.b - tetrahedron.a;
    ac :=  tetrahedron.c - tetrahedron.a;
    ad :=  tetrahedron.d - tetrahedron.a;
    ao := -tetrahedron.a;

    // todo: youtube tutorials for this don't seem to do this check. what are they seeing I'm not?
    // I came up with a paper example where this was necessary, but maybe it was wrong.
    // or maybe they just rely on a redundant shuffling of vertices through rejection.
    maybe_flip_normal := 1.0;
    abc_outside_normal := cross(ab, ac);
    if dot(abc_outside_normal, axis.*) < 0 {
        maybe_flip_normal = -1.0;
        abc_outside_normal *= maybe_flip_normal;
    }
    acd_outside_normal := cross(ac, ad) * maybe_flip_normal;
    adb_outside_normal := cross(ad, ab) * maybe_flip_normal;

    if dot(abc_outside_normal, ao) > 0 {
        point_count = 3;
        // 0 = d, 1 = c, 2 = b
        points[0] = tetrahedron.c;
        points[1] = tetrahedron.b;
        points[2] = tetrahedron.a;
        axis.* = abc_outside_normal;
        return false;
    } else if dot(acd_outside_normal, ao) > 0 {
        point_count = 3;
        // 0 = d, 1 = c, 2 = a
        points[2] = tetrahedron.a;
        axis.* = acd_outside_normal;
        return false;
    } else if dot(adb_outside_normal, ao) > 0 { 
        point_count = 3;
        // 0 = d, 1 = b, 2 = a
        points[1] = tetrahedron.b;
        points[2] = tetrahedron.a;
        axis.* = adb_outside_normal;
        return false;
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

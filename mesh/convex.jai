create_convex_mesh :: (in_mesh: *Mesh, make_indices := true) -> Mesh {
    convex: Mesh;
    // for now, only static meshes
    for in_mesh.sections {
        engine_check(.LOW, it.vertices.type == .STATIC);
    }
    create_convex_mesh_impl(in_mesh, *convex, Static_Mesh_Vertex, make_indices);
    return convex;
}

#scope_module

// trying a thing so I don't have to convexinate then triangulificate. just do both
// at once. 
create_convex_mesh_impl :: (in_mesh: *Mesh, convex: *Mesh, $vertex_type: Type, make_indices: bool) {
    greatest_triangle_count: int;
    new_indices := make_dynamic_array([..]u32, in_mesh.sections.count,, temp);

    for *new_indices {
        it.allocator = temp;
        index_count := in_mesh.sections[it_index].indices.count;
        array_reserve(it, xx index_count);
        greatest_triangle_count = max(greatest_triangle_count, index_count);
    }
    greatest_triangle_count /= 3;

    triangle_searched := make_bit_array(greatest_triangle_count,, temp);
    triangle_removed  := make_bit_array(greatest_triangle_count,, temp);
    tri_neighbors     := make_static_array([3]u32, greatest_triangle_count,, temp);

    edges: Table(u64, [2]u32, LOAD_FACTOR_PERCENT=80);
    init(*edges, xx ceil(cast(float) greatest_triangle_count * 101.0 / 80.0),, temp);

    for section, si : in_mesh.sections {
        #if vertex_type == Skeletal_Mesh_Vertex {
            vertices := section.vertices.skinned;
        } else {
            vertices := section.vertices.static;
        }
        engine_check(.MEDIUM, vertices.count == section.vertices.count);

        if si != 0 {
            clear_all_bits(*triangle_searched);
            clear_all_bits(*triangle_removed);
            table_reset(*edges);
        }
        memset(tri_neighbors.data, 0xff, size_of(type_of(tri_neighbors[0])) * tri_neighbors.count);

        section_triangle_count := section.indices.count / 3;
        for i : 0..section_triangle_count - 1 {
            a := i * 3; 
            ai := get_tri_vert_index(*section.indices, a + 0);
            bi := get_tri_vert_index(*section.indices, a + 1);
            ci := get_tri_vert_index(*section.indices, a + 2);
            ai, bi, ci = get_ascending_tri(ai, bi, ci);
            try_meet_neighbor(i, 0, ai, bi);
            try_meet_neighbor(i, 1, bi, ci);
            try_meet_neighbor(i, 2, ci, ai);
        }

        new_index_array := *new_indices[si];
        search_origin := 0;

        while true {
            origin_begin := search_origin * 3;
            neighbors := *tri_neighbors[search_origin];

            origin, neighbor_ab, neighbor_bc, neighbor_ca: Triangle = ---;
            get_triangle(*origin, search_origin, *section.indices, vertices);
            get_triangle(*neighbor_ab, neighbors.*[0], *section.indices, vertices);
            get_triangle(*neighbor_bc, neighbors.*[1], *section.indices, vertices);
            get_triangle(*neighbor_ca, neighbors.*[2], *section.indices, vertices);

            // todo: after alteration, need to check neighbor's neighbors
            neighbor: *Triangle;
            edge: int;

            if dot(origin.normal, neighbor_ab.normal) < 0 {
                neighbor = *neighbor_ab;
                edge = 0;
            } else if dot(origin.normal, neighbor_bc.normal) < 0 {
                neighbor = *neighbor_bc;
                edge = 1;
            } else if dot(origin.normal, neighbor_ca.normal) < 0 {
                neighbor = *neighbor_ca;
                edge = 2;
            } else {
                triangle_searched[search_origin] = true;
                search_origin = -1;
                for :only_cleared_bits triangle_searched {
                    search_origin = it_index;
                }
                if search_origin == -1 {
                    break;
                }
            }

            neighbor_index := tri_neighbors[search_origin][edge];
            neighbor_edge  := -1;

            if tri_neighbors[neighbor_index][0] == search_origin {
                neighbor_edge = 0;
            } else if tri_neighbors[neighbor_index][1] == search_origin {
                neighbor_edge = 1;
            } else if tri_neighbors[neighbor_index][2] == search_origin {
                neighbor_edge = 2;
            } else {
                engine_check(.LOW, false, "invalid neighbor");
            }

            bridge_vert          := decrement_wrap(edge, 0, 2);
            neighbor_bridge_vert := decrement_wrap(neighbor_edge, 0, 2);
            
            // can vertex order of new triangles be determined without calculation?
            // I think so.
            // next time on this thing da dad daaa
        }
    }
}

get_tri_vert_index :: (indices: *Mesh_Index_Buffer, i: int) -> u32 #expand {
    if indices.type == .U16 {
        return indices._u16[i];
    } else {
        return indices._u32[i];
    }
}

pack_indices :: (a: u32, b: u32) -> u64 #expand {
    return xx ((cast(u64) a) << 32) | cast(u64) b;
}

unpack_indices :: inline (a: u64) -> u32, u32 #expand {
    return xx (a >> 32), xx,trunc (a);
}

get_ascending_tri :: (a: u32, b: u32, c: u32) -> u32, u32, u32 #expand {
    if a < b {
        if b < c { 
            return a, b, c;
        } else if c < a {
            return c, a, b;
        } else {
            return a, c, b;
        }
    } else if c < a {
        if b < c {
            return b, c, a;
        } else {
            return c, b, a;
        }
    } else { 
        return b, a, c;
    }
}

try_meet_neighbor :: (this_tri: int, this_edge: int, edge_a: u32, edge_b: u32) #expand {
    ab := pack_indices(edge_a, edge_b);
    ab_edge := table_find_pointer(*`edges, ab);

    if ab_edge == null {
        table_set(*`edges, ab, .[cast(u32) this_tri, cast(u32) this_edge]);
    } else {
        neighbor_tri  := ab_edge.*[0];
        neighbor_edge := ab_edge.*[1];
        `tri_neighbors[this_tri]    [this_edge]     = xx neighbor_tri;
        `tri_neighbors[neighbor_tri][neighbor_edge] = xx this_tri;
    }
}

get_triangle :: inline (using tri: *Triangle, i: int, indices: *Mesh_Index_Buffer, vertices: []$vertex_type) {
    a = get_tri_vert_index(indices, i + 0);
    b = get_tri_vert_index(indices, i + 1);
    c = get_tri_vert_index(indices, i + 2);

    av := *vertices[a].position;
    bv := *vertices[b].position;
    cv := *vertices[c].position;

    ab := bv.* - av.*;
    ac := cv.* - av.*;

    // not normalized! don't need it
    normal = cross(ac, ab);
}

calc_ascending :: inline (using tri: *Triangle) {
    ascending.a, ascending.b, ascending.c = get_ascending_tri(array_order.a, array_order.b, array_order.c);
}

Triangle :: struct {
    array: [3]u32;
    normal: Vector3; // not normalized

    #overlay(array[0]) a: u32;
    #overlay(array[1]) b: u32;
    #overlay(array[2]) c: u32;
}

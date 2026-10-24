// turns the frame's line draws into vertices in host visible memory, batched by layer and width
// (line width is pipeline state, so each width needs its own draw).

// mirrored by Line_Vertex in shaders/src/header.glsl
Line_Vertex :: struct {
    position: Vector3;
    color:    Color4f;
}

Line_Draws :: struct {
    vertices: GPU_Buffer; // Line_Vertex, two per line
    batches:  [..]Line_Batch;
}

Line_Batch :: struct {
    layer:        Draw_Layer;
    width:        float;
    first_vertex: u32;
    vertex_count: u32;
}

prepare_line_draws :: (frame: *GPU_Frame) -> Line_Draws {
    using engine.renderer;
    line_draws: Line_Draws;
    line_draws.batches.allocator = temp;

    line_count := draws.lines.count + draws.timed_lines.count;
    if line_count == 0 {
        return line_draws;
    }

    lines := NewArray(line_count, Line_Draw,, temp);
    memcpy(lines.data, draws.lines.data, draws.lines.count * size_of(Line_Draw));
    for draws.timed_lines {
        lines[draws.lines.count + it_index] = it.draw;
    }
    // layers first, then width. widths are small, so this keeps layers apart.
    quick_sort(lines, line => cast(float64) line.layer * 1_000_000 + line.width);

    line_draws.vertices = create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, line_count * 2 * size_of(Line_Vertex), .STORAGE_BUFFER_BIT);
    vertices := cast(*Line_Vertex) gpu_mapped(line_draws.vertices);

    batch: *Line_Batch;
    for lines {
        if batch == null || batch.layer != it.layer || batch.width != it.width {
            batch = array_add(*line_draws.batches);
            batch.* = .{layer = it.layer, width = it.width, first_vertex = xx (it_index * 2)};
        }
        color := to_color4f(it.color);
        vertices[it_index * 2]     = .{it.a, color};
        vertices[it_index * 2 + 1] = .{it.b, color};
        batch.vertex_count += 2;
    }

    return line_draws;
}

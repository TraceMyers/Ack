Quad_Vertex :: struct {
    position: Vector2;
    dimensions: Vector2;
    uv: Vector2;
    color: Color4f;
    rounding: float32;
}

prepare_quad_draws :: (frame: *GPU_Frame) -> vertices: GPU_Buffer, vertex_count: int {
    using engine.renderer;

    if draws.quads.count == 0 {
        return {}, 0;
    }

    size := draws.quads.count * size_of(Quad_Vertex);
    buffer := create_gpu_buffer(frame.temp_allocator, .HOST_VISIBLE_BUFFER, size, .STORAGE_BUFFER_BIT);

    vertices := cast(*Quad_Vertex) gpu_mapped(buffer);
    memcpy(vertices, draws.quads.data, size);

    return buffer, draws.quads.count;
}

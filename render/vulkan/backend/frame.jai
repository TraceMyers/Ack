#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

GPU_Frame :: struct {
    temp_allocators: [GPU_HEAP_TYPE_COUNT]GPU_Linear_Allocator;
}

get_current_frame :: () -> *GPU_Frame {
    return *frames[frame_index];
}

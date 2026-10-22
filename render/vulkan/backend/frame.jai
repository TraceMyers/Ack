#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

GPU_Frame :: struct {
    command_pool:               VkCommandPool;
    command_buffer:             VkCommandBuffer;

    image_available_semaphore:  VkSemaphore;
    render_fence:               VkFence;
    present_fence:              VkFence;

    temp_allocators: [GPU_HEAP_TYPE_COUNT]GPU_Linear_Allocator;

    // ...
}

get_current_frame :: () -> frame: *GPU_Frame, index: int {
    index := cast(int) (rendered_frame_count % xx frames.count);
    return *frames[index], index;
}

create_frames :: () -> bool {
    return true;
}

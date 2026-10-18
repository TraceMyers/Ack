render_check :: inline (result: VkResult, fmt := "", args: ..Any, $level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) #no_debug #expand {
    render_check(result == .SUCCESS, fmt, ..args, level=level, caller_loc=caller_loc);
}

render_evaluate :: inline (result: VkResult, fmt := "", args: ..Any, level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) -> bool #expand #no_debug {
    return render_evaluate(result == .SUCCESS, fmt, ..args, level=level, caller_loc=caller_loc);
}

#import "Ack!/render/vulkan-jai";

#load "frontend/frontend.jai";
#load "frontend/init.jai";
#load "frontend/per_frame_update.jai";
#load "frontend/physical_device.jai";
#load "frontend/system.jai";

#scope_module

#load "backend/backend.jai";
#load "backend/create_renderer.jai";
#load "backend/gpu_allocation.jai";
#load "backend/gpu_linear_allocator.jai";
#load "backend/physical_device.jai";
#load "backend/pipelines.jai";
#load "backend/swapchain.jai";
#load "backend/getters.jai";
#load "backend/frame.jai";

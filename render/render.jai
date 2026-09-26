TeRM_Render_Version :: struct {
    MAJOR :: 0;
    MINOR :: 1;
}

#if GRAPHICS_API == {
case "VULKAN";
    #load "vulkan_frontend/vulkan_frontend.jai";
}

ack_renderer_path :: () -> string {
    return get_final_path(#filepath,, temp);
}

#scope_module

render_target_width: u32;
render_target_height: u32;
should_recreate_swapchain: bool;

scope_set_renderer :: (in_renderer: *Renderer) #expand {
    context.renderer = in_renderer;
    `prev_renderer := context.renderer;
    `defer context.renderer = prev_renderer;
}

NANOSECONDS_PER_SECOND      :: 1_000_000_000;
NANOSECONDS_PER_MILLISECOND :: 1_000_000;

run_init_proc :: (proc: Code, caller_loc := #caller_location) #expand {
    proc_name :: #run code_string(proc);
    render_log(.HIGH, "calling %", proc_name);
    if !context.renderer.init_success {
        return;
    }
    #insert #run tprint("context.renderer.init_success = `%();", proc_name);
    if !context.renderer.init_success {
        render_log(.HIGH, "init failure. exiting.", caller_loc=caller_loc);
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

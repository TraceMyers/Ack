
// Renderer_Creation_Settings :: struct {
//     config: Renderer_Config;

//     application_name    := "your graphics application";
//     application_version := Version.{0, 1, 0};
//     engine_name         := "Ack!";
//     engine_version      := ACK_VERSION;

//     max_textures               : u32 = 4096;
//     max_gpu_heaps              : u32 = 512;
//     max_materials              : u32 = 4096;
//     max_static_mesh_instances  : u32 = 32_768;
//     max_skinned_mesh_instances : u32 = 16_384;

//     copy_shaders_into_working_directory := true;
//     use_dev_gui                         := true;
// }

backend_create_renderer :: (using renderer: *Renderer, settings: Renderer_Creation_Settings) -> bool {
    auto_release_temp();

    vram_size: int;
    if physical_device.size <= 0 {
        vram_size = 2 * 1024 * 1024 * 1024;
    } else {
        vram_size = physical_device.size;
    }
    max_gpu_heaps := (vram_size / backend.DEFAULT_GPU_HEAP_SIZE) - 2;
    
    // todo: figure out minimum number of heaps to do anything
    MINIMUM_GPU_HEAPS :: 8;
    if render_evaluate(max_gpu_heaps < MINIMUM_GPU_HEAPS) {
        render_error("num possible heaps with vram size % is %. minimum = %.", vram_size, max_gpu_heaps, MINIMUM_GPU_HEAPS);
        return false;
    }

    pool_init(*backend.gpu_heaps, max_gpu_heaps,                   true);
    pool_init(*backend.textures,  creation_settings.max_textures,  true);
    pool_init(*backend.materials, creation_settings.max_materials, true);

    run_init_proc :: (proc: Code, caller_loc := #caller_location) #expand {
        proc_name :: #run code_string(proc);
        if !backend.init_success {
            return;
        }
        render_log("calling %", proc_name, flags=.VERBOSE_ONLY);
        #insert #run tprint("backend.init_success = `%();", proc_name);
        if !backend.init_success {
            render_log("vulkan backend init failure.", loc=caller_loc, flags=.VERBOSE_ONLY);
        }
    }

    backend.init_success = true; 
    
    run_init_proc(create_vk_instance);
    run_init_proc(create_surface);
    run_init_proc(select_physical_device);
    run_init_proc(create_logical_device);
    run_init_proc(initialize_allocators);
    run_init_proc(create_swapchain_and_attachments);
    run_init_proc(create_frame_datas);
    run_init_proc(create_default_descriptors);
    run_init_proc(create_descriptors);
    run_init_proc(create_default_pipelines);

    return backend.init_success;
}

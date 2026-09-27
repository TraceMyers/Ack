// initialize your first (and maybe only) renderer
init_first_renderer :: (first_renderer: *Renderer, options: Render_Init_Options, render_width: u32, render_height: u32) -> bool {
    render_target_width = render_width;
    render_target_height = render_height;
    first_renderer.max_texture_count = options.max_texture_count;

    success := init_renderer_shared_data(first_renderer, options);
    if !success then return false;

    success = init_renderer_unique_data(first_renderer);
    if !success then return false;

    if options.initialize_dev_gui {
        init_dev_gui(first_renderer);
    }

    return true;
}

// if you are doing the multithreading + one renderer per thread style,
// pass subsequent renderers in here to initialize them.
// as in:
// init_first_renderer(renderer_0);
// init_subsequent_renderer(renderer_1, renderer_0);
// init_subsequent_renderer(renderer_2, renderer_0);
// ...
init_subsequent_renderer :: (subsequent_renderer: *Renderer, first_renderer: *Renderer) -> bool {
    subsequent_renderer.shared_data = first_renderer.shared_data;
    return init_renderer_unique_data(subsequent_renderer);
}

// helper proc for initialization, use it instead if you like.
// initializes the section of data in a renderer that is shared among renderers, if 
// you are doing the multithreading + one renderer per thread style
init_renderer_shared_data :: (thread_local_renderer: *Renderer, options: Render_Init_Options) -> bool {
    // context values are thread-local. this functions as a way to have a global
    // value that is also safe to reassign on any given thread, as no thread can remove or
    // swap out any other thread's renderer. so, using one renderer per thread (but still sharing 
    // vk instance and etc.) might be a good design to reduce the mental overhead of multithreading.
    scope_set_renderer(thread_local_renderer);
    using context.renderer;
    auto_release_temp();

    init_success = true;

    render_log(.MEDIUM,
#string HERE
initializing renderer for application...

    %, version %
    made with %, version %
    using % graphics, version %
HERE,
        application_name, 
        renderer_version_string(application_version),
        ifx engine_name == "" then "?" else engine_name, 
        renderer_version_string(engine_version),
        API,
        renderer_version_string(API_VERSION)
    );

    if options.populate_shader_data_in_working_directory {
        if !populate_shader_data() then return false;
    }

    pool_init(*gpu_heap_pool, MAX_GPU_HEAPS,     true);
    pool_init(*image_pool,    max_texture_count, true);
    pool_init(*materials,     MAX_MATERIALS,     true);

    array_reserve(*meshes, MAX_UNIQUE_MESHES);
    meshes.allocator = no_allocator;
    
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

    return init_success;
}

// helper proc for initialization, use it instead if you like.
// initializes the section of data in a renderer that is unique to each renderer, if 
// you are doing the multithreading + one renderer per thread style
init_renderer_unique_data :: (thread_local_renderer: *Renderer) -> bool {
    scope_set_renderer(thread_local_renderer);
    using context.renderer;
    auto_release_temp();

    return true;
}

#scope_file

// copies the shader source code and compile_shaders.jai file from this module into the user's project
// directory, creates a folder for compiled spirv, and runs a compile script so the shader
// data is ready for loading later. this really only needs to run once assuming no more shaders
// are added to the module, but behavior is on by default because it populates important data 
// without the user having to think about it. once finished, tells the user how to 
// turn the option off.
//
// the reason shader source and etc are copied into the project directory: because having
// your shaders all in one place is probably what most people want. 
//
// todo: you should be able to decide where in your project the shader directory goes. you
// can technically do that right now by setting your working directory before renderer init.
//
// todo: packaging = this needs to turn off 100%
populate_shader_data :: () -> bool {
    working_directory := get_working_directory();
    defer set_working_directory(working_directory);

    final_filepath := get_final_path(#filepath,, temp);

    dst_path := parse_path_ext(working_directory);
    src_path := parse_path_ext(final_filepath);

    move_up_directory(*src_path);
    move_down_directory(*src_path, "vulkan_shaders");
    term_shaders_path := path_to_string_ext(*src_path);

    fully_exists, _ := how_much_of_path_exists_on_the_local_filesystem(src_path);

    spiel := "render init options have 'populate_shader_data_in_working_directory' set to true";

    if !fully_exists {
        render_warning(.MEDIUM, "%, but the TeRM/Render structure is unable to find path to copy shaders from. expected path is one TeRM_Render/vulkan_shaders. shaders path: %", spiel, term_shaders_path);
        return false;
    }

    move_down_directory(*dst_path, "shaders");
    project_shaders_path := path_to_string_ext(*dst_path);
    copy_success := copy_directory(term_shaders_path, project_shaders_path,, temp);

    if !copy_success {
        render_warning(.MEDIUM, "%, but the copy failed for an unknown reason. this can either be investigated at the system level or it might just be easier to copy by hand from the % to %.", spiel, term_shaders_path, project_shaders_path);
        return false;
    } 

    move_down_directory(*dst_path, "spirv");
    spirv_path := path_to_string_ext(*dst_path);
    make_directory_if_it_does_not_exist(spirv_path);
    fully_exists, _ = how_much_of_path_exists_on_the_local_filesystem(dst_path);

    if !fully_exists {
        render_warning(.MEDIUM, "tried to create directory for shader compilation spirv output at %, but failed", spirv_path);
        return false;
    }

    set_working_directory(project_shaders_path);

    // assumes jai compiler is in your environment variables, used for shader compilation
    #if RENDER_VALIDATION_LEVEL < Ack_Validation_Level.MEDIUM {
        result := run_command("jai", "compile_shaders.jai", "-", "no-log");
    } else {
        result := run_command("jai", "compile_shaders.jai");
    }

    if result.exit_code != 0 {
        render_warning(.MEDIUM, "tried to compile shaders in % using the compile.bat in there, but failed with exit code %", dst_path, result.exit_code);
        return false;
    }
    render_log(.MEDIUM, "%, so the default shader datas were copied from % to % and the shaders were compiled. this is on by default for ease of use, but it can be turned off now.", spiel, term_shaders_path, project_shaders_path);
    return true;
}

init_dev_gui :: (using renderer: *Renderer) {
    pool_sizes := VkDescriptorPoolSize.[
        .{.SAMPLER,                   1000},
        .{.COMBINED_IMAGE_SAMPLER,    1000},
        .{.SAMPLED_IMAGE,             1000},
        .{.STORAGE_IMAGE,             1000},
        .{.UNIFORM_TEXEL_BUFFER,      1000},
        .{.STORAGE_TEXEL_BUFFER,      1000},
        .{.UNIFORM_BUFFER,            1000},
        .{.STORAGE_BUFFER,            1000},
        .{.UNIFORM_BUFFER_DYNAMIC,    1000},
        .{.STORAGE_BUFFER_DYNAMIC,    1000},
        .{.INPUT_ATTACHMENT,          1000}
    ];

    pool_info := VkDescriptorPoolCreateInfo.{
        flags = .FREE_DESCRIPTOR_SET_BIT,
        maxSets = 1000,
        poolSizeCount = xx pool_sizes.count,
        pPoolSizes = pool_sizes.data
    };

    render_evaluate(.LOW, vkCreateDescriptorPool(logical.obj, *pool_info, null, *imgui_descriptor_pool) == .SUCCESS, "failed to create the descriptor pool for imgui");

    imgui_context = ImGui.CreateContext();

    dev_gui_init_fonts();
    dev_gui_set_theme_paper_and_ink();

    render_evaluate(.LOW, ImGui.ImplWin32_Init(window), "failed to initialize imgui win32 implementation");

    init_info := ImGui.ImplVulkan_InitInfo.{
        ApiVersion = API_VERSION,
        Instance = vk_instance,  
        PhysicalDevice = physical.obj,
        Device = logical.obj,
        Queue = graphics_queue,
        DescriptorPool = imgui_descriptor_pool,
        MinImageCount = 3,
        ImageCount = 3,
        UseDynamicRendering = true,
        PipelineRenderingCreateInfo = .{
            colorAttachmentCount    = 1,
            pColorAttachmentFormats = *swapchain.format.format,
            depthAttachmentFormat   = depth_buffer.format,
            stencilAttachmentFormat = depth_buffer.format
        },
        MSAASamples=xx msaa_samples
    };

    render_evaluate(.LOW, ImGui.ImplVulkan_Init(*init_info), "failed to initialize imgui vulkan implementation");
    render_evaluate(.LOW, ImGui.ImplVulkan_CreateFontsTexture(), "failed to create the fonts texture for imgui-vulkan");
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

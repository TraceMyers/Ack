backend_create_renderer :: () -> bool {
    using engine.renderer;
    auto_release_temp();

    run_and_return_if_failure :: (proc: Code, caller_loc := #caller_location) #expand {
        proc_name :: #run code_string(proc);
        render_log("calling %", proc_name, flags=.VERBOSE_ONLY);
        #insert #run tprint("backend.init_success = %();", proc_name);
        if !render_evaluate(backend.init_success, "failed on stage %", proc_name) {
            `return false;
        }
    }

    backend.init_success = true; 
    
    run_and_return_if_failure(create_vk_instance);
    run_and_return_if_failure(create_surface);
    run_and_return_if_failure(select_physical_device);

    // once physical device is gotten, we know how much local vram we have, so we can prepare
    // for allocating vram and other things.
    vram_size: int;
    if backend.physical_device.size <= 0 {
        vram_size = 2 * 1024 * 1024 * 1024;
    } else {
        vram_size = xx backend.physical_device.size;
    }
    max_gpu_heaps := (vram_size / backend.DEFAULT_GPU_HEAP_SIZE) - 2;
    
    // todo: figure out minimum number of heaps for renderer to function
    MINIMUM_GPU_HEAPS :: 8;
    if max_gpu_heaps < MINIMUM_GPU_HEAPS {
        render_error("num possible heaps with vram size % is %. minimum = %.", vram_size, max_gpu_heaps, MINIMUM_GPU_HEAPS);
        return false;
    }

    pool_init(*backend.gpu_heaps, max_gpu_heaps, true);
    pool_init(*backend.textures,  creation_settings.max_textures,  true);
    pool_init(*backend.materials, creation_settings.max_materials, true);

    run_and_return_if_failure(create_logical_device);
    run_and_return_if_failure(initialize_linear_allocators);
    // run_and_return_if_failure(create_swapchain_and_attachments);
    // run_and_return_if_failure(create_frame_datas);
    // run_and_return_if_failure(create_default_descriptors);
    // run_and_return_if_failure(create_descriptors);
    // run_and_return_if_failure(create_default_pipelines);

    return true;
}

// todo: figure out how to make this not take 1,000,000,000 years.
// seems it's mostly vkCreateInstance()
create_vk_instance :: () -> bool {
    using engine.renderer;
    auto_release_temp();
    
    if !render_evaluate(instance_extensions_are_supported(required_instance_extensions), "required instance extensions unsupported") then return false;

    if !render_evaluate(instance_layers_are_supported(required_layers), "required instance layers unsupported") then return false;

    app_info := VkApplicationInfo.{
        pApplicationName    = temp_c_string(creation_settings.application_name),
        applicationVersion  = to_vulkan_version(creation_settings.application_version),
        pEngineName         = temp_c_string(creation_settings.engine_name),
        engineVersion       = to_vulkan_version(creation_settings.engine_version),
        apiVersion          = backend.API_VERSION
    };
    create_info := VkInstanceCreateInfo.{
        pApplicationInfo = *app_info,
     enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = required_layers.data,
        enabledExtensionCount = xx required_instance_extensions.count,
        ppEnabledExtensionNames = required_instance_extensions.data
    };

    if !render_evaluate(vkCreateInstance(*create_info, null, *backend.vk_instance), "failed to create vulkan instance") then return false;

    render_log("created vk instance", flags=.VERBOSE_ONLY);
    return true;
}

instance_extensions_are_supported :: (extensions: []*u8) -> bool {
    auto_release_temp();

    available_extensions, result := vkEnumerateInstanceExtensionProperties(null,,temp);
    if !render_evaluate(result, "failed to enumerate instance extension properties") then return false;

    for need_ext : extensions {
        ext_found: bool;
        for have_ext : available_extensions {
            max_read_ct := have_ext.extensionName.count;
            if c_strings_equal(need_ext, have_ext.extensionName.data, max_read_ct) {
                ext_found = true;
                break;
            }
        }
        if !ext_found {
            return false;
        }
    }

    return true;
}

instance_layers_are_supported :: (layers: []*u8) -> bool {
    auto_release_temp();
    
    available_layers, result := vkEnumerateInstanceLayerProperties(,,temp);
    if !render_evaluate(result, "failed to enumerate instance instance layer properties") then return false;

    for need_layer : layers {
        layer_found: bool;
        for have_layer : available_layers {
            max_read_ct := have_layer.layerName.count;
            if c_strings_equal(need_layer, have_layer.layerName.data, max_read_ct) {
                layer_found = true;
                break;
            }
        }
        if !layer_found {
            render_log("unable to find layer % in available layers", to_string(need_layer));
            return false;
        }
    }

    return true;
}

create_surface :: () -> bool {
    using engine.renderer.backend;

    #if OS == .WINDOWS {
        create_info := VkWin32SurfaceCreateInfoKHR.{
            hwnd = window,
            hinstance = Win32.GetModuleHandleW(null)
        };
        if !render_evaluate(vkCreateWin32SurfaceKHR(vk_instance, *create_info, null, *surface), "failed to create surface") then return false;
    } else {
        return false;
    }

    render_log("created surface from window", flags=.VERBOSE_ONLY);
    return true;
}

create_logical_device :: () -> bool {
    using engine.renderer.backend;
    auto_release_temp();

    queue_priority : float32 = 1.0;
    unique_queue_family_indices := temp_get_unique_queue_family_indices(*physical_device);
    queue_create_infos := make_dynamic_array(VkDeviceQueueCreateInfo, 4,, temp);

    for unique_queue_family_indices {
        array_add(*queue_create_infos, {
            queueFamilyIndex = it,
            queueCount = 1,
            pQueuePriorities = *queue_priority,
        });
    }

    enable_device_features := VkPhysicalDeviceFeatures.{
        fillModeNonSolid = VK_TRUE,
        wideLines = VK_TRUE,
        multiDrawIndirect = VK_TRUE,
    };

    vulkan_1_2_features := VkPhysicalDeviceVulkan12Features.{
        // optionally pack structures in glsl in a c-like fashion, with largest number primitive alignment
        scalarBlockLayout = VK_TRUE,
        // refer to a set of descriptors as a runtime-length array in shader
        descriptorBindingPartiallyBound = VK_TRUE,
        runtimeDescriptorArray = VK_TRUE,
        shaderSampledImageArrayNonUniformIndexing = VK_TRUE,
        descriptorBindingVariableDescriptorCount = VK_TRUE,
    };

    // as far as I know, this is just for being able to use gl_DrawID in shaders for indexing by draw.
    draw_params_enable := VkPhysicalDeviceShaderDrawParametersFeatures.{
        shaderDrawParameters = VK_TRUE,
        pNext = *vulkan_1_2_features
    };

    // smooths over a bunch of unnecessary boilerplate in creating graphics pipeline-related stuff
    dynamic_rendering_enable := VkPhysicalDeviceDynamicRenderingFeatures.{
        dynamicRendering = VK_TRUE,
        pNext = *draw_params_enable
    };

    // enables syncing a fence on present
    maintenance1_enable := VkPhysicalDeviceSwapchainMaintenance1FeaturesEXT.{
        swapchainMaintenance1 = VK_TRUE,
        pNext = *dynamic_rendering_enable,
    };

    sync_feature_enable := VkPhysicalDeviceSynchronization2Features.{
        synchronization2 = VK_TRUE,
        pNext = *maintenance1_enable
    };

    device_create_info := VkDeviceCreateInfo.{
        pQueueCreateInfos = queue_create_infos.data,
        queueCreateInfoCount = xx queue_create_infos.count,
        pEnabledFeatures = *enable_device_features,
        enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = xx required_layers.data,
        enabledExtensionCount = xx required_device_extensions.count,
        ppEnabledExtensionNames = required_device_extensions.data,
        pNext = *sync_feature_enable
    };

    result := vkCreateDevice(physical_device.obj, *device_create_info, null, *logical_device.obj);
    if !render_evaluate(result, "failed to create the logical device") return false;

    vkGetDeviceQueue(logical_device.obj, xx physical_device.queue_family_indices.graphics_index, 0, *graphics_queue);
    vkGetDeviceQueue(logical_device.obj, xx physical_device.queue_family_indices.transfer_index, 0, *transfer_queue);

    render_log("created logical device", flags=.VERBOSE_ONLY);
    return true;
}

#if RENDER_VALIDATION_LEVEL >= .HIGH {
    required_layers := (*u8).[
        "VK_LAYER_KHRONOS_validation",
    ];
} else {
    required_layers := (*u8).[];
}

#if OS == .WINDOWS {
    required_instance_extensions := (*u8).[
        "VK_KHR_surface",
        "VK_KHR_win32_surface",
        "VK_KHR_get_surface_capabilities2",
        "VK_EXT_surface_maintenance1",
    ];
} else {
    required_instance_extensions := (*u8).[
        "VK_KHR_surface",
        "VK_KHR_get_surface_capabilities2",
        "VK_EXT_surface_maintenance1",
    ];
}

// todo: revisit which of these are needed and which are core
required_device_extensions := (*u8).[
    "VK_KHR_swapchain",
    "VK_EXT_swapchain_maintenance1",
    "VK_KHR_buffer_device_address",
    "VK_KHR_dynamic_rendering",
    "VK_EXT_scalar_block_layout"
];

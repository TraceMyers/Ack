backend_create_renderer :: () -> bool {
    using engine.renderer;
    auto_release_temp();

    pool_init(*materials, creation_settings.max_materials, true);

    bcr_try :: #bake_arguments engine_run_or_return_failure(log_proc=render_log, fail_log_proc=render_error, flags=.VERBOSE_ONLY);

    init_success = false;

    bcr_try(create_vk_instance());
    bcr_try(create_surface());
    bcr_try(select_physical_device());
    bcr_try(create_logical_device());
    bcr_try(initialize_allocators());
    bcr_try(create_swapchain_and_attachments());
    bcr_try(create_frames());
    bcr_try(create_upload_state());
    bcr_try(create_texture_descriptors());
    bcr_try(create_materials_buffer());
    bcr_try(create_pipelines());

    init_success = true;

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
        apiVersion          = API_VERSION
    };
    create_info := VkInstanceCreateInfo.{
        pApplicationInfo = *app_info,
     enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = required_layers.data,
        enabledExtensionCount = xx required_instance_extensions.count,
        ppEnabledExtensionNames = required_instance_extensions.data
    };

    if !render_evaluate(vkCreateInstance(*create_info, null, *vk_instance), "failed to create vulkan instance") then return false;

    render_log("created vk instance", flags=.VERBOSE_ONLY);
    return true;
}

instance_extensions_are_supported :: (extensions: []*u8) -> bool {
    using engine.renderer;
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
    using engine.renderer;
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
    using engine.renderer;
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
    using engine.renderer;
    auto_release_temp();

    queue_priority := 1.0;
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
        // instance data is indexed by gl_InstanceIndex, which starts at the draw's firstInstance
        drawIndirectFirstInstance = VK_TRUE,
        // 64-bit buffer addresses in shaders
        shaderInt64 = VK_TRUE,
    };

    vulkan_1_2_features := VkPhysicalDeviceVulkan12Features.{
        // optionally pack structures in glsl in a c-like fashion, with largest number primitive alignment
        scalarBlockLayout = VK_TRUE,
        // refer to a set of descriptors as a runtime-length array in shader
        descriptorBindingPartiallyBound = VK_TRUE,
        runtimeDescriptorArray = VK_TRUE,
        shaderSampledImageArrayNonUniformIndexing = VK_TRUE,
        descriptorBindingVariableDescriptorCount = VK_TRUE,
        // textures can be registered while frames that use the texture array are in flight
        descriptorBindingSampledImageUpdateAfterBind = VK_TRUE,
        descriptorBindingUpdateUnusedWhilePending = VK_TRUE,
        // shaders reach buffers through pointers instead of descriptors
        bufferDeviceAddress = VK_TRUE,
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

    sync_feature_enable := VkPhysicalDeviceSynchronization2Features.{
        synchronization2 = VK_TRUE,
        pNext = *dynamic_rendering_enable
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
    ];
} else {
    required_instance_extensions := (*u8).[
        "VK_KHR_surface",
        "VK_KHR_get_surface_capabilities2",
    ];
}

// todo: revisit which of these are needed and which are core
required_device_extensions := (*u8).[
    "VK_KHR_swapchain",
    "VK_KHR_dynamic_rendering",
    "VK_EXT_scalar_block_layout"
];

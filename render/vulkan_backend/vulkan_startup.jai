// todo: texture deduplication/sharing

// --- sections ---
// vk instance
// surface
// physical device
// logical device
// frame data
// descriptors

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------------- :vk instance

// todo: figure out how to make this not take 1,000,000,000 years.
// seems it's mostly vkCreateInstance()
create_vk_instance :: () -> bool {
    using context.renderer;
    auto_release_temp();
    
    if !render_evaluate(.LOW, instance_extensions_are_supported(required_instance_extensions), "required instance extensions unsupported") then return false;

    if !render_evaluate(.LOW, instance_layers_are_supported(required_layers), "required instance layers unsupported") then return false;

    app_info := VkApplicationInfo.{
        pApplicationName    = temp_c_string(application_name),
        applicationVersion  = application_version,
        pEngineName         = temp_c_string(engine_name),
        engineVersion       = engine_version,
        apiVersion          = API_VERSION
    };
    create_info := VkInstanceCreateInfo.{
        pApplicationInfo = *app_info,
     enabledLayerCount = xx required_layers.count,
        ppEnabledLayerNames = required_layers.data,
        enabledExtensionCount = xx required_instance_extensions.count,
        ppEnabledExtensionNames = required_instance_extensions.data
    };

    if !render_evaluate(.LOW, vkCreateInstance(*create_info, null, *vk_instance), "failed to create vulkan instance") then return false;

    render_log(.MEDIUM, "created vk instance");
    return true;
}

instance_extensions_are_supported :: (extensions: []*u8) -> bool {
    auto_release_temp();

    available_extensions, result := vkEnumerateInstanceExtensionProperties(null,,temp);
    if !render_evaluate(.LOW, result, "failed to enumerate instance extension properties") then return false;

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
    if !render_evaluate(.LOW, result, "failed to enumerate instance instance layer properties") then return false;

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
            render_log(.MEDIUM, "unable to find layer % in available layers", to_string(need_layer));
            return false;
        }
    }

    return true;
}

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------------- :surface

create_surface :: () -> bool {
    using context.renderer;

    #if OS == .WINDOWS {
        create_info := VkWin32SurfaceCreateInfoKHR.{
            hwnd = window,
            hinstance = Win32.GetModuleHandleW(null)
        };
        if !render_evaluate(.LOW, vkCreateWin32SurfaceKHR(vk_instance, *create_info, null, *surface), "failed to create surface") then return false;
    } else {
        return false;
    }

    render_log(.MEDIUM, "created surface from window");
    return true;
}

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------ :physical device

select_physical_device :: () -> bool {
    using context.renderer;
    auto_release_temp();

    devices, result := vkEnumeratePhysicalDevices(vk_instance,,temp);
    if !render_evaluate(.LOW, result, "failed to enumerate physical devices") then return false;
    if !render_evaluate(.LOW, devices.count > 0, "no physical devices found on the system") then return false;

    best_score: s32;
    best_scored_device: VkPhysicalDevice;

    for devices {
        device_score := score_physical_device(it);
        if device_score > best_score {
            best_score = device_score;
            best_scored_device = it;
        }
    }

    if !render_evaluate(.LOW, best_scored_device != null, "unable to find a suitable physical device") then return false;

    context.renderer.physical.obj = best_scored_device;
    if !render_evaluate(.LOW, determine_physical_device_queue_family_capabilities(*context.renderer.physical), "unable to set selected physical device queue family properties") then return false;

    set_physical_device_properties(*physical);
    {
        using physical.properties;
        render_log(.MEDIUM, 
#string HERE
found suitable physical device...

    api version     %
    driver version  %
    vendor          %
    device id       0x%
    device type     %
    device name     %
HERE,
            make_string(get_graphics_api_version(context.renderer),,temp),
            make_string(get_physical_device_driver_version(context.renderer),,temp),
            get_physical_device_vendor(context.renderer),
            FormatInt.{value=device_id, base=16, minimum_digits=4},
            device_type,
            device_name
        );
    }

    return true;
}

set_physical_device_properties :: (physical: *Physical_Device) {
    using physical;
    temp_properties: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(obj, *temp_properties);
    properties.api_version = temp_properties.apiVersion;
    properties.driver_version = temp_properties.driverVersion;
    properties.vendor_id = temp_properties.vendorID;
    properties.device_id = temp_properties.deviceID;
    properties.device_type = temp_properties.deviceType;
    properties.texel_buffer_alignment = temp_properties.limits.minTexelBufferOffsetAlignment;
    properties.uniform_buffer_alignment = temp_properties.limits.minUniformBufferOffsetAlignment;
    properties.storage_buffer_alignment = temp_properties.limits.minStorageBufferOffsetAlignment;
    // properties.image_alignment = temp_properties.limits.bufferImageGranularity;
    memcpy(properties.device_name_buffer.data, temp_properties.deviceName.data, min(properties.device_name_buffer.count, temp_properties.deviceName.count));
    properties.device_name = to_string_safe(properties.device_name_buffer.data, properties.device_name_buffer.count);
}

score_physical_device :: (device: VkPhysicalDevice) -> score: s32 {
    properties: VkPhysicalDeviceProperties;
    features: VkPhysicalDeviceFeatures;
    vkGetPhysicalDeviceProperties(device, *properties);
    vkGetPhysicalDeviceFeatures(device, *features);

    dummy_device := Physical_Device.{obj=device};
    if !determine_physical_device_queue_family_capabilities(*dummy_device) {
        return 0;
    }
    if depth_buffer_format(device) == .UNDEFINED {
        return 0;
    }
    if dummy_device.queue_family_indices.graphics_index == -1 
    || dummy_device.queue_family_indices.present_index  == -1 {
        return 0;
    }
    if !device_extensions_are_supported(device, required_device_extensions) {
        return 0;
    }
    info: Swapchain_Support_Info;
    if !get_swapchain_support_info(device, *info,, temp) {
        return 0;
    }
    if info.present_modes.count == 0 || info.formats.count == 0 {
        return 0;
    }

    score : s32 = ifx properties.deviceType == .DISCRETE_GPU then (100).(s32) else (1).(s32);
    score += cast(s32) properties.limits.maxImageDimension2D;
    render_log(.MEDIUM, "max image dimension: %", properties.limits.maxImageDimension2D);
    if dummy_device.queue_family_indices.graphics_index == dummy_device.queue_family_indices.present_index 
        then score += 50;
    return score;
}


determine_physical_device_queue_family_capabilities :: (physical: *Physical_Device) -> bool {
    physical.queue_family_indices = .{};

    queue_family_properties := vkGetPhysicalDeviceQueueFamilyProperties(physical.obj,,temp);
    if !render_evaluate(.LOW, queue_family_properties.count > 0, "physical device queue family properties count is 0") then return false;

    max_support_score: float;

    for family : queue_family_properties {
        using physical.queue_family_indices;

        present_support: VkBool32;
        vkGetPhysicalDeviceSurfaceSupportKHR(physical.obj, xx it_index, context.renderer.surface, *present_support);

        // just try to get them all on the same queue.
        score := 0.0;
        if family.queueFlags & .GRAPHICS_BIT {
            if graphics_index == -1 {
                graphics_index = xx it_index;
            }
            score += 2;
        }
        if family.queueFlags & .TRANSFER_BIT {
            if transfer_index == -1 {
                transfer_index = xx it_index;
            }
            score += ifx family.queueFlags & .GRAPHICS_BIT then 2 else 1;
        }
        if family.queueFlags & .COMPUTE_BIT {
            if compute_index == -1 {
                compute_index = xx it_index;
            }
            score += 1;
        }
        if present_support {
            if present_index == -1 {
                present_index = xx it_index;
            }
            score += 1;
        }

        if score > max_support_score {
            if family.queueFlags & .GRAPHICS_BIT {
                graphics_index = xx it_index;
            }
            if family.queueFlags & .TRANSFER_BIT {
                transfer_index = xx it_index;
            }
            if family.queueFlags & .COMPUTE_BIT {
                compute_index = xx it_index;
            }
            if present_support {
                present_index = xx it_index;
            }
            max_support_score = score;
        }
    }
    return true;
}

device_extensions_are_supported :: (phys: VkPhysicalDevice, extensions: []*u8) -> bool {
    auto_release_temp();

    available_extensions, result := vkEnumerateDeviceExtensionProperties(phys, null,,temp);
    if !render_evaluate(.LOW, result, "unable to enumerate physical device extension properties") then return false;

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

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------- :logical device

create_logical_device :: () -> bool {
    using context.renderer;
    auto_release_temp();

    queue_priority : float32 = 1.0;
    unique_queue_family_indices := get_unique_queue_family_indices(*physical);
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

    // VkPhysicalDeviceVulkan12Features :: struct {
    //     sType:                                              VkStructureType = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES;
    //     pNext:                                              *void;
    //     samplerMirrorClampToEdge:                           VkBool32;
    //     drawIndirectCount:                                  VkBool32;
    //     storageBuffer8BitAccess:                            VkBool32;
    //     uniformAndStorageBuffer8BitAccess:                  VkBool32;
    //     storagePushConstant8:                               VkBool32;
    //     shaderBufferInt64Atomics:                           VkBool32;
    //     shaderSharedInt64Atomics:                           VkBool32;
    //     shaderFloat16:                                      VkBool32;
    //     shaderInt8:                                         VkBool32;
    //     descriptorIndexing:                                 VkBool32;
    //     shaderInputAttachmentArrayDynamicIndexing:          VkBool32;
    //     shaderUniformTexelBufferArrayDynamicIndexing:       VkBool32;
    //     shaderStorageTexelBufferArrayDynamicIndexing:       VkBool32;
    //     shaderUniformBufferArrayNonUniformIndexing:         VkBool32;
    //     shaderSampledImageArrayNonUniformIndexing:          VkBool32;
    //     shaderStorageBufferArrayNonUniformIndexing:         VkBool32;
    //     shaderStorageImageArrayNonUniformIndexing:          VkBool32;
    //     shaderInputAttachmentArrayNonUniformIndexing:       VkBool32;
    //     shaderUniformTexelBufferArrayNonUniformIndexing:    VkBool32;
    //     shaderStorageTexelBufferArrayNonUniformIndexing:    VkBool32;
    //     descriptorBindingUniformBufferUpdateAfterBind:      VkBool32;
    //     descriptorBindingSampledImageUpdateAfterBind:       VkBool32;
    //     descriptorBindingStorageImageUpdateAfterBind:       VkBool32;
    //     descriptorBindingStorageBufferUpdateAfterBind:      VkBool32;
    //     descriptorBindingUniformTexelBufferUpdateAfterBind: VkBool32;
    //     descriptorBindingStorageTexelBufferUpdateAfterBind: VkBool32;
    //     descriptorBindingUpdateUnusedWhilePending:          VkBool32;
    //     descriptorBindingPartiallyBound:                    VkBool32;
    //     descriptorBindingVariableDescriptorCount:           VkBool32;
    //     runtimeDescriptorArray:                             VkBool32;
    //     samplerFilterMinmax:                                VkBool32;
    //     scalarBlockLayout:                                  VkBool32;
    //     imagelessFramebuffer:                               VkBool32;
    //     uniformBufferStandardLayout:                        VkBool32;
    //     shaderSubgroupExtendedTypes:                        VkBool32;
    //     separateDepthStencilLayouts:                        VkBool32;
    //     hostQueryReset:                                     VkBool32;
    //     timelineSemaphore:                                  VkBool32;
    //     bufferDeviceAddress:                                VkBool32;
    //     bufferDeviceAddressCaptureReplay:                   VkBool32;
    //     bufferDeviceAddressMultiDevice:                     VkBool32;
    //     vulkanMemoryModel:                                  VkBool32;
    //     vulkanMemoryModelDeviceScope:                       VkBool32;
    //     vulkanMemoryModelAvailabilityVisibilityChains:      VkBool32;
    //     shaderOutputViewportIndex:                          VkBool32;
    //     shaderOutputLayer:                                  VkBool32;
    //     subgroupBroadcastDynamicId:                         VkBool32;
    // }

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

    result := vkCreateDevice(physical.obj, *device_create_info, null, *logical.obj);
    if !render_evaluate(.LOW, result, "failed to create the logical device") return false;

    vkGetDeviceQueue(logical.obj, xx physical.queue_family_indices.graphics_index, 0, *graphics_queue);
    vkGetDeviceQueue(logical.obj, xx physical.queue_family_indices.transfer_index, 0, *transfer_queue);

    render_log(.MEDIUM, "created logical device");
    return true;
}

get_unique_queue_family_indices :: (physical: *Physical_Device) -> []u32 {
    already_made_queue: Queue_Family_Capability_Flags;
    unique_indices := make_dynamic_array(u32, 4,, temp);
    for 0..physical.queue_family_indices.array.count-1 {
        flag := (1 << physical.queue_family_indices.array[it]).(Queue_Family_Capability_Flags);
        if (already_made_queue & flag) != 0 {
            continue;
        }
        array_add(*unique_indices, xx physical.queue_family_indices.array[it]);
        already_made_queue |= flag;
    }
    return unique_indices;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------- :frame data

create_frame_datas :: () -> bool {
    using context.renderer;
    auto_release_temp();

    render_check(.LOW, frames.data == null);
    frames = make_static_array(Graphics_Frame, min(swapchain.images.count, 2));

    command_pool_info := VkCommandPoolCreateInfo.{
        flags = .RESET_COMMAND_BUFFER_BIT,
        queueFamilyIndex = xx physical.queue_family_indices.graphics_index
    };

    fence_info := VkFenceCreateInfo.{
        flags = .SIGNALED_BIT
    };
    
    semaphore_info := VkSemaphoreCreateInfo.{};

    for 0..frames.count-1 {
        if !render_evaluate(.LOW, vkCreateCommandPool(logical.obj, *command_pool_info, null, *frames[it].command_pool), "failed to create a command pool") then return false;

        command_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = frames[it].command_pool,
            commandBufferCount = 1,
            level = .PRIMARY
        };

        if !render_evaluate(.LOW, vkAllocateCommandBuffers(logical.obj, *command_alloc_info, *frames[it].command_buffer), "failed to create a command buffer") then return false;

        if !render_evaluate(.LOW, vkCreateFence(logical.obj, *fence_info, null, *frames[it].render_fence), "failed to create a render fence") then return false;

        if !render_evaluate(.LOW, vkCreateFence(logical.obj, *fence_info, null, *frames[it].present_fence), "failed to create a present fence") then return false;

        if !render_evaluate(.LOW, vkCreateSemaphore(logical.obj, *semaphore_info, null, *frames[it].image_available_semaphore), "failed to create a semaphore") then return false;

        if !render_evaluate(.LOW, vkCreateSemaphore(logical.obj, *semaphore_info, null, *frames[it].image_rendered_semaphore), "failed to create a semaphore") then return false;
    }

    fence_info.flags = 0;

    {
        pool_info := VkCommandPoolCreateInfo.{
            flags = .RESET_COMMAND_BUFFER_BIT,
            queueFamilyIndex = xx physical.queue_family_indices.transfer_index
        };

        if !render_evaluate(.LOW, vkCreateCommandPool(logical.obj, *pool_info, null, *transfer_command_pool), "failed to create the transfer command pool") then return false;

        buffer_alloc_info := VkCommandBufferAllocateInfo.{
            commandPool = transfer_command_pool,
            commandBufferCount = 1,
            level = .PRIMARY
        };

        if !render_evaluate(.LOW, vkAllocateCommandBuffers(logical.obj, *buffer_alloc_info, *transfer_command_buffer), "failed to create the transfer command pool") then return false;

        if !render_evaluate(.LOW, vkCreateFence(logical.obj, *fence_info, null, *transfer_fence), "failed to create the transfer fence") then return false;
    }

    render_log(.MEDIUM, "created frame datas. max frames in flight %", frames.count);
    return true;
}

create_default_descriptors :: () -> bool {
    using context.renderer;
    auto_release_temp();
    return true;
}

create_default_pipelines :: () -> bool {
    using context.renderer;

    // making pipeline layouts
    create_default_pipeline_layouts();

    {
        build_info: Graphics_Pipeline_Build_Info;
        build_info.pipeline_layout = billboard_pipeline_layout;
        make_default_vertex_fragment_pipeline_build_info(
            *build_info, "billboard_vert", "billboard_frag", Static_Mesh_Vertex
        );
        build_info.name = "billboard pipeline";
        build_info.depth_stencil.create.depthWriteEnable = VK_FALSE;
        build_info.color_blend.attachment.blendEnable = VK_TRUE;
        billboard_pipeline = build_pipeline(*build_info);
    }

    {
        build_info: Graphics_Pipeline_Build_Info;
        build_info.pipeline_layout = opaque_mesh_pipeline_layout;
        make_default_vertex_fragment_pipeline_build_info(
            *build_info, "mesh_vert", "mesh_frag", Static_Mesh_Vertex
        );

        build_info.name = "opaque mesh pipeline";
        opaque_mesh_pipeline = build_pipeline(*build_info);

        build_info.name = "transparent mesh pipeline";
        build_info.depth_stencil.create.depthWriteEnable = VK_FALSE;
        build_info.color_blend.attachment.blendEnable = VK_TRUE;
        transparent_mesh_pipeline = build_pipeline(*build_info);

    }
    {
        build_info: Graphics_Pipeline_Build_Info;
        build_info.pipeline_layout = opaque_skinned_mesh_pipeline_layout;
        make_default_vertex_fragment_pipeline_build_info(
            *build_info, "skinned_mesh_vert", "mesh_frag", Skeletal_Mesh_Vertex
        );

        build_info.name = "opaque skinned mesh pipeline";
        opaque_skinned_mesh_pipeline = build_pipeline(*build_info);

        build_info.name = "transparent skinned mesh pipeline";
        build_info.depth_stencil.create.depthWriteEnable = VK_FALSE;
        build_info.color_blend.attachment.blendEnable = VK_TRUE;
        build_info.rasterization.create.cullMode = .FRONT_BIT;
        transparent_skinned_mesh_pipeline = build_pipeline(*build_info);
    }
    {
        build_info: Graphics_Pipeline_Build_Info;
        build_info.pipeline_layout = opaque_mesh_pipeline_layout;
        make_default_vertex_fragment_pipeline_build_info(
            *build_info, "simple_mesh_vert", "simple_mesh_frag", Static_Mesh_Vertex
        );

        dynamic_states := VkDynamicState.[.VIEWPORT, .SCISSOR, .LINE_WIDTH]; 

        build_info.name = "draw in front opaque line pipeline";
        build_info.input_assembly.create.topology = .LINE_LIST;
        build_info.depth_stencil.create.depthTestEnable = VK_FALSE;
        build_info.depth_stencil.create.depthWriteEnable = VK_TRUE;
        build_info.dynamic_state.create = {
            dynamicStateCount = xx dynamic_states.count,
            pDynamicStates    = dynamic_states.data
        };
        draw_in_front_opaque_line_pipeline = build_pipeline(*build_info);

        build_info.name = "draw in front transparent line pipeline";
        build_info.color_blend.attachment.blendEnable = VK_TRUE;
        draw_in_front_transparent_line_pipeline = build_pipeline(*build_info);

        build_info.name = "opaque line pipeline";
        build_info.color_blend.attachment.blendEnable = VK_FALSE;
        build_info.depth_stencil.create.depthTestEnable = VK_TRUE;
        opaque_line_pipeline = build_pipeline(*build_info);
    }
    
    render_log(.MEDIUM, "created default pipelines");
    return true;
}

create_default_pipeline_layouts :: () -> bool {
    using context.renderer;

    // 0 = textures
    // 1 = materials
    // 2 = per frame uniform
    {
        // 3 = billboard instances
        descriptor_set_layouts := VkDescriptorSetLayout.[
            textures_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            uniform_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout
        ];
        create_pipeline_layout := VkPipelineLayoutCreateInfo.{
            setLayoutCount = xx descriptor_set_layouts.count,
            pSetLayouts = descriptor_set_layouts.data,
        };

        if !render_evaluate(.LOW, vkCreatePipelineLayout(logical.obj, *create_pipeline_layout, null, *billboard_pipeline_layout), "failed to create billboard pipeline layout") {
            return false;
        }
    }
    {
        // 3 = mesh transforms
        // 4 = mesh instances
        descriptor_set_layouts := VkDescriptorSetLayout.[
            textures_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            uniform_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout
        ];

        create_pipeline_layout := VkPipelineLayoutCreateInfo.{
            setLayoutCount = xx descriptor_set_layouts.count,
            pSetLayouts = descriptor_set_layouts.data
        };

        if !render_evaluate(.LOW, vkCreatePipelineLayout(logical.obj, *create_pipeline_layout, null, *opaque_mesh_pipeline_layout), "failed to create mesh pipeline layout") {
            return false;
        }
    }
    {
        // 3 = mesh transforms
        // 4 = mesh instances
        // 5 = skinning joints
        descriptor_set_layouts := VkDescriptorSetLayout.[
            textures_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            uniform_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout,
            storage_buffer_descriptor_set_layout
        ];

        create_pipeline_layout := VkPipelineLayoutCreateInfo.{
            setLayoutCount = xx descriptor_set_layouts.count,
            pSetLayouts = descriptor_set_layouts.data
        };

        if !render_evaluate(.LOW, vkCreatePipelineLayout(logical.obj, *create_pipeline_layout, null, *opaque_skinned_mesh_pipeline_layout), "failed to create skinned mesh pipeline layout") {
            return false;
        }
    }

    return true;
}

// -----------------------------------------------------------------------------------
// ---------------------------------------------------------------------- :descriptors

create_descriptors :: () -> bool {
    using context.renderer;

    ratios := Descriptor_Pool_Ratio.[
        {.STORAGE_IMAGE, 0.25}, 
        {.COMBINED_IMAGE_SAMPLER, 0.25}, 
        {.UNIFORM_BUFFER, 0.25},
        {.STORAGE_BUFFER, 0.25}
    ];
    create_descriptor_pool(*descriptor_pool, xx (max_texture_count * 4), ratios);

    // Sets = granularity of when things change
    // Bindings = individual resources within that granularity

    // can use UNIFORM_BUFFER_DYNAMIC and STORAGE_BUFFER_DYNAMIC for buffers
    // whose memory stays the same, but offset changes.

    // any ubo can use this layout
    uniform_buffer_binding := VkDescriptorSetLayoutBinding.[
        {binding=0, descriptorCount=1, descriptorType=.UNIFORM_BUFFER, stageFlags=.ALL}
    ];
    uniform_buffer_descriptor_set_layout = build_descriptor_set_layout(uniform_buffer_binding);

    // any ssbo can use this layout
    storage_buffer_binding := VkDescriptorSetLayoutBinding.[
        {binding=0, descriptorCount=1, descriptorType=.STORAGE_BUFFER, stageFlags=.VERTEX_BIT | .FRAGMENT_BIT}
    ];
    storage_buffer_descriptor_set_layout = build_descriptor_set_layout(storage_buffer_binding);

    {
        // descriptor set of all images
        textures_binding := VkDescriptorSetLayoutBinding.[{
            binding         = 0, 
            descriptorCount = xx max_texture_count, 
            descriptorType  = .COMBINED_IMAGE_SAMPLER, 
            stageFlags      = .VERTEX_BIT | .FRAGMENT_BIT
        }];

        // Mark it as partially bound and variable count
        binding_flags : VkDescriptorBindingFlags = .PARTIALLY_BOUND_BIT | .VARIABLE_DESCRIPTOR_COUNT_BIT;
        flags_info := VkDescriptorSetLayoutBindingFlagsCreateInfo.{
            bindingCount  = 1,
            pBindingFlags = *binding_flags
        };

        textures_descriptor_set_layout = build_descriptor_set_layout(textures_binding, p_next = *flags_info);

        max_texture_count_u32 : u32 = xx max_texture_count;

        variable_count_info := VkDescriptorSetVariableDescriptorCountAllocateInfo.{
            descriptorSetCount = 1,
            pDescriptorCounts  = *max_texture_count_u32
        };

        textures_descriptor_set = allocate_descriptor_set(descriptor_pool, textures_descriptor_set_layout, *variable_count_info);

        for *ref : context.renderer.texture_references {
            sampler := get_or_add_sampler(ref.min_filter, ref.mag_filter, ref.horizontal_wrap, ref.vertical_wrap);
            ref.local_buffer  = -1;
            ref.global_buffer = xx add_gpu_image_for_sampling(ref.path, sampler).pool_index;
        }
    }

    create_gpu_storage_buffer(
        descriptor_pool, 
        *materials_storage_buffer_descriptor_set, 
        *materials_storage_buffer, 
        size_of(GPU_Material) * MAX_MATERIALS
    );

    create_gpu_vertex_buffer(*billboard_vertex_buffer, billboard_vertices);

    for *frame : context.renderer.frames {
        create_gpu_uniform_buffer(
            descriptor_pool,
            *frame.per_frame_uniform_descriptor_set, 
            *frame.per_frame_uniform_buffer, 
            size_of(Per_Frame_Uniform_Buffer)
        ); 

        create_gpu_storage_buffer(
            descriptor_pool, 
            *frame.mesh_instances_shader_data_descriptor_set, 
            *frame.mesh_instances_shader_data, 
            size_of(Mesh_Instance_Shader_Data) * MAX_STATIC_MESHES
        );

        create_gpu_storage_buffer(
            descriptor_pool, 
            *frame.skinned_mesh_instances_shader_data_descriptor_set, 
            *frame.skinned_mesh_instances_shader_data, 
            size_of(Mesh_Instance_Shader_Data) * MAX_SKINNED_MESHES
        );

        create_gpu_storage_buffer(
            descriptor_pool, 
            *frame.mesh_sections_shader_data_descriptor_set, 
            *frame.mesh_sections_shader_data, 
            size_of(Mesh_Section_Shader_Data) * MAX_STATIC_MESHES * 8
        );

        create_gpu_storage_buffer(
            descriptor_pool, 
            *frame.skinned_mesh_sections_shader_data_descriptor_set, 
            *frame.skinned_mesh_sections_shader_data, 
            size_of(Mesh_Section_Shader_Data) * MAX_SKINNED_MESHES * 8
        );

        create_gpu_storage_buffer(
            descriptor_pool,
            *frame.skinning_joints_buffer_descriptor_set,
            *frame.skinning_joints_buffer,
            size_of(Matrix4) * MAX_SKINNING_JOINTS
        );

        max_billboard_instance_count := 100_000;
        create_gpu_storage_buffer(
            descriptor_pool, 
            *frame.billboard_instance_buffer_descriptor_set, 
            *frame.billboard_instance_buffer, 
            size_of(Billboard_Instance) * max_billboard_instance_count
        );

        max_draw_command_count := 5_000;
        create_gpu_storage_buffer(
            descriptor_pool,
            *frame.opaque_mesh_draw_commands_descriptor_set,
            *frame.opaque_mesh_draw_commands,
            size_of(VkDrawIndexedIndirectCommand) * max_draw_command_count
        );

        create_gpu_storage_buffer(
            descriptor_pool,
            *frame.opaque_skinned_mesh_draw_commands_descriptor_set,
            *frame.opaque_skinned_mesh_draw_commands,
            size_of(VkDrawIndexedIndirectCommand) * max_draw_command_count
        );
    }

    return true;
}

// -----------------------------------------------------------------------------------
// ----------------------------------------------------------------------- :allocators

initialize_allocators :: () -> bool {
    using context.renderer;

    // Create throwaway resources to probe compatibility

    dummy_buffer_create_info := VkBufferCreateInfo.{
        size = 4096,
        usage = .VERTEX_BUFFER_BIT
              | .INDEX_BUFFER_BIT
              | .UNIFORM_BUFFER_BIT
              | .STORAGE_BUFFER_BIT
              | .TRANSFER_SRC_BIT
              | .TRANSFER_DST_BIT,
        sharingMode = .EXCLUSIVE
    };
    dummy_buffer: VkBuffer;

    dummy_image_create_info := VkImageCreateInfo.{
        imageType = ._2D,
        format = .R8G8B8A8_UNORM,
        extent = {1024, 1024, 1},
        mipLevels = 1,
        arrayLayers = 1,
        samples = ._1_BIT, // MSAA
        tiling = .OPTIMAL,
        usage =  .TRANSFER_DST_BIT | .SAMPLED_BIT,
        sharingMode = .EXCLUSIVE
    };
    dummy_image: VkImage;

    dummy_buffer_requirements: VkMemoryRequirements;
    dummy_image_requirements: VkMemoryRequirements;

    vkCreateBuffer(logical.obj, *dummy_buffer_create_info, null, *dummy_buffer);
    vkGetBufferMemoryRequirements(logical.obj, dummy_buffer, *dummy_buffer_requirements);
    vkDestroyBuffer(logical.obj, dummy_buffer, null);

    vkCreateImage(logical.obj, *dummy_image_create_info, null, *dummy_image);   // OPTIMAL tiling, typical format
    vkGetImageMemoryRequirements(logical.obj, dummy_image, *dummy_image_requirements);
    vkDestroyImage(logical.obj, dummy_image, null);

    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical.obj, *memory_properties);

    physical.properties.device_local_buffer_memory_index = find_index_of_memory_type(dummy_buffer_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT, *memory_properties);
    physical.properties.host_visible_buffer_memory_index = find_index_of_memory_type(dummy_buffer_requirements.memoryTypeBits, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *memory_properties);
    physical.properties.device_local_image_memory_index = find_index_of_memory_type(dummy_image_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT, *memory_properties);
    physical.properties.host_visible_image_memory_index = find_index_of_memory_type(dummy_image_requirements.memoryTypeBits, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, *memory_properties);

    for *linear_allocators {
        it.heap_type = cast(GPU_Heap_Type) it_index;
    }

    // todo: allocate memory in each category for allocators.
    return true;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------------- :assets

load_assets :: () -> bool {
    using context.renderer;

    // for *ref : mesh_references {
    //     if ref.do_not_load_at_startup {
    //         continue;
    //     }
    //     mesh, success := load_mesh(ref.path);
    //     if success {
    //         add_mesh(context.renderer, *mesh, ref);
    //         render_log("succeeded loading mesh at %", ref.path);
    //     } else {
    //         ref.index = -1;
    //         render_log("FAILED loading mesh at %", ref.path);
    //     }
    // }
    return true;
}

// -----------------------------------------------------------------------------------

#scope_file

#if RENDER_VALIDATION_LEVEL >= 1 {
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

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

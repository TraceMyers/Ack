#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

Physical_Device :: struct {
    obj: VkPhysicalDevice;
    type: VkPhysicalDeviceType;
    size: VkDeviceSize;
    queue_family_indices: Queue_Family_Indices;
    properties: Physical_Device_Properties;
}

Queue_Family_Capability_Flags :: enum_flags {
    PRESENT;
    GRAPHICS;
    COMPUTE;
    TRANSFER;
}

Queue_Family_Indices :: struct {
    present_index:  u32 = U32_MAX;
    graphics_index: u32 = U32_MAX;
    compute_index:  u32 = U32_MAX;
    transfer_index: u32 = U32_MAX;
    #overlay(present_index) array: [4]u32 = ---;
}

Physical_Device_Properties :: struct {
    api_version: u32;
    driver_version: u32;
    vendor_id: u32;
    device_id: u32;
    device_type: VkPhysicalDeviceType;
    device_name: string;
    device_name_buffer: [256]u8;
    texel_buffer_alignment: VkDeviceSize;
    uniform_buffer_alignment: VkDeviceSize;
    storage_buffer_alignment: VkDeviceSize;
    device_local_buffer_memory_index: u32;
    host_visible_buffer_memory_index: u32;
    device_local_image_memory_index: u32;
    host_visible_image_memory_index: u32;
    image_alignment: VkDeviceSize;
}

select_physical_device :: () -> bool {
    auto_release_temp();

    devices, result := vkEnumeratePhysicalDevices(vk_instance,,temp);
    if !render_evaluate(result, "failed to enumerate physical graphics devices") then return false;
    if !render_evaluate(devices.count > 0, "no physical graphics devices found on the system") then return false;

    best_score: s32;
    best_scored_device: VkPhysicalDevice;

    for devices {
        device_score := score_physical_device(it);
        if device_score > best_score {
            best_score = device_score;
            best_scored_device = it;
        }
    }

    if !render_evaluate(best_scored_device != null, "unable to find a suitable physical graphics device") then return false;

    physical_device.obj = best_scored_device;
    if !render_evaluate(determine_physical_device_queue_family_capabilities(*physical_device), "unable to set selected physical graphics device queue family properties") then return false;

    set_physical_device_properties(*physical_device);
    set_physical_device_size(*physical_device);

    render_log(
#string HERE
found suitable physical device...

    api version     %
    driver version  %
    vendor          %
    device id       0x%
    device type     %
    device name     %
    vram size       % MB
HERE,
        make_version_string(get_graphics_api_version(),, temp),
        make_version_string(get_physical_device_driver_version(),, temp),
        get_physical_device_vendor(),
        FormatInt.{value=physical_device.properties.device_id, base=16, minimum_digits=4},
        physical_device.properties.device_type,
        physical_device.properties.device_name,
        fmt_commas(physical_device.size / (1024 * 1024)),
        flags=.VERBOSE_ONLY,
        user_flags = xx Ack_Log_Flags.ADD_NEWLINE
    );

    return true;
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
    render_log("max image dimension: %", properties.limits.maxImageDimension2D, flags=.VERBOSE_ONLY);
    if dummy_device.queue_family_indices.graphics_index == dummy_device.queue_family_indices.present_index {
        score += 50;
    }

    return score;
}

determine_physical_device_queue_family_capabilities :: (physical: *Physical_Device) -> bool {
    physical.queue_family_indices = .{};

    queue_family_properties := vkGetPhysicalDeviceQueueFamilyProperties(physical.obj,,temp);
    if !render_evaluate(queue_family_properties.count > 0, "physical device queue family properties count is 0") then return false;

    max_support_score: float;

    for family : queue_family_properties {
        using physical.queue_family_indices;

        present_support: VkBool32;
        vkGetPhysicalDeviceSurfaceSupportKHR(physical.obj, xx it_index, surface, *present_support);

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
    if !render_evaluate(result, "unable to enumerate physical device extension properties") then return false;

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

depth_buffer_format :: (phys: VkPhysicalDevice) -> VkFormat {
    need_flags : VkFormatFeatureFlags = .DEPTH_STENCIL_ATTACHMENT_BIT | .SAMPLED_IMAGE_BIT;
    for format : DEPTH_STENCIL_FORMATS {
        props: VkFormatProperties;
        vkGetPhysicalDeviceFormatProperties(phys, format, *props);
        if (props.optimalTilingFeatures & need_flags) == need_flags {
            return format;
        }
    }
    return .UNDEFINED;
}

get_swapchain_support_info :: (phys: VkPhysicalDevice, info: *Swapchain_Support_Info) -> bool {
    if !render_evaluate(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys, surface, *info.capabilities), "unable to get surface capabilities of a physical device") {
        return false;
    }
    result: VkResult;
    {
        info.formats, result = vkGetPhysicalDeviceSurfaceFormatsKHR(phys, surface);
        if !render_evaluate(result, "unable to get phys device surface formats") || info.formats.count == 0 {
            return false;
        }
    }
    {
        info.present_modes, result = vkGetPhysicalDeviceSurfacePresentModesKHR(phys, surface);
        if !render_evaluate(result, "unable to get surface present modes") || info.present_modes.count == 0 {
            return false;
        }
    }
    return true;
}

set_physical_device_properties :: (physical: *Physical_Device) {
    using physical;
    temp_properties: VkPhysicalDeviceProperties;

    vkGetPhysicalDeviceProperties(physical.obj, *temp_properties);
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

set_physical_device_size :: (physical: *Physical_Device) -> bool {
    physical.size = 0;

    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical.obj, *memory_properties);

    for 0..memory_properties.memoryHeapCount-1 {
        if memory_properties.memoryHeaps[it].flags & .DEVICE_LOCAL_BIT {
            physical.size = memory_properties.memoryHeaps[it].size;
            return true;
        }
    }

    return false;
}

temp_get_unique_queue_family_indices :: (physical: *Physical_Device) -> []u32 {
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

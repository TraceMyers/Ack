get_graphics_api_version :: () -> Version {
    version_u32 := engine.renderer.backend.physical_device.properties.api_version;
    return {
        VK_VERSION_MAJOR(version_u32),
        VK_VERSION_MINOR(version_u32),
        VK_VERSION_PATCH(version_u32)
    };
}

make_version_string :: (driver_version: Physical_Device_Driver_Version) -> string {
    builder: String_Builder;
    for driver_version.array {
        if it <= -1 {
            break;
        }
        if it_index > 0 {
            print(*builder, ".%", it);
        } else {
            print(*builder, "%", it);
        }
    }
    return builder_to_string(*builder);
}

make_version_string :: (using api_version: Version) -> string {
    return sprint("%.%.%", major, minor, patch);
}

make_version_string :: (version: u32) -> string {
    major := VK_API_VERSION_MAJOR(version);
    minor := VK_API_VERSION_MINOR(version);
    patch := VK_API_VERSION_PATCH(version);
    return sprint("%.%.%", major, minor, patch);
}

to_vulkan_version :: (version: Version) -> u32 {
    return VK_MAKE_VERSION(version.major, version.minor, version.patch);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

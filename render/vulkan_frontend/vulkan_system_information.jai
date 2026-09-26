get_physical_device_vendor :: (r: *Renderer) -> Physical_Device_Vendor {
    if r.physical.properties.vendor_id == {
    case 0x10DE;
        return .NVIDIA;
    case 0x1002; 
        #through;
    case 0x1022;
        return .AMD;
    case 0x8086;
        return .INTEL;
    case 0x13B5;
        return .ARM;
    case 0x5143;
        return .QUALCOMM;
    case 0x1010;
        return .IMGTEC;
    }
    return .UNKNOWN;
}

get_physical_device_driver_version :: (r: *Renderer) -> Physical_Device_Driver_Version {
    vendor := get_physical_device_vendor(r);
    version_u32 := r.physical.properties.driver_version;
    version: Physical_Device_Driver_Version;
    if vendor == {
    case .AMD; 
        #through;
    case .INTEL;
        version.major = xx VK_VERSION_MAJOR(version_u32);
        version.minor = xx VK_VERSION_MINOR(version_u32);
        version.patch = xx VK_VERSION_PATCH(version_u32);
    case .NVIDIA;
        version.major     = xx (version_u32 & 0xffc0_0000) >> 22;
        version.minor     = xx (version_u32 & 0x003f_c000) >> 14;
        version.secondary = xx (version_u32 & 0x0000_3fc0) >> 6;
        version.tertiary  = xx (version_u32 & 0x0000_003f) >> 0;
    }
    return version;
}

get_graphics_api_version :: (r: *Renderer) -> Graphics_API_Version {
    version_u32 := r.physical.properties.api_version;
    return {
        VK_VERSION_MAJOR(version_u32),
        VK_VERSION_MINOR(version_u32),
        VK_VERSION_PATCH(version_u32)
    };
}

make_string :: (driver_version: Physical_Device_Driver_Version) -> string {
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

make_string :: (using api_version: Graphics_API_Version) -> string {
    return sprint("%.%.%", major, minor, patch);
}

renderer_version_string :: (version: u32) -> string {
    major := VK_API_VERSION_MAJOR(version);
    minor := VK_API_VERSION_MINOR(version);
    patch := VK_API_VERSION_PATCH(version);
    return tprint("%.%.%", major, minor, patch);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

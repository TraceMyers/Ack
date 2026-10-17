Physical_Device_Driver_Version :: struct {
    major:     s32 = -1;
    minor:     s32 = -1;
    secondary: s32 = -1;
    tertiary:  s32 = -1;
    #overlay(secondary) patch: s32 = ---;
    #overlay(major) array: [4]s32;
}

Physical_Device_Vendor :: enum u32 {
    UNKNOWN;
    NVIDIA;
    AMD;
    INTEL;
    ARM;
    QUALCOMM;
    IMGTEC;
}

get_physical_device_vram_size :: () -> u32 {
    return xx engine.renderer.backend.physical_device.size;
}

get_physical_device_vendor :: () -> Physical_Device_Vendor {
    if engine.renderer.backend.physical_device.properties.vendor_id == {
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
    render_warning("unknown vendor id %", engine.renderer.backend.physical_device.properties.vendor_id);
    return .UNKNOWN;
}

get_physical_device_driver_version :: () -> Physical_Device_Driver_Version {
    vendor := get_physical_device_vendor();
    version_u32 := engine.renderer.backend.physical_device.properties.driver_version;
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
    case;
        render_warning("unsupported vender for getting driver version: %", vendor);
    }
    return version;
}

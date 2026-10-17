// Enumeration helpers
// copied from the base (included with compiler) module. was easier than updating the generator
// the local vulkan submodule.

vkEnumeratePhysicalDevices :: (instance: VkInstance) -> [] VkPhysicalDevice, VkResult {
    count: u32;
    data: [] VkPhysicalDevice;
    result: VkResult;
    result = vkEnumeratePhysicalDevices(instance, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkPhysicalDevice, initialized = false);
    result = vkEnumeratePhysicalDevices(instance, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceQueueFamilyProperties :: (physicalDevice: VkPhysicalDevice) -> [] VkQueueFamilyProperties {
    count: u32;
    data: [] VkQueueFamilyProperties;
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkQueueFamilyProperties, initialized = false);
    vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, *count, data.data);
    return data;
}

vkEnumerateInstanceExtensionProperties :: (pLayerName: *u8) -> [] VkExtensionProperties, VkResult {
    count: u32;
    data: [] VkExtensionProperties;
    result: VkResult;
    result = vkEnumerateInstanceExtensionProperties(pLayerName, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkExtensionProperties, initialized = false);
    result = vkEnumerateInstanceExtensionProperties(pLayerName, *count, data.data);
    return data, result;
}

vkEnumerateDeviceExtensionProperties :: (physicalDevice: VkPhysicalDevice, pLayerName: *u8) -> [] VkExtensionProperties, VkResult {
    count: u32;
    data: [] VkExtensionProperties;
    result: VkResult;
    result = vkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkExtensionProperties, initialized = false);
    result = vkEnumerateDeviceExtensionProperties(physicalDevice, pLayerName, *count, data.data);
    return data, result;
}

vkEnumerateInstanceLayerProperties :: () -> [] VkLayerProperties, VkResult {
    count: u32;
    data: [] VkLayerProperties;
    result: VkResult;
    result = vkEnumerateInstanceLayerProperties(*count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkLayerProperties, initialized = false);
    result = vkEnumerateInstanceLayerProperties(*count, data.data);
    return data, result;
}

vkEnumerateDeviceLayerProperties :: (physicalDevice: VkPhysicalDevice) -> [] VkLayerProperties, VkResult {
    count: u32;
    data: [] VkLayerProperties;
    result: VkResult;
    result = vkEnumerateDeviceLayerProperties(physicalDevice, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkLayerProperties, initialized = false);
    result = vkEnumerateDeviceLayerProperties(physicalDevice, *count, data.data);
    return data, result;
}

vkGetImageSparseMemoryRequirements :: (device: VkDevice, image: VkImage) -> [] VkSparseImageMemoryRequirements {
    count: u32;
    data: [] VkSparseImageMemoryRequirements;
    vkGetImageSparseMemoryRequirements(device, image, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkSparseImageMemoryRequirements, initialized = false);
    vkGetImageSparseMemoryRequirements(device, image, *count, data.data);
    return data;
}

vkGetPhysicalDeviceSparseImageFormatProperties :: (physicalDevice: VkPhysicalDevice, format: VkFormat, type: VkImageType, samples: VkSampleCountFlagBits, usage: VkImageUsageFlags, tiling: VkImageTiling) -> [] VkSparseImageFormatProperties {
    count: u32;
    data: [] VkSparseImageFormatProperties;
    vkGetPhysicalDeviceSparseImageFormatProperties(physicalDevice, format, type, samples, usage, tiling, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkSparseImageFormatProperties, initialized = false);
    vkGetPhysicalDeviceSparseImageFormatProperties(physicalDevice, format, type, samples, usage, tiling, *count, data.data);
    return data;
}

vkEnumeratePhysicalDeviceGroups :: (instance: VkInstance) -> [] VkPhysicalDeviceGroupProperties, VkResult {
    count: u32;
    data: [] VkPhysicalDeviceGroupProperties;
    result: VkResult;
    result = vkEnumeratePhysicalDeviceGroups(instance, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkPhysicalDeviceGroupProperties, initialized = false);
    result = vkEnumeratePhysicalDeviceGroups(instance, *count, data.data);
    return data, result;
}

vkGetImageSparseMemoryRequirements2 :: (device: VkDevice, pInfo: *VkImageSparseMemoryRequirementsInfo2) -> [] VkSparseImageMemoryRequirements2 {
    count: u32;
    data: [] VkSparseImageMemoryRequirements2;
    vkGetImageSparseMemoryRequirements2(device, pInfo, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkSparseImageMemoryRequirements2, initialized = false);
    vkGetImageSparseMemoryRequirements2(device, pInfo, *count, data.data);
    return data;
}

vkGetPhysicalDeviceQueueFamilyProperties2 :: (physicalDevice: VkPhysicalDevice) -> [] VkQueueFamilyProperties2 {
    count: u32;
    data: [] VkQueueFamilyProperties2;
    vkGetPhysicalDeviceQueueFamilyProperties2(physicalDevice, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkQueueFamilyProperties2, initialized = false);
    vkGetPhysicalDeviceQueueFamilyProperties2(physicalDevice, *count, data.data);
    return data;
}

vkGetPhysicalDeviceSparseImageFormatProperties2 :: (physicalDevice: VkPhysicalDevice, pFormatInfo: *VkPhysicalDeviceSparseImageFormatInfo2) -> [] VkSparseImageFormatProperties2 {
    count: u32;
    data: [] VkSparseImageFormatProperties2;
    vkGetPhysicalDeviceSparseImageFormatProperties2(physicalDevice, pFormatInfo, *count, data.data);
    if count == 0 return .[];
    data = NewArray(count, VkSparseImageFormatProperties2, initialized = false);
    vkGetPhysicalDeviceSparseImageFormatProperties2(physicalDevice, pFormatInfo, *count, data.data);
    return data;
}

vkGetPhysicalDeviceSurfaceFormatsKHR :: (physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR) -> [] VkSurfaceFormatKHR, VkResult {
    count: u32;
    data: [] VkSurfaceFormatKHR;
    result: VkResult;
    result = vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkSurfaceFormatKHR, initialized = false);
    result = vkGetPhysicalDeviceSurfaceFormatsKHR(physicalDevice, surface, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceSurfacePresentModesKHR :: (physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR) -> [] VkPresentModeKHR, VkResult {
    count: u32;
    data: [] VkPresentModeKHR;
    result: VkResult;
    result = vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkPresentModeKHR, initialized = false);
    result = vkGetPhysicalDeviceSurfacePresentModesKHR(physicalDevice, surface, *count, data.data);
    return data, result;
}

vkGetSwapchainImagesKHR :: (device: VkDevice, swapchain: VkSwapchainKHR) -> [] VkImage, VkResult {
    count: u32;
    data: [] VkImage;
    result: VkResult;
    result = vkGetSwapchainImagesKHR(device, swapchain, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkImage, initialized = false);
    result = vkGetSwapchainImagesKHR(device, swapchain, *count, data.data);
    return data, result;
}

vkGetPhysicalDevicePresentRectanglesKHR :: (physicalDevice: VkPhysicalDevice, surface: VkSurfaceKHR) -> [] VkRect2D, VkResult {
    count: u32;
    data: [] VkRect2D;
    result: VkResult;
    result = vkGetPhysicalDevicePresentRectanglesKHR(physicalDevice, surface, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkRect2D, initialized = false);
    result = vkGetPhysicalDevicePresentRectanglesKHR(physicalDevice, surface, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceDisplayPropertiesKHR :: (physicalDevice: VkPhysicalDevice) -> [] VkDisplayPropertiesKHR, VkResult {
    count: u32;
    data: [] VkDisplayPropertiesKHR;
    result: VkResult;
    result = vkGetPhysicalDeviceDisplayPropertiesKHR(physicalDevice, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayPropertiesKHR, initialized = false);
    result = vkGetPhysicalDeviceDisplayPropertiesKHR(physicalDevice, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceDisplayPlanePropertiesKHR :: (physicalDevice: VkPhysicalDevice) -> [] VkDisplayPlanePropertiesKHR, VkResult {
    count: u32;
    data: [] VkDisplayPlanePropertiesKHR;
    result: VkResult;
    result = vkGetPhysicalDeviceDisplayPlanePropertiesKHR(physicalDevice, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayPlanePropertiesKHR, initialized = false);
    result = vkGetPhysicalDeviceDisplayPlanePropertiesKHR(physicalDevice, *count, data.data);
    return data, result;
}

vkGetDisplayPlaneSupportedDisplaysKHR :: (physicalDevice: VkPhysicalDevice, planeIndex: u32) -> [] VkDisplayKHR, VkResult {
    count: u32;
    data: [] VkDisplayKHR;
    result: VkResult;
    result = vkGetDisplayPlaneSupportedDisplaysKHR(physicalDevice, planeIndex, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayKHR, initialized = false);
    result = vkGetDisplayPlaneSupportedDisplaysKHR(physicalDevice, planeIndex, *count, data.data);
    return data, result;
}

vkGetDisplayModePropertiesKHR :: (physicalDevice: VkPhysicalDevice, display: VkDisplayKHR) -> [] VkDisplayModePropertiesKHR, VkResult {
    count: u32;
    data: [] VkDisplayModePropertiesKHR;
    result: VkResult;
    result = vkGetDisplayModePropertiesKHR(physicalDevice, display, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayModePropertiesKHR, initialized = false);
    result = vkGetDisplayModePropertiesKHR(physicalDevice, display, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceDisplayProperties2KHR :: (physicalDevice: VkPhysicalDevice) -> [] VkDisplayProperties2KHR, VkResult {
    count: u32;
    data: [] VkDisplayProperties2KHR;
    result: VkResult;
    result = vkGetPhysicalDeviceDisplayProperties2KHR(physicalDevice, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayProperties2KHR, initialized = false);
    result = vkGetPhysicalDeviceDisplayProperties2KHR(physicalDevice, *count, data.data);
    return data, result;
}

vkGetPhysicalDeviceDisplayPlaneProperties2KHR :: (physicalDevice: VkPhysicalDevice) -> [] VkDisplayPlaneProperties2KHR, VkResult {
    count: u32;
    data: [] VkDisplayPlaneProperties2KHR;
    result: VkResult;
    result = vkGetPhysicalDeviceDisplayPlaneProperties2KHR(physicalDevice, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayPlaneProperties2KHR, initialized = false);
    result = vkGetPhysicalDeviceDisplayPlaneProperties2KHR(physicalDevice, *count, data.data);
    return data, result;
}

vkGetDisplayModeProperties2KHR :: (physicalDevice: VkPhysicalDevice, display: VkDisplayKHR) -> [] VkDisplayModeProperties2KHR, VkResult {
    count: u32;
    data: [] VkDisplayModeProperties2KHR;
    result: VkResult;
    result = vkGetDisplayModeProperties2KHR(physicalDevice, display, *count, data.data);
    if result return .[], result;
    if count == 0 return .[], .SUCCESS;
    data = NewArray(count, VkDisplayModeProperties2KHR, initialized = false);
    result = vkGetDisplayModeProperties2KHR(physicalDevice, display, *count, data.data);
    return data, result;
}

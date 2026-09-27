// --- sections ---
// swapchain
// render target
// depth buffer

// VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT  = GPU fast memory
// VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT  = CPU mappable
// VK_MEMORY_PROPERTY_HOST_COHERENT_BIT = no manual flush
// VK_MEMORY_PROPERTY_HOST_CACHED_BIT   = CPU cached

// -----------------------------------------------------------------------------------
// ------------------------------------------------------------------------ :swapchain

create_swapchain_and_attachments :: () -> bool {
    using context.renderer;
    auto_release_temp();

    reset_swapchain_images();
    old_swapchain_obj := swapchain.obj;

    vkQueueWaitIdle(transfer_queue);
    vkQueueWaitIdle(graphics_queue);

    if !render_evaluate(.LOW, create_swapchain(old_swapchain_obj), "failed creating swapchain") then return false;
    if !render_evaluate(.LOW, create_render_target(), "failed creating render target") then return false;
    if !render_evaluate(.LOW, create_depth_buffer(), "failed creating depth buffer") then return false;

    should_recreate_swapchain = false;

    render_log(.MEDIUM, "created swapchain and attachments");
    return true;
}

create_swapchain :: (old_swapchain_obj: VkSwapchainKHR) -> bool {
    using context.renderer;

    support_info: Swapchain_Support_Info;

    if !render_evaluate(.LOW, get_swapchain_support_info(physical.obj, *support_info,, temp), "unable to get swapchain support info for the selected physical device") then return false;

    if !render_evaluate(.LOW, support_info.present_modes.count > 0 && support_info.formats.count > 0, "insufficient number or present modes or surface formats to create a swap chain") then return false;

    success: bool;
    swapchain.format, success       = choose_swapchain_surface_format(*support_info);
    if !render_evaluate(.LOW, success, "failed to choose a swapchain surface format") then return false;

    swapchain.present_mode, success = choose_swapchain_present_mode(*support_info);
    if !render_evaluate(.LOW, success, "failed to choose a swapchain present mode") then return false;

    swapchain.extent, success       = choose_swapchain_extent(*support_info);
    if !render_evaluate(.LOW, success, "failed to choose an extent for the swapchain") then return false;

    max_image_count : u32 = ifx support_info.capabilities.maxImageCount == 0 
        then U32_MAX 
        else support_info.capabilities.maxImageCount;

    image_count := min(support_info.capabilities.minImageCount + 1, max_image_count);

    create_info := VkSwapchainCreateInfoKHR.{
        surface = surface,
        minImageCount = image_count,
        imageFormat = swapchain.format.format,
        imageColorSpace = swapchain.format.colorSpace,
        imageExtent = swapchain.extent,
        // layers per image
        imageArrayLayers = 1,
        // render directly to the image
        imageUsage = .COLOR_ATTACHMENT_BIT /*| .TRANSFER_DST_BIT*/,
        // how to transform the image before... presenting?
        preTransform = support_info.capabilities.currentTransform,
        // whether the alpha channel should blend with other windows
        compositeAlpha = .OPAQUE_BIT_KHR,
        presentMode = swapchain.present_mode,
        // since the images of this program are composited with other
        // images on the system, there is an opportunity to discard
        // fragments hidden by other images. set to true if want.
        clipped = VK_TRUE,
        oldSwapchain = old_swapchain_obj,
        // a resource can only be owned by one queue at a time
        imageSharingMode = .EXCLUSIVE
    };

    if !render_evaluate(.LOW, vkCreateSwapchainKHR(logical.obj, *create_info, null, *swapchain.obj), "failed creating the swapchain") then return false;

    result: VkResult;
    swapchain.images, result = vkGetSwapchainImagesKHR(logical.obj, swapchain.obj);
    if !render_evaluate(.LOW, success, "unable to get the array of swapchain images") then return false;

    if old_swapchain_obj != null {
        vkDestroySwapchainKHR(logical.obj, old_swapchain_obj, null);
    }

    swapchain.image_views = make_static_array(VkImageView, swapchain.images.count);
    for swapchain.images {
        create_info := VkImageViewCreateInfo.{
            image = it,
            viewType = ._2D,
            format = swapchain.format.format,
            // image's purpose and which part of the image should be accessed. it's a color target without mips or extra layers
            subresourceRange = .{
                aspectMask = .COLOR_BIT,
                baseMipLevel = 0,
                levelCount = 1,
                baseArrayLayer = 0,
                layerCount = 1
            }
        };
        if !render_evaluate(.LOW, vkCreateImageView(logical.obj, *create_info, null, *swapchain.image_views[it_index]), "unable to create an image view for a swapchain image") then return false;
    }

    render_log(.MEDIUM, "created the swapchain. image count %", swapchain.images.count);
    return true;
}

reset_swapchain_images :: () {
    using context.renderer;
    for swapchain.image_views {
        vkDestroyImageView(logical.obj, it, null);
    }
    array_reset(*swapchain.images);
    array_reset(*swapchain.image_views);
}

get_swapchain_support_info :: (phys: VkPhysicalDevice, info: *Swapchain_Support_Info) -> bool {
    if !render_evaluate(.LOW, vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys, context.renderer.surface, *info.capabilities), "unable to get surface capabilities of a physical device") {
        return false;
    }
    result: VkResult;
    {
        info.formats, result = vkGetPhysicalDeviceSurfaceFormatsKHR(phys, context.renderer.surface);
        if !render_evaluate(.LOW, result, "unable to get phys device surface formats") || info.formats.count == 0 {
            return false;
        }
    }
    {
        info.present_modes, result = vkGetPhysicalDeviceSurfacePresentModesKHR(phys, context.renderer.surface);
        if !render_evaluate(.LOW, result, "unable to get surface present modes") || info.present_modes.count == 0 {
            return false;
        }
    }
    return true;
}

choose_swapchain_surface_format :: (info: *Swapchain_Support_Info) -> VkSurfaceFormatKHR, bool {
    for info.formats {
        if it.format == .R8G8B8A8_UNORM && it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
            return it, true;
        }
    }
    return info.formats[0], false;
}

choose_swapchain_present_mode :: (info: *Swapchain_Support_Info) -> VkPresentModeKHR, bool {
    // 'the queue' for any queued mode (FIFO, FIFO_RELAXED, MAILBOX) refers to the logical section
    // post-submission-for-presentation, and pre-draw-on-monitor. the oldest image in the queue
    // is moved into the draw section once the monitor enters its vblank period.
    //
    //
    //  acquire <------- available <---------
    //     v                                 |
    //   draw                                |
    //     v                                 |
    //   present --> queue (if exists) -> display
    //
    //
    // IMMEDIATE     : on present, immediately replace the image being drawn
    // FIFO          : on present, push image into the queue.
    // FIFO_RELAXED  : like FIFO, but if the program didn't submit an image for one whole vblank period, the next image replaces the image being drawn immediately.
    // MAILBOX       : on present, push image into the queue. if the queue is occupied by another image, move that image into the available pool and replace it with the new one.
    // return .FIFO_KHR, true; // vblank syncing with the most freedom and responsibility to manually frame-pace. probably better for low power devices than mailbox.
    return .IMMEDIATE_KHR, true;
}

choose_swapchain_extent :: (using info: *Swapchain_Support_Info) -> VkExtent2D, bool {
    extent := VkExtent2D.{
        clamp(render_target_width, capabilities.minImageExtent.width, capabilities.maxImageExtent.width),
        clamp(render_target_height, capabilities.minImageExtent.height, capabilities.maxImageExtent.height),
    };
    return extent, true;
}

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------- :render target

// for now, just drawing directly to the swapchain image because it's simpler
create_render_target :: () -> bool {
    return true;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------- :depth buffer

create_depth_buffer :: () -> bool {
    using context.renderer;

    if depth_buffer != null {
        heap := *gpu_heap_pool[depth_buffer.allocation.source_heap];
        // todo: free (using linear allocator rn)

        vkDestroyImageView(logical.obj, depth_buffer.view, null);
        vkDestroyImage(logical.obj, depth_buffer.obj, null);

        pool_return(*image_pool, depth_buffer.pool_index);
        depth_buffer = null;
    }

    render_check(.LOW, render_target_width > 0 && render_target_height > 0);

    depth_buffer = gpu_linear_allocate(.DEVICE_LOCAL_IMAGE, xx render_target_width, xx render_target_height, .DEPTH_STENCIL_ATTACHMENT_BIT | .SAMPLED_BIT, depth_buffer_format(physical.obj), create_color_view = false);

    view_info := image_view_create_info(depth_buffer.format, depth_buffer.obj, .DEPTH_BIT | .STENCIL_BIT);

    if !render_evaluate(.LOW, vkCreateImageView(logical.obj, *view_info, null, *depth_buffer.view), "failed to create the view of depth buffer") then return false;

    render_log(.MEDIUM, "created the depth buffer");
    return true;
}

depth_buffer_format :: (phys: VkPhysicalDevice) -> VkFormat {
    props: VkFormatProperties;
    vkGetPhysicalDeviceFormatProperties(phys, DEPTH_FORMAT, *props);
    if (props.optimalTilingFeatures & .DEPTH_STENCIL_ATTACHMENT_BIT) != 0 {
        return DEPTH_FORMAT;
    }
    return .UNDEFINED;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

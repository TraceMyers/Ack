#scope_file

using engine.renderer;
using engine.renderer.backend;

#scope_module

Swapchain_Support_Info :: struct {
    capabilities: VkSurfaceCapabilitiesKHR;
    formats: []VkSurfaceFormatKHR;
    present_modes: []VkPresentModeKHR;
}


Swapchain :: struct {
    obj: VkSwapchainKHR;
    extent: VkExtent2D;
    format: VkSurfaceFormatKHR;
    present_mode: VkPresentModeKHR;
    images: []*GPU_Image;
    image_rendered: [..]VkSemaphore;
    image_index: int;
}

create_swapchain_and_attachments :: () -> bool {
    auto_release_temp();

    vkDeviceWaitIdle(logical_device.obj);

    if window_width <= 0 || window_height <= 0 {
        return false;
    }

    reset_swapchain_images_and_attachments();
    old_swapchain_obj := swapchain.obj;

    if !render_evaluate(create_swapchain(old_swapchain_obj), "failed creating swapchain") then return false;
    if !render_evaluate(create_render_target(), "failed creating render target") then return false;
    if !render_evaluate(create_depth_buffer(), "failed creating depth buffer") then return false;

    should_recreate_swapchain = false;

    render_log("created swapchain and attachments", flags=.VERBOSE_ONLY);
    return true;
}

create_swapchain :: (old_swapchain_obj: VkSwapchainKHR) -> bool {
    support_info: Swapchain_Support_Info;

    if !render_evaluate(get_swapchain_support_info(physical_device.obj, *support_info,, temp), "unable to get swapchain support info for the selected physical device") then return false;

    if !render_evaluate(support_info.present_modes.count > 0 && support_info.formats.count > 0, "insufficient number or present modes or surface formats to create a swap chain") then return false;

    success: bool;
    swapchain.format, success       = choose_swapchain_surface_format(*support_info);
    if !render_evaluate(success, "failed to choose a swapchain surface format") then return false;

    swapchain.present_mode, success = choose_swapchain_present_mode(*support_info);
    if !render_evaluate(success, "failed to choose a swapchain present mode") then return false;

    swapchain.extent, success       = choose_swapchain_extent(*support_info);
    if !render_evaluate(success, "failed to choose an extent for the swapchain") then return false;

    max_image_count : u32 = ifx support_info.capabilities.maxImageCount == 0 
        then U32_MAX 
        else support_info.capabilities.maxImageCount;

    // preference = 2 images. double buffering even if we get more.
    image_count := min(max(support_info.capabilities.minImageCount, 2), max_image_count);

    create_info := VkSwapchainCreateInfoKHR.{
        surface = surface,
        minImageCount = image_count,
        imageFormat = swapchain.format.format,
        imageColorSpace = swapchain.format.colorSpace,
        imageExtent = swapchain.extent,
        // layers per image
        imageArrayLayers = 1,
        // render directly to the image
        imageUsage = .COLOR_ATTACHMENT_BIT /*| .STORAGE_BIT | .TRANSFER_DST_BIT*/,
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

    if !render_evaluate(vkCreateSwapchainKHR(logical_device.obj, *create_info, null, *swapchain.obj), "failed creating the swapchain") then return false;

    swapchain_image_objects, result := vkGetSwapchainImagesKHR(logical_device.obj, swapchain.obj,, temp);

    if !render_evaluate(success, "unable to get the array of swapchain images") then return false;

    if old_swapchain_obj != null {
        vkDestroySwapchainKHR(logical_device.obj, old_swapchain_obj, null);
    }

    swapchain.images = make_static_array(*GPU_Image, swapchain_image_objects.count);

    start_index := swapchain.image_rendered.count;
    end_index   := swapchain.images.count - 1;
    if swapchain.image_rendered.count < swapchain.images.count {
        semaphore_create_info := VkSemaphoreCreateInfo.{};
        array_resize(*swapchain.image_rendered, swapchain.images.count);
        for start_index..end_index {
            if !render_evaluate(vkCreateSemaphore(logical_device.obj, *semaphore_create_info, null, *swapchain.image_rendered[it]), "failed to create a swapchain image semaphore") {
                return false;
            }
        }
    } else if swapchain.image_rendered.count > swapchain.images.count {
        for start_index..end_index {
            vkDestroySemaphore(logical_device.obj, swapchain.image_rendered[it], null);
        }
        array_resize(*swapchain.image_rendered, swapchain.images.count);
    }

    for *image : swapchain.images {
        image.* = create_gpu_image({}, .NONE, xx swapchain.extent.width, xx swapchain.extent.height, create_info.imageUsage, swapchain.format.format, premade_image=swapchain_image_objects[it_index]);
        if !create_image_views(image.*, {.COLOR_BIT, .COLOR_ATTACHMENT_OPTIMAL}) {
            return false;
        }
    }

    render_log("created the swapchain. image count %", swapchain.images.count, flags=.VERBOSE_ONLY);
    return true;
}

reset_swapchain_images_and_attachments :: () {
    for *image : swapchain.images {
        destroy_gpu_image(image);
    }
    array_reset(*swapchain.images);
    destroy_gpu_image(*render_target);
    destroy_gpu_image(*depth_buffer);
}

choose_swapchain_surface_format :: (info: *Swapchain_Support_Info) -> VkSurfaceFormatKHR, bool {
    for info.formats {
        if it.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
            if it.format == .B8G8R8A8_SRGB || it.format == .R8G8B8A8_SRGB {
                return it, true;
            }
        }
    }
    return {}, false;
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
    return {xx window_width, xx window_height}, true;
}

// -----------------------------------------------------------------------------------
// -------------------------------------------------------------------- :render target

// todo: free old allocation / allocate only what is needed
create_render_target :: () -> bool {
    render_check(render_target == null);

    render_target = create_gpu_image(general_allocator, .DEVICE_LOCAL_IMAGE, xx swapchain.extent.width, xx swapchain.extent.height, .COLOR_ATTACHMENT_BIT | .SAMPLED_BIT | .STORAGE_BIT, .R16G16B16A16_SFLOAT);
    if !render_evaluate(create_image_views(render_target, {.COLOR_BIT, .COLOR_ATTACHMENT_OPTIMAL}), "failed to create the render target image view") {
        return false;
    }

    render_log("created the render target image", flags=.VERBOSE_ONLY);
    return true;
}

// -----------------------------------------------------------------------------------
// --------------------------------------------------------------------- :depth buffer

// todo: free old allocation / allocate only what is needed
create_depth_buffer :: () -> bool {
    render_check(depth_buffer == null);

    depth_buffer = create_gpu_image(general_allocator, .DEVICE_LOCAL_IMAGE, xx swapchain.extent.width, xx swapchain.extent.height, .DEPTH_STENCIL_ATTACHMENT_BIT | .SAMPLED_BIT, depth_buffer_format(physical_device.obj));
    if !render_evaluate(create_image_views(depth_buffer, {.DEPTH_BIT | .STENCIL_BIT, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL}, {.DEPTH_BIT, .DEPTH_STENCIL_READ_ONLY_OPTIMAL}), "failed to create one of the depth buffer image views") {
        return false;
    }

    render_log("created the depth buffer image", flags=.VERBOSE_ONLY);
    return true;
}

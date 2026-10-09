// todo: rename this file

image_create_info :: inline (format: VkFormat, usage_flags: VkImageUsageFlags, extent: VkExtent3D, mip_levels : u32 = 1, msaa_samples: VkSampleCountFlags = ._1_BIT /*1 = no msaa*/, tiling_format := VkImageTiling.OPTIMAL) -> VkImageCreateInfo {
    return VkImageCreateInfo.{
        imageType = ._2D,
        format = format,
        extent = extent,
        mipLevels = mip_levels,
        arrayLayers = 1,
        samples = msaa_samples,
        tiling = tiling_format,
        usage = usage_flags
    };
}

image_view_create_info :: inline (format: VkFormat, image: VkImage, aspect_flags: VkImageAspectFlags, mip_levels: u32 = 1) -> VkImageViewCreateInfo {
    return VkImageViewCreateInfo.{
        viewType = ._2D,
        image = image,
        format = format,
        subresourceRange = .{
            levelCount = mip_levels,
            layerCount = 1,
            aspectMask = aspect_flags
        }
    };
}

begin_command_buffer :: (frame: *Graphics_Frame) -> VkCommandBuffer, bool {
    cmd := frame.command_buffer;
    success := begin_command_buffer(cmd);
    return cmd, success;
}

begin_command_buffer :: (cmd: VkCommandBuffer) -> bool {
    if !render_evaluate(.LOW, vkResetCommandBuffer(cmd, 0), "failed to reset a command buffer") then return false;
    command_buffer_begin := VkCommandBufferBeginInfo.{flags = .ONE_TIME_SUBMIT_BIT};
    if !render_evaluate(.LOW, vkBeginCommandBuffer(cmd, *command_buffer_begin), "failed to begin a command buffer") then return false;
    return true;
}

acquire_next_swapchain_image :: (current_frame: *Graphics_Frame) -> u32, bool {
    using context.renderer;
    image_index: u32;
    if !render_evaluate(.LOW, vkAcquireNextImageKHR(logical.obj, swapchain.obj, NANOSECONDS_PER_SECOND, current_frame.image_available_semaphore, null, *image_index), "failed to wait to get an image from the swapchain") then return 0xffff_ffff, false;
    return image_index, true;
}

// todo: this image transitioning is a one-size-fits-all. look into how to do it with more params when optimization calls for it.
transition_image :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout, force_aspect_mask: VkImageAspectFlags = 0) {
    image_barrier := VkImageMemoryBarrier2.{
        srcStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        srcAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT,
        dstStageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
        dstAccessMask = VK_ACCESS_2_MEMORY_WRITE_BIT | VK_ACCESS_2_MEMORY_READ_BIT,
        oldLayout = old_layout,
        newLayout = new_layout,
        subresourceRange = .{
            aspectMask = ifx new_layout == .DEPTH_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_STENCIL_ATTACHMENT_OPTIMAL || new_layout == .DEPTH_STENCIL_READ_ONLY_OPTIMAL then .DEPTH_BIT | .STENCIL_BIT else .COLOR_BIT,
            baseMipLevel = 0,
            levelCount = VK_REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount = VK_REMAINING_ARRAY_LAYERS
        },
        image = image
    };

    if force_aspect_mask != 0 then {
        image_barrier.subresourceRange.aspectMask = force_aspect_mask;
    }

    dependency_info := VkDependencyInfo.{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers = *image_barrier
    };

    vkCmdPipelineBarrier2(cmd, *dependency_info);
}

begin_rendering :: (cmd: VkCommandBuffer, render_target_view: VkImageView, load_op:= VkAttachmentLoadOp.CLEAR) {
    using context.renderer;
    color_attachment := VkRenderingAttachmentInfo.{
        // sType:              VkStructureType = .RENDERING_ATTACHMENT_INFO;
        // pNext:              *void;
        imageView = render_target_view,
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        // resolveMode:        VkResolveModeFlagBits;
        // resolveImageView:   VkImageView;
        // resolveImageLayout: VkImageLayout;
        loadOp = load_op,
        storeOp = .STORE,
        clearValue = {color={_float32=clear_color.array}}
    };

    depth_attachment := VkRenderingAttachmentInfo.{
        imageView = depth_buffer.view,
        imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        loadOp = load_op,
        storeOp = .STORE,
        clearValue.depthStencil = .{0, 0}
    };

    stencil_attachment := VkRenderingAttachmentInfo.{
        imageView = depth_buffer.view,
        imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
        loadOp = load_op,
        storeOp = .STORE,
        clearValue.depthStencil = .{0, 0}
    };

    rendering_info := VkRenderingInfo.{
        // pNext:                *void;
        // flags:                VkRenderingFlags;
        renderArea = .{
            {0,0},
            {render_target_width, render_target_height},
        },
        layerCount = 1,
        // viewMask:             u32;
        colorAttachmentCount = 1,
        pColorAttachments = *color_attachment,
        pDepthAttachment = *depth_attachment,
        pStencilAttachment = *stencil_attachment,
    };

    viewport := VkViewport.{
        x = 0,
        y = 0,
        width = xx render_target_width,
        height = xx render_target_height,
        minDepth = MIN_DEPTH,
        maxDepth = MAX_DEPTH 
    };

    scissor := VkRect2D.{
        {0,0},
        {render_target_width, render_target_height}
    };

    vkCmdSetViewport(cmd, 0, 1, *viewport);
    vkCmdSetScissor(cmd, 0, 1, *scissor);
    vkCmdBeginRendering(cmd, *rendering_info);
}

semaphore_submit_info :: inline (stage_mask: VkPipelineStageFlags2, semaphore: VkSemaphore) -> VkSemaphoreSubmitInfo {
    return .{
        semaphore = semaphore,
        stageMask = stage_mask,
        // deviceIndex = 0,
        value = 1
    };
}

command_buffer_submit_info :: inline (cmd: VkCommandBuffer) -> VkCommandBufferSubmitInfo {
    return .{
        commandBuffer = cmd,
        // deviceMask = 0
    };
}

roll_submit_info :: inline (cmd: *VkCommandBufferSubmitInfo, wait_semaphore_info: *VkSemaphoreSubmitInfo, signal_semaphore_info: *VkSemaphoreSubmitInfo,) -> VkSubmitInfo2 {
    return .{
        waitSemaphoreInfoCount = ifx wait_semaphore_info == null then (0).(u32) else (1).(u32),
        pWaitSemaphoreInfos = wait_semaphore_info,
        signalSemaphoreInfoCount = ifx signal_semaphore_info == null then (0).(u32) else (1).(u32),
        pSignalSemaphoreInfos = signal_semaphore_info,
        commandBufferInfoCount = 1,
        pCommandBufferInfos = cmd
    };
}

make_vertex_descriptors :: ($T: Type, binding_index: u32 = 0) -> VkVertexInputBindingDescription, []VkVertexInputAttributeDescription {
    binding := VkVertexInputBindingDescription.{
        stride = size_of(T),
        inputRate = .VERTEX
    };

    struct_info := cast(*Type_Info_Struct)T;
    render_check(.LOW, struct_info.members.count > 0);

    attributes: [..]VkVertexInputAttributeDescription;
    array_reserve(*attributes, struct_info.members.count);

    for *struct_info.members {
        format := struct_member_vertex_input_binding_format(it);
        render_check(.LOW, format != .UNDEFINED);
        array_add(*attributes, .{
            location = xx it_index,
            binding = binding_index,
            format = format,
            offset = xx it.offset_in_bytes
        });
    }

    return binding, attributes;
}

struct_member_vertex_input_binding_format :: (info: *Type_Info_Struct_Member, depth := 0) -> VkFormat {
    render_check(.LOW, depth <= 1);
    format: VkFormat;
    if info.type.type == .FLOAT {
        format = ifx info.type.runtime_size == 4 then .R32_SFLOAT else .R64_SFLOAT;
    } else if info.type.type == .INTEGER {
        member_int_info := cast(*Type_Info_Integer)info.type;
        is_signed := member_int_info.signed;

        if info.type.runtime_size == {
        case 1;
            format = ifx is_signed then .R8_SINT else .R8_UINT;
        case 2;
            format = ifx is_signed then .R16_SINT else .R16_UINT;
        case 4;
            format = ifx is_signed then .R32_SINT else .R32_UINT;
        case 8;
            format = ifx is_signed then .R64_SINT else .R64_UINT;
        }
    } else if info.type.type == .STRUCT {
        render_check(.LOW, depth == 0);
        member_struct_info := cast(*Type_Info_Struct)info.type;
        render_check(.LOW, member_struct_info.members.count > 0);

        only_one_field_type := true;
        repeating_field_format: VkFormat;

        // look for placements
        unique_offsets: [..]s64;
        unique_offsets.allocator = temp;

        for *member_struct_info.members {
            find_success, _ := array_find(unique_offsets, it.offset_in_bytes);

            if find_success {
                continue;
            }

            if it.flags & .CONSTANT {
                continue;
            }

            field_format := struct_member_vertex_input_binding_format(it, depth + 1);

            // only structs with repeating fields of same type are allowed
            if repeating_field_format == .UNDEFINED {
                repeating_field_format = field_format;
            } else if repeating_field_format != field_format {
                only_one_field_type = false;
                break;
            }

            array_add(*unique_offsets, it.offset_in_bytes);
        }
        if only_one_field_type && repeating_field_format == .R32_SFLOAT {
            if unique_offsets.count == {
            case 2;
                format = .R32G32_SFLOAT;
            case 3;
                format = .R32G32B32_SFLOAT;
            case 4;
                format = .R32G32B32A32_SFLOAT;
            }
        }
    } else if info.type.type == .ARRAY {
        array_type_info := info.type.(*Type_Info_Array);
        render_check(.LOW, array_type_info.array_count > 0 && array_type_info.array_type == .FIXED);
        if array_type_info.element_type.type == {
        case .INTEGER;
            int_element_type := array_type_info.element_type.(*Type_Info_Integer);
            render_check(.LOW, int_element_type.runtime_size == 2);
            if array_type_info.array_count == {
            case 2;
                if int_element_type.signed {
                    return .R16G16_SINT;
                } else {
                    return .R16G16_UINT;
                }
            case 3;
                if int_element_type.signed {
                    return .R16G16B16_SINT;
                } else {
                    return .R16G16B16_UINT;
                }
            case 4;
                if int_element_type.signed {
                    return .R16G16B16A16_SINT;
                } else {
                    return .R16G16B16A16_UINT;
                }
            }
        case .FLOAT;
            float_element_type := cast(*Type_Info_Float) array_type_info.element_type;
            render_check(.LOW, float_element_type.runtime_size == 4);
            if array_type_info.array_count == {
            case 2;
                return .R32G32_SFLOAT;
            case 3;
                return .R32G32B32_SFLOAT;
            case 4;
                return .R32G32B32A32_SFLOAT;
            case;
                render_check(.LOW, false);
            }
        }
    }
    return format;
}

create_gpu_buffer_for_array :: (data: []$T, usage_flags: VkBufferUsageFlags, memory_flags: VkMemoryPropertyFlags) -> GPU_Buffer {
    return create_gpu_buffer(data.count * size_of(T), usage_flags, memory_flags);
}

copy_to_gpu_buffer :: (buffer: *GPU_Buffer, array: []$T, override_count := -1, command_buffer: VkCommandBuffer = null) {
    using context.renderer;
    heap := *gpu_heap_pool[buffer.source_heap];
    
    copy_count := ifx override_count != -1 then override_count else array.count;
    if copy_count == 0 {
        return;
    }

    copy_size := copy_count * size_of(T);
    render_check(.LOW, buffer.size >= xx copy_size);

    copy_to_gpu_buffer(buffer, cast(*void) array.data, cast(u32) copy_size, command_buffer=command_buffer);
}

copy_to_gpu_buffer :: (buffer: *GPU_Buffer, data: *void, override_size: u32 = 0xffff_ffff, additional_offset: u32 = 0, command_buffer: VkCommandBuffer = null) {
    using context.renderer;
    heap := *gpu_heap_pool[buffer.source_heap];

    copy_offset := buffer.source_heap_offset + xx additional_offset;
    copy_size   := min(buffer.size, override_size);

    if is_host_visible_type(heap.type) {
        render_check(.LOW, heap.is_valid);
        vbo     := heap.buffer; 
        offset  := copy_offset;
        size    := copy_size;

        if size == 0 {
            return;
        }

        p: *void;
        vkMapMemory(logical.obj, heap.memory, xx offset, xx size, 0, *p);
        memcpy(p, data, size);
        vkUnmapMemory(logical.obj, heap.memory);
    } else {
        staging_buffer := gpu_linear_allocate(.HOST_VISIBLE_BUFFER, copy_size, .TRANSFER_SRC_BIT, true);
        copy_to_gpu_buffer(*staging_buffer, data);
        staging_buffer_heap := *gpu_heap_pool[staging_buffer.source_heap];

        copy_region := VkBufferCopy.{
            srcOffset = xx staging_buffer.source_heap_offset,
            dstOffset = xx copy_offset,
            size      = xx copy_size
        };

        // Record copy on transfer queue
        cmd: VkCommandBuffer;
        if command_buffer == null {
            cmd = transfer_command_buffer;
            begin_command_buffer(cmd);
        } else {
            cmd = command_buffer;
        }

        vkCmdCopyBuffer(cmd, staging_buffer_heap.buffer, heap.buffer, 1, *copy_region);
        
        if command_buffer == null {
            immediate_submit_buffer_transfer_commands(heap, copy_offset, copy_size);
        } else {
            add_buffer_memory_barrier_for_transfer(*transfer_buffer_memory_barriers, heap, copy_offset, copy_size);
        }
    }
}

add_buffer_memory_barrier_for_transfer :: (collection: *Buffer_Memory_Barrier_Collection, heap: *GPU_Heap, region_offset: s32, region_size: u32) {
    access_flags: VkAccessFlags;

    if heap.type == {
    case .VERTEX_BUFFER;
        access_flags = .VERTEX_ATTRIBUTE_READ_BIT;
        collection.pipeline_stage_flags |= .VERTEX_INPUT_BIT;
    case .SKINNED_VERTEX_BUFFER;
        access_flags = .VERTEX_ATTRIBUTE_READ_BIT;
        collection.pipeline_stage_flags |= .VERTEX_INPUT_BIT;
    case .INDEX_BUFFER;
        access_flags = .INDEX_READ_BIT;
        collection.pipeline_stage_flags |= .VERTEX_INPUT_BIT;
    case;
        // todo: can tighten this with the buffer's stated usage
        access_flags = 
              .INDIRECT_COMMAND_READ_BIT
            | .UNIFORM_READ_BIT
            | .INPUT_ATTACHMENT_READ_BIT
            | .SHADER_READ_BIT
            | .SHADER_WRITE_BIT;
        collection.pipeline_stage_flags |=
              .DRAW_INDIRECT_BIT
            // | .GEOMETRY_SHADER_BIT
            // | .TESSELLATION_CONTROL_SHADER_BIT
            // | .TESSELLATION_EVALUATION_SHADER_BIT
            | .VERTEX_SHADER_BIT
            | .FRAGMENT_SHADER_BIT
            | .COMPUTE_SHADER_BIT;
    }

    array_add(*collection.barriers, {
        srcAccessMask = .TRANSFER_WRITE_BIT,
        dstAccessMask = access_flags,
        buffer        = heap.buffer,
        offset        = xx region_offset,
        size          = xx region_size
    });
}

immediate_submit_buffer_transfer_commands :: (heap: *GPU_Heap, buffer_offset: s32, buffer_size: u32) {
    using context.renderer;

    array_local: [1]VkBufferMemoryBarrier;
    collection: Buffer_Memory_Barrier_Collection;
    collection.barriers.data = array_local.data;
    collection.barriers.allocated = 1;
    add_buffer_memory_barrier_for_transfer(*collection, heap, buffer_offset, buffer_size);
    vkCmdPipelineBarrier(transfer_command_buffer, .TRANSFER_BIT, collection.pipeline_stage_flags, 0, 0, null, 1, collection.barriers.data, 0, null);
    submit_commands(transfer_command_buffer, transfer_fence, transfer_queue);
}

add_buffer_transfer_barrier :: (cmd: VkCommandBuffer) {
    using context.renderer;

    collection := transfer_buffer_memory_barriers;
    if collection.barriers.count == 0 {
        render_log(.HIGH, "tried to submit empty transfer barrier collection");
        return;
    }
    vkCmdPipelineBarrier(cmd, .TRANSFER_BIT, collection.pipeline_stage_flags, 0, 0, null, xx collection.barriers.count, collection.barriers.data, 0, null);
    reset_memory_barrier_collection(*transfer_buffer_memory_barriers);
}

reset_memory_barrier_collection :: (collection: *Buffer_Memory_Barrier_Collection) {
    array_reset_keeping_memory(*collection.barriers);
    collection.pipeline_stage_flags = 0;
}

add_gpu_image_for_sampling :: (path: string, sampler: VkSampler) -> *GPU_Image {
    using context.renderer;

    width, height, channels_in_file: s32;
    desired_channels : s32 = 4;
    image_data := stbi_load(temp_c_string(path), *width, *height, *channels_in_file, desired_channels); 
    defer stbi_image_free(image_data);

    use_image_data := image_data;

    render_check(.LOW, channels_in_file == 4 || channels_in_file == 3, "tried to load image with channel count %", channels_in_file);
    render_check(.LOW, width > 0 && height > 0);

    image := add_gpu_image_for_sampling(xx use_image_data, width, height, sampler);

    return image;
}

add_gpu_image_for_sampling :: (data: *Color4b, width: s32, height: s32, sampler: VkSampler) -> *GPU_Image {
    using context.renderer;

    // create staging resources (cpu visible)
    image_size     := width * height * 4;
    staging_buffer := gpu_linear_allocate(.HOST_VISIBLE_BUFFER, image_size, .TRANSFER_SRC_BIT, true);
    copy_to_gpu_buffer(*staging_buffer, data);

    image := gpu_linear_allocate(.DEVICE_LOCAL_IMAGE, width, height, .TRANSFER_DST_BIT | .SAMPLED_BIT);

    // Record copy on transfer queue
    cmd := transfer_command_buffer;
    begin_command_buffer(cmd);

    transition_image(cmd, image.obj, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
    copy_buffer_to_image(cmd, image, staging_buffer);

    // Transition image layout for shader usage
    transition_image(cmd, image.obj, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);

    submit_commands(cmd, transfer_fence, transfer_queue);

    image_info := VkDescriptorImageInfo.{
        sampler = sampler,
        imageView = image.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL
    };
    write := VkWriteDescriptorSet.{
        dstSet = textures_descriptor_set,
        dstBinding = 0,
        dstArrayElement = xx image.pool_index,
        descriptorCount = 1,
        descriptorType = .COMBINED_IMAGE_SAMPLER,
        pImageInfo = *image_info
    };
    vkUpdateDescriptorSets(logical.obj, 1, *write, 0, null);

    return image;   
}

copy_buffer_to_image :: (cmd: VkCommandBuffer, dst: *GPU_Image, src: GPU_Buffer) {
    using context.renderer;

    buffer_heap := *gpu_heap_pool[src.source_heap];

    copy_region := VkBufferImageCopy.{
        bufferOffset = xx src.source_heap_offset,
        imageSubresource = {
            aspectMask = .COLOR_BIT,
            layerCount = dst.layer_count,
        },
        imageExtent = dst.extent
    };

    vkCmdCopyBufferToImage(cmd, buffer_heap.buffer, dst.obj, .TRANSFER_DST_OPTIMAL, 1, *copy_region);
}

create_gpu_uniform_buffer :: (pool: VkDescriptorPool, set: *VkDescriptorSet, buffer: *GPU_Buffer, size: int, temp := false, heap_type := GPU_Heap_Type.DEVICE_LOCAL_BUFFER) {
    internal_create_ubo_or_ssbo(pool, set, buffer, size, heap_type, temp, true);
}

create_gpu_storage_buffer :: (pool: VkDescriptorPool, set: *VkDescriptorSet, buffer: *GPU_Buffer, size: int, temp := false, heap_type := GPU_Heap_Type.DEVICE_LOCAL_BUFFER) {
    internal_create_ubo_or_ssbo(pool, set, buffer, size, heap_type, temp, false);
}

internal_create_ubo_or_ssbo :: (pool: VkDescriptorPool, set: *VkDescriptorSet, buffer: *GPU_Buffer, size: int, heap_type: GPU_Heap_Type, temp: bool, uniform: bool) {
    using context.renderer;

    if heap_type == {
    case .DEVICE_LOCAL_BUFFER; // good
    case .HOST_VISIBLE_BUFFER; // good
    case;
        render_check(.LOW, false, "invalid heap type passed into create_gpu_storage_buffer: %", heap_type);
    }
    
    layout := ifx uniform then uniform_buffer_descriptor_set_layout else storage_buffer_descriptor_set_layout;
    set.* = allocate_descriptor_set(pool, layout);
    buffer.* = gpu_linear_allocate(heap_type, size, ifx uniform then .UNIFORM_BUFFER_BIT else .STORAGE_BUFFER_BIT, temp);
    vk_buffer := gpu_heap_pool[buffer.source_heap].buffer;

    info := VkDescriptorBufferInfo.{
        buffer = vk_buffer,
        offset = xx buffer.source_heap_offset,
        range  = xx size
    };

    write := VkWriteDescriptorSet.{
        dstSet          = set.*,
        dstBinding      = 0,
        descriptorCount = 1,
        descriptorType  = ifx uniform then .UNIFORM_BUFFER else .STORAGE_BUFFER,
        pBufferInfo     = *info
    };

    vkUpdateDescriptorSets(logical.obj, 1, *write, 0, null);
}

bleh :: (set: *VkDescriptorSet, buffers: []*GPU_Buffer) {

    // vkUpdateDescriptorSets(
}

create_gpu_vertex_buffer :: (buffer: *GPU_Buffer, vertices: []Static_Mesh_Vertex) {
    buffer.* = gpu_linear_allocate(.VERTEX_BUFFER, size_of(Static_Mesh_Vertex) * vertices.count, .VERTEX_BUFFER_BIT);
    copy_to_gpu_buffer(buffer, vertices);
}

create_gpu_skinned_vertex_buffer :: (buffer: *GPU_Buffer, vertices: []Skeletal_Mesh_Vertex) {
    buffer.* = gpu_linear_allocate(.SKINNED_VERTEX_BUFFER, size_of(Skeletal_Mesh_Vertex) * vertices.count, .VERTEX_BUFFER_BIT);
    copy_to_gpu_buffer(buffer, vertices);
}

create_gpu_index_buffer :: (buffer: *GPU_Buffer, indices: []u32) {
    buffer.* = gpu_linear_allocate(.INDEX_BUFFER, size_of(u32) * indices.count, .INDEX_BUFFER_BIT);
    copy_to_gpu_buffer(buffer, indices);
}

bind_vertex_buffer :: (cmd: VkCommandBuffer, gpu_buffer: GPU_Buffer) {
    heap   := *context.renderer.gpu_heap_pool[gpu_buffer.source_heap];
    vk_buffer := heap.buffer;
    offset_u64 : u64 = xx gpu_buffer.source_heap_offset;
    vkCmdBindVertexBuffers(cmd, 0, 1, *vk_buffer, *offset_u64);
}

create_gpu_buffer :: (size: int, usage_flags: VkBufferUsageFlags, memory_flags: VkMemoryPropertyFlags) -> GPU_Buffer {
    using context.renderer;

    buffer := GPU_Buffer.{
        size = xx size,
        usage_flags = usage_flags,
        memory_flags = memory_flags
    };

    create_info := VkBufferCreateInfo.{
        size  = buffer.size,
        usage = usage_flags,
        sharingMode = .EXCLUSIVE
    };

    allocate_gpu_buffer(*buffer, create_info, memory_flags);

    return buffer;
}

get_vbo :: () -> VkBuffer {
    vb_allocator := *context.renderer.linear_allocators[GPU_Heap_Type.VERTEX_BUFFER];
    if vb_allocator.heaps.count == 0 {
        return null;
    }
    heap := *context.renderer.gpu_heap_pool[vb_allocator.heaps[0]];
    return heap.buffer;
}

get_skinned_vbo :: () -> VkBuffer {
    vb_allocator := *context.renderer.linear_allocators[GPU_Heap_Type.SKINNED_VERTEX_BUFFER];
    if vb_allocator.heaps.count == 0 {
        return null;
    }
    heap := *context.renderer.gpu_heap_pool[vb_allocator.heaps[0]];
    return heap.buffer;
}

get_ibo :: () -> VkBuffer {
    vb_allocator := *context.renderer.linear_allocators[GPU_Heap_Type.INDEX_BUFFER];
    if vb_allocator.heaps.count == 0 {
        return null;
    }
    heap := *context.renderer.gpu_heap_pool[vb_allocator.heaps[0]];
    return heap.buffer;
}

create_gpu_image :: (width: s32, height: s32, usage_flags: VkImageUsageFlags, memory_flags: VkMemoryPropertyFlags, format := VkFormat.R8G8B8A8_UNORM, mip_count: u32 = 1, layer_count: u32 = 1) ->  *GPU_Image {
    using context.renderer;

    image_index := pool_acquire(*image_pool);
    render_check(.LOW, image_index < max_image_count);
    image := *image_pool[image_index];
    image.pool_index = xx image_index;

    image.extent = {xx width, xx height, 1};
    image.format = format;
    image.usage = usage_flags;
    image.mip_count = mip_count;
    image.layer_count = layer_count;

    create_info := VkImageCreateInfo.{
        imageType = ._2D,
        format = texture.format,
        extent = texture.extent,
        mipLevels = mip_count,
        // here, can stack images together, (like maybe albedo, metallic, roughness, etc.)
        // maybe it's not good for that example, though since I don't think we usually mip
        // pbr-type textures?
        arrayLayers = layer_count,
        samples = ._1_BIT, // MSAA
        tiling = .OPTIMAL,
        usage = usage_flags,
        sharingMode = .EXCLUSIVE
    };

    allocate_gpu_image(image, create_info, memory_flags);

    return image;
}

heap_type_and_memory_index :: inline (heap_type: GPU_Heap_Type) -> VkMemoryPropertyFlags, u32 {
    using context.renderer;
    if is_buffer_type(heap_type) {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical.properties.host_visible_buffer_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical.properties.device_local_buffer_memory_index;
        }
    } else {
        if is_host_visible_type(heap_type) {
            return .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT, physical.properties.host_visible_image_memory_index;
        } else {
            return .DEVICE_LOCAL_BIT, physical.properties.device_local_image_memory_index;
        }
    }
    return 0, 0xffff_ffff;
}

allocate_gpu_heap :: (size: int, type: GPU_Heap_Type, allocator: GPU_Allocator, buffer_usage: VkBufferUsageFlags = 0) -> s16 {
    using context.renderer;

    _, memory_index := heap_type_and_memory_index(type);
    allocate_info := VkMemoryAllocateInfo.{
        allocationSize = xx size,
        memoryTypeIndex = memory_index
    };

    memory: VkDeviceMemory;

    if !render_evaluate(.LOW, vkAllocateMemory(logical.obj, *allocate_info, null, *memory), "failed to allocate a heap of type % from allocator % size %", type, allocator, size) {
        return -1;
    }

    buffer: VkBuffer;
    buffer_min_alignment: u32;

    if is_buffer_type(type) {
        create_info := VkBufferCreateInfo.{
            size        = xx size,
            usage       = buffer_usage,
            sharingMode = .EXCLUSIVE
        };

        memory_requirements: VkMemoryRequirements;
        vkCreateBuffer(logical.obj, *create_info, null, *buffer);
        vkGetBufferMemoryRequirements(logical.obj, buffer, *memory_requirements);
        buffer_min_alignment = xx memory_requirements.alignment;
        vkBindBufferMemory(logical.obj, buffer, memory, 0);
    }

    heap_index := cast(u16) pool_borrow(*gpu_heap_pool);
    heap := *gpu_heap_pool[heap_index];

    heap.* = GPU_Heap.{
        memory = memory,
        size                 = size,
        type                 = type,
        allocator            = allocator,
        buffer               = buffer,
        buffer_usage         = buffer_usage,
        buffer_min_alignment = buffer_min_alignment,
        is_valid             = true
    };

    return xx heap_index;
}

// todo: textures should work the same way as this, where you allocate, remove or update
// makes for a nice interface for updating textures cpu-side arbitrarily

allocate_material :: (mat: *Material) -> s32 {
    using context.renderer;
    new_mat_index := pool_borrow(*materials);
    render_check(.LOW, new_mat_index != -1);
    update_material(xx new_mat_index, mat);
    return xx new_mat_index;
}

update_material :: (index: s32, mat: *Material) {
    using context.renderer;
    pool_mat := *materials[index];
    pool_mat.* = mat.*;
    gpu_mat := convert_material_to_gpu_format(mat);
    copy_size   : u32 = xx size_of(GPU_Material);
    copy_offset : u32 = xx (index * size_of(GPU_Material));
    copy_to_gpu_buffer(*materials_storage_buffer, *gpu_mat, copy_size, copy_offset);
}

convert_material_to_gpu_format :: inline (mat: *Material) -> GPU_Material {
    gpu_mat: GPU_Material;

    gpu_mat.albedo_factor    = mat.albedo_factor;
    gpu_mat.emissive_factor  = mat.emissive_factor;
    gpu_mat.metallic_factor  = mat.metallic_factor;
    gpu_mat.roughness_factor = mat.roughness_factor;

    gpu_mat.alpha_cutoff = mat.discard_alpha_cutoff_if_masked_alpha;

    gpu_mat.albedo_uv    = mat.albedo_uv;
    gpu_mat.metallic_uv  = mat.metallic_uv;
    gpu_mat.roughness_uv = mat.roughness_uv;
    gpu_mat.normal_uv    = mat.normal_uv;
    gpu_mat.occlusion_uv = mat.occlusion_uv;
    gpu_mat.emissive_uv  = mat.emissive_uv;

    gpu_mat.albedo_tex   = mat.albedo_texture.global_buffer;
    gpu_mat.normal_tex   = mat.normal_texture.global_buffer;
    gpu_mat.emissive_tex = mat.emissive_texture.global_buffer;
    gpu_mat.orm_tex      = mat.orm_texture.global_buffer;

    return gpu_mat;
}

usage_alignment :: inline (usage_flags: VkBufferUsageFlags) -> int {
    using context.renderer;
    align: u32 = 0;
    if (usage_flags & (.TRANSFER_SRC_BIT | .TRANSFER_DST_BIT | .STORAGE_BUFFER_BIT)) != 0 {
        // note: I was told by an AI that meeting the requirements for storage buffers
        // almost certainly meets the requirements for optimal transfer.
        align = max(align, cast(u32) physical.properties.storage_buffer_alignment);
    }
    if (usage_flags & (.UNIFORM_TEXEL_BUFFER_BIT | .STORAGE_TEXEL_BUFFER_BIT)) != 0 {
        align = max(align, cast(u32) physical.properties.texel_buffer_alignment);
    }
    if (usage_flags & .UNIFORM_BUFFER_BIT) != 0 {
        align = max(align, cast(u32) physical.properties.uniform_buffer_alignment);
    }
    if (usage_flags & .VERTEX_BUFFER_BIT) != 0 {
        align = max(align, 8);
    }
    if (usage_flags & (.INDEX_BUFFER_BIT | .INDIRECT_BUFFER_BIT)) != 0 {
        align = max(align, 4);
    }
    return align;
}

get_or_add_sampler :: (min_filter: Texture_Filter, mag_filter: Texture_Filter, horizontal_wrap: Texture_Wrap, vertical_wrap: Texture_Wrap) -> VkSampler {
    using context.renderer;
    // this procedure has to change if this isn't true, because we're turning these into a simple hash.
    render_check(.LOW, size_of(Texture_Filter) == 1 && size_of(Texture_Wrap) == 1);

    key := 
          ((cast(u32) min_filter)     << 24) 
        | ((cast(u32) mag_filter)     << 16) 
        | ((cast(u32) horizontal_wrap) << 8) 
        | ((cast(u32) vertical_wrap)   << 0);

    sampler, just_added := find_or_add(*sampler_table, key);
    if !just_added {
        return sampler.*;
    }

    create_info := VkSamplerCreateInfo.{
        minFilter  = ifx min_filter == .NEAREST then .NEAREST else .LINEAR,
        magFilter  = ifx mag_filter == .NEAREST then .NEAREST else .LINEAR,
        mipmapMode = ifx min_filter == .NEAREST then .NEAREST else .LINEAR,
    };

    // translating same name to different enum type
    if horizontal_wrap == {
    case .CLAMP_TO_EDGE;
        create_info.addressModeU = .CLAMP_TO_EDGE;
    case .MIRRORED_REPEAT;
        create_info.addressModeU = .MIRRORED_REPEAT;
    case .REPEAT;
        create_info.addressModeU = .REPEAT;
    }

    // translating same name to different enum type
    if vertical_wrap == {
    case .CLAMP_TO_EDGE;
        create_info.addressModeV = .CLAMP_TO_EDGE;
    case .MIRRORED_REPEAT;
        create_info.addressModeV = .MIRRORED_REPEAT;
    case .REPEAT;
        create_info.addressModeV = .REPEAT;
    }

    // not using because I don't have 3d uv maps
    create_info.addressModeW = create_info.addressModeW;

    render_evaluate(.LOW, vkCreateSampler(logical.obj, *create_info, null, sampler), "failed to create sampler with min filter %, mag filter %, hz wrap %, vt wrap %", min_filter, mag_filter, horizontal_wrap, vertical_wrap);

    return sampler.*;
}

allocate_gpu_image :: (image: *GPU_Image, create_info: VkImageCreateInfo, memory_flags: VkMemoryPropertyFlags) {
    using context.renderer;
    memory_requirements: VkMemoryRequirements;
    vkCreateImage(logical.obj, *create_info, null, *image.obj);
    vkGetImageMemoryRequirements(logical.obj, image.obj, *memory_requirements);
    allocate_gpu_memory(*image.memory, memory_flags, memory_requirements);
    vkBindImageMemory(logical.obj, image.obj, image.memory, 0);   
}

allocate_gpu_buffer :: (buffer: *GPU_Buffer, create_info: VkBufferCreateInfo, memory_flags: VkMemoryPropertyFlags) {
    using context.renderer;
    memory_requirements: VkMemoryRequirements;
    vkCreateBuffer(logical.obj, *create_info, null, *buffer.obj);
    vkGetBufferMemoryRequirements(logical.obj, buffer.obj, *memory_requirements);
    allocate_gpu_memory(*buffer.memory, memory_flags, memory_requirements);
    vkBindBufferMemory(logical.obj, buffer.obj, buffer.memory, 0);   
}

allocate_gpu_memory :: (memory: *VkDeviceMemory, flags: VkMemoryPropertyFlags, requirements: VkMemoryRequirements) {
    using context.renderer;
    memory_properties: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(physical.obj, *memory_properties);
    memory_type_index := find_index_of_memory_type(requirements.memoryTypeBits, flags, *memory_properties);
    allocate_info := VkMemoryAllocateInfo.{
        allocationSize = requirements.size,
        memoryTypeIndex = memory_type_index
    };
    vkAllocateMemory(logical.obj, *allocate_info, null, memory);
}

find_index_of_memory_type :: (can_use_type_bits: u32, must_have_props: VkMemoryPropertyFlags, memory_properties: *VkPhysicalDeviceMemoryProperties) -> u32 {
    for 0..memory_properties.memoryTypeCount-1 {
        type_props := memory_properties.memoryTypes[it].propertyFlags;
        type_has_props := (type_props & must_have_props) == must_have_props;
        type_can_be_used := (cast(u32) (1 << it) & can_use_type_bits) != 0;
        if type_has_props && type_can_be_used {
            return cast(u32) it;
        }
    }
    return INVALID_MEMORY_TYPE_INDEX;
}

submit_commands :: (cmd: VkCommandBuffer, fence: VkFence, queue: VkQueue, wait_semaphore: *VkSemaphoreSubmitInfo = null, signal_semaphore: *VkSemaphoreSubmitInfo = null) -> bool {
    using context.renderer;

    if !render_evaluate(.LOW, vkEndCommandBuffer(cmd), "failed to end a command buffer") then return false;

    cmd_submit_info := command_buffer_submit_info(cmd);
    submit_info     := roll_submit_info(*cmd_submit_info, wait_semaphore, signal_semaphore); 

    if !render_evaluate(.LOW, vkQueueSubmit2(queue, 1, *submit_info, fence), "failed to submit commands to a queue") then return false;

    if !render_evaluate(.LOW, vkWaitForFences(logical.obj, 1, *fence, VK_TRUE, NANOSECONDS_PER_SECOND), "failed to wait for a fence") then return false;

    if !render_evaluate(.LOW, vkResetFences(logical.obj, 1, *fence), "failed to reset a fence") then return false;

    return true;
}

create_descriptor_pool :: (pool: *VkDescriptorPool, max_sets: u32, ratios: []Descriptor_Pool_Ratio) -> bool {
    using context.renderer;
    auto_release_temp();

    sizes := make_dynamic_array(VkDescriptorPoolSize, ratios.count,,temp);    
    descriptor_set_count : u32 = 0; 

    // all ratios can come in at whatever sum. you might think they should sum to ~1, but
    // that creates unnecessary mental overhead on the input side. the important thing is that
    // the numbers make sense in proportion to each other.
    ratio_sum := 0.0;
    for ratios {
        ratio_sum += it.ratio;
    }
    inv_ratio_sum := 1.0 / ratio_sum;

    for ratios {
        count := round(it.ratio * inv_ratio_sum * max_sets, u32);
        count = min(max_sets - descriptor_set_count, count);
        if count > 0 {
            descriptor_set_count += count;
            array_add(*sizes, {type=it.type, descriptorCount=count});
        }
    }

    create_info := VkDescriptorPoolCreateInfo.{
        maxSets = descriptor_set_count,
        poolSizeCount = xx sizes.count,
        pPoolSizes = sizes.data
    };

    return render_evaluate(.LOW, vkCreateDescriptorPool(logical.obj, *create_info, null, pool), "failed creating descriptor pool");
}

// this is inflexible and probably not great going forward due to forcing the stages to be uniform
build_descriptor_set_layout :: (layout_builder: []VkDescriptorSetLayoutBinding, shader_stages: VkShaderStageFlags = 0, p_next: *void = null, flags: VkDescriptorSetLayoutCreateFlags = 0) -> VkDescriptorSetLayout {
    using context.renderer;

    for *layout_builder {
        it.stageFlags |= shader_stages;
    }

    create_info := VkDescriptorSetLayoutCreateInfo.{
        pBindings = layout_builder.data,
        bindingCount = xx layout_builder.count,
        flags = flags,
        pNext = p_next
    };

    set: VkDescriptorSetLayout;
    render_evaluate(.LOW, vkCreateDescriptorSetLayout(logical.obj, *create_info, null, *set), "failed to create a descriptor set layout");

    return set;
}

allocate_descriptor_set :: (pool: VkDescriptorPool, layout: VkDescriptorSetLayout, p_next: *void = null) -> VkDescriptorSet {
    alloc_info := VkDescriptorSetAllocateInfo.{
        descriptorPool = pool,
        descriptorSetCount = 1,
        pSetLayouts = *layout,
        pNext = p_next
    };
    descriptor_set: VkDescriptorSet;
    render_evaluate(.LOW, vkAllocateDescriptorSets(context.renderer.logical.obj, *alloc_info, *descriptor_set), "failed to allocate a descriptor set");
    return descriptor_set;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

// the renderer's only descriptor set: a bindless array of sampled textures. shaders reach every
// buffer through its device address (see Push_Constants), so buffers need no descriptors.
//
// the array grows at runtime. the set layout's upper bound is the device limit, which costs
// nothing. the set itself is allocated with a smaller variable count, and when that fills up a
// bigger set is allocated, every live texture is rewritten into it, and the old pool is destroyed
// once the frames that might still use it have finished. a texture's slot (its index in the
// shaders' array) never changes while the texture is alive.

Texture_Descriptors :: struct {
    layout:   VkDescriptorSetLayout;
    pool:     VkDescriptorPool;
    set:      VkDescriptorSet;
    capacity: u32;

    // indexed by slot. image is null for unused slots. kept so descriptors can be rewritten on growth.
    entries:    [..]Texture_Descriptor;
    free_slots: [..]s32;
}

Texture_Descriptor :: struct {
    image:   *GPU_Image;
    sampler: VkSampler;
}

create_texture_descriptors :: () -> bool {
    using engine.renderer;

    binding := VkDescriptorSetLayoutBinding.{
        binding         = 0,
        descriptorType  = .COMBINED_IMAGE_SAMPLER,
        descriptorCount = physical_device.properties.max_texture_descriptors,
        stageFlags      = .ALL
    };
    binding_flags: VkDescriptorBindingFlags = .PARTIALLY_BOUND_BIT | .UPDATE_AFTER_BIND_BIT | .VARIABLE_DESCRIPTOR_COUNT_BIT;
    flags_info := VkDescriptorSetLayoutBindingFlagsCreateInfo.{
        bindingCount  = 1,
        pBindingFlags = *binding_flags
    };
    layout_info := VkDescriptorSetLayoutCreateInfo.{
        pNext        = *flags_info,
        flags        = .UPDATE_AFTER_BIND_POOL_BIT,
        bindingCount = 1,
        pBindings    = *binding
    };
    if !render_evaluate(vkCreateDescriptorSetLayout(logical_device.obj, *layout_info, null, *textures.layout), "failed to create the texture descriptor set layout") then return false;

    initial_capacity := min(max(creation_settings.initial_texture_capacity, 1), physical_device.properties.max_texture_descriptors);
    if !allocate_texture_set(initial_capacity) then return false;

    render_log("created texture descriptors. capacity %, max %", textures.capacity, physical_device.properties.max_texture_descriptors, flags=.VERBOSE_ONLY);
    return true;
}

// makes image sampleable by shaders as textures[slot]. returns the slot.
// the image needs a view whose expected layout is SHADER_READ_ONLY_OPTIMAL.
register_sampled_image :: (image: *GPU_Image, sampler: VkSampler) -> s32 {
    using engine.renderer;
    render_check(image.texture_slot == -1, "image is already registered as a texture");

    slot: s32;
    if textures.free_slots.count > 0 {
        slot = pop(*textures.free_slots);
    } else {
        slot = xx textures.entries.count;
        array_add(*textures.entries, .{});
    }

    textures.entries[slot] = .{image, sampler};
    image.texture_slot = slot;

    if cast(u32) slot >= textures.capacity {
        max_count := physical_device.properties.max_texture_descriptors;
        render_check(cast(u32) slot < max_count, "texture count exceeds the device limit of %", max_count);
        // growing rewrites every live texture, including this one
        allocate_texture_set(min(max(textures.capacity * 2, cast(u32) slot + 1), max_count));
    } else {
        write_texture_descriptor(slot);
    }

    return slot;
}

// the slot is reused only after the frames that might still sample it have finished
release_texture_slot :: (image: *GPU_Image) {
    using engine.renderer;
    if image.texture_slot == -1 {
        return;
    }
    textures.entries[image.texture_slot] = .{};
    defer_destroy(.{type = .TEXTURE_SLOT, texture_slot = image.texture_slot});
    image.texture_slot = -1;
}

get_or_add_sampler :: (min_filter: Texture_Filter, mag_filter: Texture_Filter, horizontal_wrap: Texture_Wrap, vertical_wrap: Texture_Wrap) -> VkSampler {
    using engine.renderer;
    // this procedure has to change if this isn't true, because we're turning these into a simple hash.
    render_check(size_of(Texture_Filter) == 1 && size_of(Texture_Wrap) == 1);

    key :=
          ((cast(u32) min_filter)      << 24)
        | ((cast(u32) mag_filter)      << 16)
        | ((cast(u32) horizontal_wrap) << 8)
        | ((cast(u32) vertical_wrap)   << 0);

    sampler, just_added := find_or_add(*sampler_table, key);
    if !just_added {
        return sampler.*;
    }

    to_address_mode :: (wrap: Texture_Wrap) -> VkSamplerAddressMode {
        if wrap == {
        case .CLAMP_TO_EDGE;   return .CLAMP_TO_EDGE;
        case .MIRRORED_REPEAT; return .MIRRORED_REPEAT;
        }
        return .REPEAT;
    }

    create_info := VkSamplerCreateInfo.{
        minFilter    = ifx min_filter == .NEAREST then .NEAREST else .LINEAR,
        magFilter    = ifx mag_filter == .NEAREST then .NEAREST else .LINEAR,
        mipmapMode   = ifx min_filter == .NEAREST then .NEAREST else .LINEAR,
        addressModeU = to_address_mode(horizontal_wrap),
        addressModeV = to_address_mode(vertical_wrap),
        addressModeW = .REPEAT,
        maxLod       = VK_LOD_CLAMP_NONE
    };

    render_evaluate(vkCreateSampler(logical_device.obj, *create_info, null, sampler), "failed to create sampler with min filter %, mag filter %, hz wrap %, vt wrap %", min_filter, mag_filter, horizontal_wrap, vertical_wrap);

    return sampler.*;
}

#scope_file

// allocates a set with room for capacity textures, writes every live texture into it, and makes
// it the current set. the previous pool is destroyed once frames in flight are done with it.
allocate_texture_set :: (capacity: u32) -> bool {
    using engine.renderer;

    pool_size := VkDescriptorPoolSize.{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = capacity};
    pool_info := VkDescriptorPoolCreateInfo.{
        flags         = .UPDATE_AFTER_BIND_BIT,
        maxSets       = 1,
        poolSizeCount = 1,
        pPoolSizes    = *pool_size
    };
    pool: VkDescriptorPool;
    if !render_evaluate(vkCreateDescriptorPool(logical_device.obj, *pool_info, null, *pool), "failed to create a texture descriptor pool with capacity %", capacity) then return false;

    variable_count := capacity;
    count_info := VkDescriptorSetVariableDescriptorCountAllocateInfo.{
        descriptorSetCount = 1,
        pDescriptorCounts  = *variable_count
    };
    alloc_info := VkDescriptorSetAllocateInfo.{
        pNext              = *count_info,
        descriptorPool     = pool,
        descriptorSetCount = 1,
        pSetLayouts        = *textures.layout
    };
    set: VkDescriptorSet;
    if !render_evaluate(vkAllocateDescriptorSets(logical_device.obj, *alloc_info, *set), "failed to allocate a texture descriptor set with capacity %", capacity) {
        vkDestroyDescriptorPool(logical_device.obj, pool, null);
        return false;
    }

    if textures.pool != null {
        defer_destroy(.{type = .DESCRIPTOR_POOL, descriptor_pool = textures.pool});
        render_log("texture capacity grew from % to %", textures.capacity, capacity, flags=.VERBOSE_ONLY);
    }

    textures.pool     = pool;
    textures.set      = set;
    textures.capacity = capacity;

    for textures.entries {
        if it.image != null {
            write_texture_descriptor(xx it_index);
        }
    }
    return true;
}

write_texture_descriptor :: (slot: s32) {
    using engine.renderer;
    entry := textures.entries[slot];

    view := get_image_view(entry.image, .SHADER_READ_ONLY_OPTIMAL);
    render_check(view != null, "a texture needs an image view with expected layout SHADER_READ_ONLY_OPTIMAL");

    image_info := VkDescriptorImageInfo.{
        sampler     = entry.sampler,
        imageView   = view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL
    };
    write := VkWriteDescriptorSet.{
        dstSet          = textures.set,
        dstBinding      = 0,
        dstArrayElement = xx slot,
        descriptorCount = 1,
        descriptorType  = .COMBINED_IMAGE_SAMPLER,
        pImageInfo      = *image_info
    };
    vkUpdateDescriptorSets(logical_device.obj, 1, *write, 0, null);
}

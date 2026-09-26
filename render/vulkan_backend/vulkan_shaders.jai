get_shader :: (filename: string) -> VkShaderModule {
    using context.renderer;
    auto_release_temp();

    shader, just_added  := find_or_add(*shader_table, filename);
    if just_added {
        shader.* = create_shader_module_from_file(filename);
    }
    return shader.*;
}

create_shader_module_from_file :: (filename: string) -> VkShaderModule {
    using context.renderer;
    auto_release_temp();

    file_path := tprint("shaders/spirv/%.spv", filename);
    spirv, success := read_entire_file(file_path, true,, temp);
    if !render_check(.LOW, success, "failed to load shader binary for %. if this is a default TeRM/Render shader module, try setting 'copy_shader_data_into_working_directory' = true in the render init options.", file_path) then return null;

    create_info := VkShaderModuleCreateInfo.{
        codeSize = xx spirv.count,
        pCode = xx spirv.data
    };

    module: VkShaderModule = ---;
    if !render_check(.LOW, vkCreateShaderModule(logical.obj, *create_info, null, *module), "failed to create a shader module with file at path %", file_path) then return null;

    return module;
}


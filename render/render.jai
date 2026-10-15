#if GRAPHICS_API == {
case "VULKAN";
    #load "vulkan/vulkan.jai";
}

Renderer :: struct {
    using frontend: Renderer_Frontend;
    // backend isn't opaque because it doesn't seem necessary. frontend and backend are
    // separated so that it's clear what is managed by the user program and what 
    // is typically managed by the renderer.
    backend: Renderer_Backend;
    // copied into renderer post-creation. provided for read-only reference. modifying it 
    // doesn't do anything.
    creation_settings: Renderer_Creation_Settings;
}

Renderer_Creation_Settings :: struct {
    config: Renderer_Config;

    application_name    := "your graphics application";
    application_version := Version.{0, 1, 0};
    engine_name         := "Ack!";
    engine_version      := ACK_VERSION;

    max_textures                : u32 = 4096;
    // max_gpu_heaps              : u32 = 512; // this doesn't really make sense as an option...
    max_materials               : u32 = 4096;
    max_static_mesh_instances   : u32 = 32_768;
    max_skeletal_mesh_instances : u32 = 16_384;

    // only need to do once/initially, or after in-engine shaders have been updated
    copy_shaders_from_engine := true;
    // only need to do when shaders are updated (todo: file watching)
    compile_shaders          := true;
    use_dev_gui              := true;
}

// values provided during creation that are also configurable afterward.
Renderer_Config :: struct {
    msaa_samples : u32 = 1;
    render_dimensions_override: Vector2i;
}

Renderer_View_Mode :: enum u8 {
    LIT;
    UNLIT;
    DEPTH;
}

Renderer_Frontend :: struct {
    clear_color := COLOR4F_WHITE;
    view_mode: Renderer_View_Mode;
    depth_view_mode_max_distance := 200.0;

    // todo: define user's role in adding to/building the dev gui, then provide controls.
    // dev_gui_callback: *void;

    // copied here at the beginning of per-frame update. meant to be a read-only reference.
    // modifying it has no consequences.
    using last_per_frame_input: Renderer_Per_Frame_Input;
}

Renderer_Per_Frame_Input :: struct {
    delta_time: float32;
    unscaled_delta_time: float32;
    global_shader_time: float32;
    global_shader_delta_time: float32;

    camera_info: Camera_Info;
    camera_position: Vector3;
    camera_orientation: Quaternion;
}

Renderer_Per_Frame_Output :: struct {
    rendered_frame_count: s32;
}

Shader_Compile_Info :: struct {
    input_path: string;
    output_path: string;
    stage: string;
}

// todo: bring init options here and find stuff that should be in the init options
create_renderer :: (settings: Renderer_Creation_Settings) -> bool {
    render_check(window != null);
    render_check(engine.renderer == null);

    engine.renderer = New(Renderer);
    {
        using engine.renderer;
        creation_settings = settings;
        backend.window_dimensions.x = window_width;
        backend.window_dimensions.y = window_height;
    }

    render_log(
#string HERE
initializing renderer for application...

    %, version %
    made with %, version %
    using % graphics, version %
HERE,
        settings.application_name, 
        renderer_version_string(settings.application_version),
        ifx settings.engine_name == "" then "?" else settings.engine_name, 
        renderer_version_string(settings.engine_version),
        engine.renderer.backend.API,
        renderer_version_string(engine.renderer.backend.API_VERSION)
    );

    if settings.copy_shaders_from_engine && !copy_shaders_from_engine() {
        return false;
    }
    if settings.compile_shaders && !compile_shaders() {
        return false;
    }

    backend_create_renderer(engine.renderer);

    return true;
}

destroy_renderer :: () {
    // do things...

}

update_renderer :: () {

}

copy_shaders_from_engine :: () -> success: bool {
    // spiel := "render init options have 'populate_shader_data_in_working_directory' set to true";

    working_directory := get_working_directory();
    defer set_working_directory(working_directory);

    renderer_path := ack_renderer_path();

    src_path := path_parse_ext(renderer_path);
    if !move_down_directory(*src_path, "shaders") {
        // todo: error
        return false;
    }
    src_path_str := path_to_string_ext(*src_path);

    dst_path := path_parse_ext(engine.project_info.shaders_path);
    if !move_down_directories(*dst_path, engine.creation_settings.project_shader_directory) {
        // todo: error
        return false;
    }
    dst_path_str := path_to_string_ext(*dst_path);
    
    copy_success := copy_directory(src_path_str, dst_path_str,, temp);
    if !copy_success {
        // todo: error
        return false;
    }

    return true;
}

compile_shaders :: () -> success: bool {
    using engine;

    shaders_path := parse_path_ext(project_settings.shaders_path);
    if !file_exists(shaders_path) {
        // todo: error
        return false;
    }

    shaders_path_str := path_to_string_ext(*shaders_path);
    scope_set_working_directory(shaders_path_str);

    if !file_exists("glslc.exe") {
        // todo: error
        return false;
    }
    if !file_exists("src") {
        // todo: warning
        return false;
    }

    move_down_directory(*shaders_path, "spirv", false);
    spirv_path_str := path_to_string_ext(*shaders_path);
    make_directory_if_it_does_not_exist(spirv_path_str);

    Shader_Files :: struct {
        header: string;
        shaders: [..]Shader_Compile_Info;
    }
    
    to_output_path :: (short_name: string) -> string {
        new_name := copy_string(short_name);
        for < *c : new_name {
            if c.* == #char "." {
                c.* = #char "_";
                break;
            }
        }
        return sprint("spirv/%.spv", new_name);
    }

    visitor :: (info: *File_Visit_Info, files: *Shader_Files) {
        if info.short_name == "header.glsl" {
            files.header = copy_string(info.full_name,, temp);
        } else {
            input_path := copy_string(info.full_name,, temp);
            output_path := to_output_path(info.short_name,, temp);

            if ends_with(info.short_name, "vert") {
                array_add(*files.shaders, {input_path, output_path, "vert"});
            } else if ends_with(info.short_name, "frag") {
                array_add(*files.shaders, {input_path, output_path, "frag"});
            } else if ends_with(info.short_name, "compute") {
                array_add(*files.shaders, {input_path, output_path, "compute"});
            }
        }
    }

    files: Shader_Files;
    files.shaders.allocator = temp;
    array_reserve(*files.shaders, 4096);

    visit_files("src", recursive=true, *files, visitor);

    header_text, success := read_entire_file(files.header,, temp);
    if !success {
        render_error("failed loading header file %", files.header);
        return false;
    }

    for shader : files.shaders {
        compile_shader(header_text, shader);
    }

    file_delete("temp.glsl");

    return true;
}

compile_shader :: (header_text: string, shader: Shader_Compile_Info) -> bool {
    auto_release_temp();

    render_log("shader compilation: % -> %", shader.input_path, shader.output_path, flags=.VERBOSE_ONLY);

    shader_text, read_success := read_entire_file(shader.input_path, true,, temp);
    if !read_success {
        render_error("failed reading input file.");
        return false;
    }

    // find paste directives written into the shader code.
    // they will be formatted like "## some_file_name", alone on a line.
    // this finds 'some_file_name.glsl' in the src folder and pastes the contents.
    shader_text_rebuilder: String_Builder;
    shader_text_rebuilder.allocator = temp;

    for :per_line shader_text {
        trimmed := trim(it);
        if begins_with(trimmed, "##") {
            found_space, left, right := split_from_left(trimmed, " ");
            filename := tprint("src/%.glsl", right);
            lines_to_paste, success := read_entire_file(filename,, temp);
            render_check(success);
            print(*shader_text_rebuilder, "\n%\n", lines_to_paste);
        } else {
            print(*shader_text_rebuilder, tprint("%\n", it));
        }
    }

    shader_text = builder_to_string(*shader_text_rebuilder,, temp);

    combined_shader_text := tprint("%\n%", header_text, shader_text);
    write_success := write_entire_file("temp.glsl", combined_shader_text);
    if !write_success {
        render_error("failed writing temp file.");
        return false;
    }

    stage := tprint("-fshader-stage=%", shader.stage);
    result := run_command("glslc.exe", stage, "temp.glsl", "-o", shader.output_path);
    if result.exit_code != 0 {
        render_error("failed compilation. glslc exit code: %.", result.exit_code);
        return false;
    }

    return true;
}

ack_renderer_path :: () -> string {
    return get_final_path(#filepath,, temp);
}

#scope_module

Renderer_Backend_Base :: struct {
    DEFAULT_GPU_HEAP_SIZE :: 64 * 1024 * 1024;

    config: Renderer_Config;

    init_success: bool;
    queueing_draw_commands: bool; // was: in_the_middle_of_rendering

    gpu_heaps:  Pool(GPU_Heap);
    textures:   Pool(GPU_Image);
    materials:  Pool(Material);
    meshes:     Managed_Meshes;

    physical_device: Physical_Device;
    logical_device:  Logical_Device;
}

NANOSECONDS_PER_SECOND      :: 1_000_000_000;
NANOSECONDS_PER_MILLISECOND :: 1_000_000;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

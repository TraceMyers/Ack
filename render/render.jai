#if GRAPHICS_API == {
case "VULKAN";
    #load "vulkan/vulkan.jai";
}

#load "draw.jai";

Renderer :: struct {
    // modify data here and the renderer will react on update.
    config: Renderer_Config;

    // todo: define user's role in adding to/building the dev gui, then provide controls.
    // dev_gui_callback: *void;

    // copied here at the beginning of per-frame update. modifying it has no consequences to
    // rendering except under race conditions.
    using last_per_frame_input: Renderer_Per_Frame_Input;

    // immediate draws (debug lines, one-off meshes) submitted for the next frame. see draw.jai.
    draws: Frame_Draws;

    // backend isn't opaque because it doesn't seem necessary. backend is just separated so 
    // that it's clear what is typically managed & accessed by the user program and what 
    // is typically managed by the renderer.
    using backend: Renderer_Backend;

    // copied into renderer post-creation. provided for read-only reference. modifying it 
    // doesn't do anything.
    creation_settings: Renderer_Creation_Settings;
}

Renderer_Creation_Settings :: struct {
    // config = configurable after creation. the renderer has a copy of this data which
    // can be modified *there*. modifying renderer's creation_settings does nothing.
    // leaving it unedited keeps a clean record of the creation settings, including config.
    config: Renderer_Config;

    application_name    := "your graphics application";
    application_version := Version.{0, 1, 0};
    engine_name         := "Ack!";
    engine_version      := ACK_VERSION;

    // the texture array grows past this when needed
    initial_texture_capacity    : u32 = 1024;
    max_materials               : u32 = 4096;
    max_static_mesh_instances   : u32 = 32_768;
    max_skeletal_mesh_instances : u32 = 16_384;

    // only need to do once/initially, or after in-engine shaders have been updated
    copy_shaders_from_engine                    := true;
    // only need to do when shaders are updated (todo: file watching)
    compile_shaders                             := true;
    // use the getrect-based developer ui (may want to turn off for shipping builds)
    use_dev_gui                                 := true;
    // if false, main thread: physics -> pre renderer -> update renderer -> post renderer
    // if true,  main thread: pre renderer + -> pre clock
    //                                     v
    //         render thread:              + -> update renderer -> post render
    // if post render proc exists, the main thread will stall just before calling pre render,
    // until post render is complete. if not, then it stalls until the renderer update is complete
    run_renderer_on_its_own_thread              := true;
    // if run_renderer_on_its_own_thread is true, setting this to true shifts the above to:
    // post physics + -> pre clock
    //              v
    //              + -> pre renderer -> update renderer -> post renderer
    // same main thread stalling behavior as above, except the stall happens at post physics 
    // rather than pre render.
    call_pre_renderer_update_from_render_thread := false;
}

// values provided during creation that are also configurable afterward.
Renderer_Config :: struct {
    clear_color := COLOR4F_WHITE;
    view_mode: Renderer_View_Mode;
    depth_view_mode_max_distance := 200.0;
    msaa_samples : u32 = 1;
    render_dimensions_override: Vector2i;
}

Renderer_View_Mode :: enum u8 {
    LIT;
    UNLIT;
    DEPTH;
}

Renderer_Per_Frame_Input :: struct {
    // the times are set from engine.clock at the start of each renderer update
    delta_time: float32;
    unscaled_delta_time: float32;
    global_shader_time: float32;
    global_shader_delta_time: float32;

    camera_info: Camera_Info;
    camera_position: Vector3;
    camera_orientation: Quaternion;
    light_direction := Vector3.{0, 0, -1};
}

// layers draw in this order: GAME, then LAYER_5 down to LAYER_1. the depth buffer is cleared
// before each layer after GAME, so a layer always draws over everything in the layers before it,
// while keeping full depth precision within itself.
Draw_Layer :: enum u8 {
    GAME;
    LAYER_1; // drawn last, in front of everything
    LAYER_2;
    LAYER_3;
    LAYER_4;
    LAYER_5;
}

DRAW_LAYER_COUNT :: #run enum_highest_value(Draw_Layer) + 1;
DRAW_LAYER_ORDER :: Draw_Layer.[.GAME, .LAYER_5, .LAYER_4, .LAYER_3, .LAYER_2, .LAYER_1];

Renderer_Per_Frame_Output :: struct {
    rendered_frame_count: u64;
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
    engine.renderer.creation_settings = settings;
    engine.renderer.config = settings.config;

    render_log(
#string HERE
initializing renderer for application...

    %, version %
    made with % version %
    using % graphics version %
HERE,
        settings.application_name, 
        make_version_string(settings.application_version),
        ifx settings.engine_name == "" then "?" else settings.engine_name, 
        make_version_string(settings.engine_version),
        engine.renderer.backend.API,
        make_version_string(engine.renderer.backend.API_VERSION),
        user_flags = xx Ack_Log_Flags.ADD_NEWLINE
    );

    if settings.copy_shaders_from_engine && !copy_shaders_from_engine() {
        render_error("renderer creation failed");
        return false;
    }

    if settings.compile_shaders && !compile_shaders() {
        render_error("renderer creation failed");
        return false;
    }

    if !backend_create_renderer() {
        render_error("renderer creation failed");
        return false;
    }
    
    render_log("renderer creation success");
    return true;
}

destroy_renderer :: () {
    // do things...

}

update_renderer :: () {
    if engine.renderer == null || !engine.renderer.init_success {
        return;
    }

    using engine.renderer;
    delta_time               = engine.clock.delta_time;
    unscaled_delta_time      = engine.clock.unscaled_delta_time;
    global_shader_time       = xx engine.clock.time;
    global_shader_delta_time = engine.clock.delta_time;

    render_frame();
    reset_frame_draws();
}

copy_shaders_from_engine :: () -> success: bool {
    render_log("copying shaders from engine", flags=.VERBOSE_ONLY);

    report_copy_error :: (error_fmt: string, args: ..Any) #expand {
        render_error("failed to copy shaders from the engine to the project: %", tprint(error_fmt, ..args));
        `return false;
    }

    working_directory := get_working_directory();
    defer set_working_directory(working_directory);

    renderer_path := ack_renderer_path();

    src_path := parse_path_ext(renderer_path);
    if !move_down_directory(*src_path, "shaders") {
        report_copy_error("no shaders directory in engine (renderer path=%)", src_path);
        return false;
    }
    src_path_str := path_to_string_ext(*src_path);

    dst_path := parse_path_ext(engine.project_info.project_path);
    dst_path_str := path_to_string_ext(*dst_path);
    if !move_down_directories(*dst_path, engine.project_info.shaders_path) {
        dst_path_str = path_to_string_ext(*dst_path);
        if !make_directory_if_it_does_not_exist(dst_path_str) {
            report_copy_error("failed to make or find project shader path %", dst_path_str);
            return false;
        }
    }

    dst_path_str = path_to_string_ext(*dst_path);
    render_log("copy source = %, dest = %", src_path_str, dst_path_str, flags=.VERY_VERBOSE_ONLY);
    
    copy_success := copy_directory(src_path_str, dst_path_str,, temp);
    if !copy_success {
        report_copy_error("failed to copy shaders from % to %", src_path_str, dst_path_str);
        return false;
    }

    render_log("success copying shaders from engine", flags=.VERBOSE_ONLY);
    return true;
}

compile_shaders :: () -> success: bool {
    using engine;
    render_log("compiling shaders", flags=.VERBOSE_ONLY);

    // shaders are loaded from project_path/shaders_path, so compile them there too
    shaders_path := parse_path_ext(project_info.project_path);
    move_down_directories(*shaders_path, project_info.shaders_path, false);
    shaders_path_str := path_to_string_ext(*shaders_path);
    if !file_exists(shaders_path_str) {
        render_error("did not find path %", shaders_path_str);
        return false;
    }

    scope_set_working_directory(shaders_path_str);

    if !file_exists("glslc.exe") {
        render_error("did not find glslc.exe at %", shaders_path_str);
        return false;
    }
    if !file_exists("src") {
        render_error("did not find 'src' directory at %", shaders_path_str);
        return false;
    }

    // relative to the shaders directory, which is now the working directory
    if !make_directory_if_it_does_not_exist("spirv") {
        render_error("failed to make the spirv directory at %", shaders_path_str);
        return false;
    }

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
        return tprint("spirv/%.spv", new_name);
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
        // todo: invoke glslc.exe once
        if !compile_shader(header_text, shader) {
            return false;
        }
    }

    file_delete("temp.glsl");

    render_log("finished compiling shaders", flags=.VERBOSE_ONLY);
    return true;
}

compile_shader :: (header_text: string, shader: Shader_Compile_Info) -> bool {
    auto_release_temp();

    render_log("shader compilation: % -> %", shader.input_path, shader.output_path, flags=.VERY_VERBOSE_ONLY);

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
    init_success: bool;
    currently_updating_renderer: bool; // was: in_the_middle_of_rendering

    rendered_frame_count: u64;

    // allocate from linear_allocator or general_allocator. heap_allocator is what they allocate
    // whole heaps from.
    heap_allocator:    GPU_Allocator;
    linear_allocator:  GPU_Linear_Allocator;
    general_allocator: GPU_General_Allocator;

    materials:     Pool(Material);
    meshes:        Managed_Meshes;

}

NANOSECONDS_PER_SECOND      :: 1_000_000_000;
NANOSECONDS_PER_MILLISECOND :: 1_000_000;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

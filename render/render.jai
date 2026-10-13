#if GRAPHICS_API == {
case "VULKAN";
    #load "vulkan/vulkan.jai";
}

Renderer :: struct {
    API :: GRAPHICS_API;
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

    max_texture_count : u32 = 4096;

    copy_shader_data_into_working_directory := true;
    use_dev_gui                             := true;
}

// values provided during creation that are also configurable afterward.
Renderer_Config :: struct {
    msaa_samples : u32 = 1;
    render_dimensions_override: Vector2i;
}

Renderer_View_Mode :: enum u8 {
    LIT;
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

// todo: bring init options here and find stuff that should be in the init options
create_renderer :: (settings: Renderer_Creation_Settings) -> bool {
    engine_check(window != null);
    engine_check(engine.renderer == null);

    engine.renderer = New(Renderer);
    engine.renderer.creation_settings = settings;

    return true;
}

destroy_renderer :: () {
    // do things...

    // if renderer == context.renderer {
    //     context.renderer = null;
    // }
}

update_renderer :: () {

}

// todo: track render target dimensions once the frontend is back.
update_render_dimensions :: (width: u32, height: u32) {
    // the window is created before the renderer, so the first call has nothing to notify
    if engine.renderer != null {
        engine.renderer.backend.should_recreate_swapchain = true;
    }
}

ack_renderer_path :: () -> string {
    return get_final_path(#filepath,, temp);
}

#scope_module

Renderer_Backend_Base :: struct {
    config: Renderer_Config;
    init_success: bool;
}

NANOSECONDS_PER_SECOND      :: 1_000_000_000;
NANOSECONDS_PER_MILLISECOND :: 1_000_000;

run_init_proc :: (proc: Code, caller_loc := #caller_location) #expand {
    proc_name :: #run code_string(proc);
    render_log("calling %", proc_name, flags=.VERBOSE_ONLY);
    if !engine.renderer.backend.init_success {
        return;
    }
    #insert #run tprint("engine.renderer.backend.init_success = `%();", proc_name);
    if !engine.renderer.backend.init_success {
        render_log("init failure. exiting.", loc=caller_loc, flags=.VERBOSE_ONLY);
    }
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

#module_parameters()(
    GRAPHICS_API := "VULKAN",

    user_types: $I/interface Type_Provider_Default = Type_Provider_Default,

    ENABLE_LOGGING           := true,
    LOG_VERTICAL_MODE        := true,

    // you need to pass integer values for VERBOSITY and VALIDATION levels, 
    // because the enums will not be compiled at import time.
    // 0 = NORMAL, 1 = VERBOSE/HIGH, 2=VERY_VERBOSE/VERY_HIGH
    
    USER_VERBOSITY_LEVELS:   []u8 = .[0],
    GENERAL_VERBOSITY_LEVEL  := Ack_Log_Level.NORMAL,
    PHYSICS_VERBOSITY_LEVEL  := Ack_Log_Level.NORMAL,
    RENDER_VERBOSITY_LEVEL   := Ack_Log_Level.NORMAL,

    ENABLE_VALIDATION        := true,
    USER_VALIDATION_LEVEL    := Ack_Validation_Level.NORMAL,
    GENERAL_VALIDATION_LEVEL := Ack_Validation_Level.NORMAL,
    PHYSICS_VALIDATION_LEVEL := Ack_Validation_Level.NORMAL,
    RENDER_VALIDATION_LEVEL  := Ack_Validation_Level.NORMAL,

    ADD_TEXT_ENCODINGS:  []string = string.[], // see 'how to add text encodings' section
    ADD_ENCODE_FAILURES: []string = string.[], // see 'how to add text encodings' section
    ADD_CONTROL_MODES:   []string = string.[],

    ENCODE_TEXT_MAX_WRITE_SIZE := 8,
    PHYSICS_DELTA_TIME                := 1.0 / 100.0,
    MIN_PHYSICS_BODY_SPEED_ALONG_AXIS := 0.000001,
    FLIP_VECTOR_2D_Y_AXIS             := false // origin at upper left? flip it
) {
    Collision_Channels_Default :: enum_flags u32 { DEFAULT; };
    Raycast_Channels_Default :: enum_flags u32 { DEFAULT; };
    Extra_Body_Data_Default :: struct {};
    Entity_ID_Type_Default :: u64;

    Type_Provider_Default :: struct {
        entity_id_type      :: Entity_ID_Type_Default;
        extra_body_data     :: Extra_Body_Data_Default;
        collision_channels  :: Collision_Channels_Default;
        raycast_channels    :: Raycast_Channels_Default;
        entity_to_id_proc   :: (ent: *Ack_Entity) -> Entity_ID_Type_Default { return 0; };
        id_to_entity_proc   :: (id: Entity_ID_Type_Default) -> *Ack_Entity { return null; };
        entity_id_to_u64    :: (id: Entity_ID_Type_Default) -> u64 { return id; };
        u64_to_entity_id    :: (id: u64) -> Entity_ID_Type_Default { return id; };
        null_entity_id      : u64 : 0;
    }

    Ack_Validation_Level :: enum u8 {
        NORMAL    :: 0;
        HIGH      :: 1;
        VERY_HIGH :: 2;
    }

    // mirroring jai's Log_Level so that it can be used in module params
    Ack_Log_Level :: enum u8 {
        NORMAL       :: 0;
        VERBOSE      :: 1;
        VERY_VERBOSE :: 2;
    }
}

ACK_VERSION :: Version.{0,1,0};

// -----------------------------------------------------------------------------------------------

engine: Game_Engine;

// this can be called instead of doing manual init
game_engine_init :: (
    initialize_project: bool, // only need to set this to true once, or when engine is updated
    engine_settings         := Engine_Settings.{},
    window_settings         := Window_Creation_Settings.{}, 
    renderer_settings       := Renderer_Creation_Settings.{}, 
    physical_world_settings := Physical_World_Creation_Settings.{}, 
    use_ack_logger          := true,
    log_options             := Log_Options.{},
    project_info            := Project_Info.{}
) -> bool {
    engine_check(!engine.initialized);
    engine_check(engine.physical_world == null);
    engine_check(engine.renderer == null);

    copy_engine_files_to_project = initialize_project;

    engine = {settings=engine_settings, initialized=false};

    if use_ack_logger {
        context.logger = ack_log;
        global_log_options = log_options;
    }

    engine.project_info = project_info;
    if engine.project_info.project_path == "" {
        engine.project_info.project_path = get_final_path(get_working_directory());
    } else {
        engine.project_info.project_path = get_final_path(engine.project_info.project_path);
    }

    build_path_success: bool;
    engine.project_info.shaders_path, build_path_success = build_path_string(engine.project_info.project_path, engine.project_info.shaders_path, carve_path=initialize_project);
    if !build_path_success {
        engine_error("unable to find or make shaders path %", engine.project_info.shaders_path);
    }

    engine.project_info.fonts_path,   build_path_success = build_path_string(engine.project_info.project_path, engine.project_info.fonts_path,   carve_path=initialize_project);
    if !build_path_success {
        engine_error("unable to find or make fonts path %", engine.project_info.fonts_path);
    }

    egi_try :: #bake_arguments engine_run_or_return_failure(flags=.VERBOSE_ONLY);

    egi_try(create_window(window_settings));
    egi_try(create_renderer(renderer_settings));
    egi_try(create_physical_world(physical_world_settings));

    engine.initialized = true;
    return true;
}

// you can use this instead of making your own loop.
game_engine_loop :: () {
    if !engine.initialized {
        engine_log("engine uninitialized. exiting loop");
        return;
    }

    init_clock(*engine.clock);

    while !engine.settings.quit {
        reset_temporary_storage();
        update_game_system(engine.settings.input_update);
        // if the window is already closed, then we need to quit right away
        if engine.settings.quit then break;
        update_game_system(engine.settings.physics_update);
        update_game_system(engine.settings.render_update);
        update_game_system(engine.settings.clock_update);
    }
}

ack_engine_path :: () -> string {
    return get_final_path(#filepath,, temp);
}

#if ENABLE_VALIDATION {
    check :: (condition: bool, fmt := "", args: ..Any, $level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) #expand #no_debug {
        if level <= USER_VALIDATION_LEVEL {
            if !condition && assert_helper(fmt, ..args, caller_loc) then debug_break();
        }
    }
} else {
    check :: (#discard condition: bool, #discard fmt := "", #discard args: ..Any, $level := Ack_Validation_Level.NORMAL, #discard caller_loc := #caller_location) #expand {}
}

// like check, but always evaluates the condition, even if asserts are disabled. also returns
// the evaluated condition, so it can be used in if statements.
evaluate :: (condition: bool, fmt := "", args: ..Any, $level := Ack_Validation_Level.NORMAL, caller_loc := #caller_location) -> bool #expand #no_debug {
    #if ENABLE_VALIDATION {
        if level <= USER_VALIDATION_LEVEL {
            if !condition && assert_helper(fmt, ..args, caller_loc) then debug_break();
        }
    }
    return condition;
}

// -----------------------------------------------------------------------------------------------

Game_Engine :: struct {
    clock: Loop_Clock;
    settings: Engine_Settings;
    project_info: Project_Info;
    input: Game_Input;
    renderer: *Renderer;
    physical_world: *Physical_World;
    initialized: bool;
}

All_Game_System_Updates :: struct {
    // before and after reading system input and calling input bindings
    input_update   := Game_System_Update.{update=update_input};
    // before and after calcucs
    physics_update := Game_System_Update.{update=update_physics};
    // before and after rendering
    render_update  := Game_System_Update.{update=update_renderer};
    // before and after updating engine.clock
    clock_update   := Game_System_Update.{update=update_clock};
}

Engine_Settings :: struct {
    // updatable during loop
    quit: bool;
    auto_sync_frame_time := true;
    using update_procedures: All_Game_System_Updates;
}

Project_Info :: struct {
    // path to the project. is set to current working directory in game_init if not explicitly passed
    project_path: string;
    // all other paths are project path-relative
    shaders_path := "shaders";
    fonts_path   := "fonts";
}

Game_System_Update :: struct {
    pre_update: ();
    update: ();
    post_update: ();
}

update_game_system :: (system: Game_System_Update) {
    if system.pre_update  != null then system.pre_update();
    if system.update      != null then system.update();
    if system.post_update != null then system.post_update();
}

update_clock :: () {
    update_clock(*engine.clock);
}

// -----------------------------------------------------------------------------------------------

// multi-file loads
#load "mesh/mesh.jai";
// #load "navmesh/navmesh.jai";
#load "physics/physics.jai";
#load "render/render.jai";
#load "containers/containers.jai";
#load "allocation/allocation.jai";
#load "math/math.jai";
#load "input/input.jai";
// #load "animation/animation.jai";

// single-file loads
#load "entity.jai";
#load "array.jai";
#load "camera.jai";
#load "color.jai";
#load "component.jai";
#load "compression.jai";
#load "config.jai";
#load "encode_text.jai";
#load "file.jai";
#load "flag_array.jai";
#load "json.jai";
#load "lock.jai";
#load "log.jai";
#load "metaprogram.jai";
#load "number_interpretation.jai";
#load "optional.jai";
#load "random.jai";
#load "serialize.jai";
#load "statistics.jai";
#load "string.jai";
#load "system.jai";
#load "testing.jai";
#load "misc.jai";
#load "context_additions.jai";
#load "engine_logging_and_validation.jai";
#load "window.jai";
#load "clock.jai";
#load "curves.jai";

// base imports
#import "Basic";
#import "Math";
#import "Machine_X64";
#import "Compiler";
#import "String";
#import "Hash";
#import "Hash_Table";
#import "Sort";
#import "md5";
#import "Random";
Program_Print :: #import "Program_Print";
#import "Bit_Operations";
#import "Atomics";
#import "File";
#import "File_Utilities";
Window_Creation :: #import "Window_Creation";
#import "Flat_Pool";
#import "stb_image";
#import "Process";
#import "Input";
#import "Gamepad";

#scope_module

copy_engine_files_to_project: bool;

maybe_copy_files_to_project :: (project_path: string, engine_relative_path: string, initial_log: string, system := enum { ENGINE; PHYSICS; RENDER; }.ENGINE) -> bool {
    if copy_engine_files_to_project {
        report_copy_error :: (error_fmt: string, args: ..Any) #expand {
            error_proc := ifx `system == .ENGINE then engine_error
                else ifx `system == .PHYSICS then physics_error
                else render_error;
            error_proc("failed to copy fonts from the engine to the project: %", tprint(error_fmt, ..args));
            `return false;
        }

        log_proc := ifx system == .ENGINE then engine_log
            else ifx system == .PHYSICS then physics_log
            else render_log;

        log_proc(initial_log, flags=.VERBOSE_ONLY);

        src_path, src_success := build_path_string(ack_engine_path(), engine_relative_path);
        if !src_success {
            report_copy_error("unable to find engine source path %", engine_relative_path);
        }

        log_proc("copy source = %, dest = %", src_path, project_path, flags=.VERY_VERBOSE_ONLY);
        
        copy_success := copy_directory(src_path, project_path,, temp);
        if !copy_success {
            report_copy_error("failed to copy fonts from % to %", src_path, project_path);
        }

        log_proc("success copying files from %", engine_relative_path, flags=.VERBOSE_ONLY);
    }

    return true;
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

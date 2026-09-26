#module_parameters()(
    GRAPHICS_API := "VULKAN",
    ENCODE_TEXT_MAX_WRITE_SIZE := 8,
    ADD_TEXT_ENCODINGS: []string = string.[], // see 'how to add text encodings' section
    ADD_ENCODE_FAILURES: []string = string.[], // see 'how to add text encodings' section
    PHYSICS_DELTA_TIME := 1.0 / 100.0,
    MIN_PHYSICS_BODY_SPEED_ALONG_AXIS := 0.000001,
    FLIP_VECTOR_2D_Y_AXIS := false, // origin at upper left? flip it
    LOG_VERTICAL_MODE := true,
    USER_VERBOSITY_LEVEL     := 1,
    USER_VALIDATION_LEVEL    := 1,
    GENERAL_VALIDATION_LEVEL := 2,
    PHYSICS_VALIDATION_LEVEL := 2,
    RENDER_VALIDATION_LEVEL  := 2,
    user_types: $I/interface Type_Provider_Default = Type_Provider_Default
) {
    Entity_ID_Default :: u64;
    Collision_Channels_Default :: enum_flags u32 { DEFAULT; };
    Raycast_Channels_Default :: enum_flags u32 { DEFAULT; };
    Extra_Body_Data_Default :: struct {};
    Entity_Type_Default :: struct { id: u64; };

    Type_Provider_Default :: struct {
        entity_id_type      :: Entity_ID_Default;
        extra_body_data     :: Extra_Body_Data_Default;
        collision_channels  :: Collision_Channels_Default;
        raycast_channels    :: Raycast_Channels_Default;
        entity_to_id_proc   :: (ent: *Entity_Type_Default) -> u64 { return 0; };
        id_to_entity_proc   :: (id: u64) -> *Entity_Type_Default { return null; };
    }
}

Gen_Ref :: struct {
    index: s32;
    generation: u32;
}

Ack_Validation_Level :: enum u8 {
    // 0 = no asserts or logs.
    NONE   :: 0;
    // 1 = some asserts.
    LOW    :: 1;
    // 2 = more asserts, some logs.
    MEDIUM :: 2;
    // 3 = all errors asserted, verbose logs.
    HIGH   :: 3;
}

#assert(GENERAL_VALIDATION_LEVEL >= Ack_Validation_Level.NONE && GENERAL_VALIDATION_LEVEL <= Ack_Validation_Level.HIGH);
#assert(PHYSICS_VALIDATION_LEVEL >= Ack_Validation_Level.NONE && PHYSICS_VALIDATION_LEVEL <= Ack_Validation_Level.HIGH);
#assert(RENDER_VALIDATION_LEVEL  >= Ack_Validation_Level.NONE && RENDER_VALIDATION_LEVEL  <= Ack_Validation_Level.HIGH);

// ---------------------------------------------------------------------------------------------
// context additions

// render
#add_context renderer: *Renderer;

// physics
#add_context physical_world: *Physical_World;

// json
// errors are cleared and added per-load and per-save, for each thread. 
// if the number of errors maxes out, errors are no longer stored unless a fatal error happens,
// then that ovewrites the last error.
// adding these to the context so they can be thread-local, allowing for multithreaded processing
#add_context json_error_buffer:       [32]JSON_Error;
#add_context json_errors:             []JSON_Error;
#add_context json_load_result:        JSON_Load_Result;

// mesh
#add_context ack_mesh_self_allocation: [..]u8;
#add_context ack_mesh_buffer_table: [..]Buffer_Table_Item;
#add_context ack_mesh_texture_buffer_table: [..]Texture_Buffer_Table_Item;

// lock
#add_context thread_wait_events: Event_Pool;

#if OS == .WINDOWS {
    // system
    #add_context system_timer: Win32.HANDLE;
}

// ---------------------------------------------------------------------------------------------

ack_engine_path :: () -> string {
    return get_final_path(#filepath,, temp);
}

// multi-file loads
#load "mesh/mesh.jai";
#load "navmesh/navmesh.jai";
#load "physics/physics.jai";
#load "render/render.jai";
#load "containers/containers.jai";
#load "allocation/allocation.jai";
#load "math/math.jai";

// single-file loads
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

ImGui :: #import "Ack!/render/ImGui_VulkanWin32";

#scope_module

engine_log :: ($verbosity: Ack_Validation_Level, fmt: string, args: ..Any, add_newline := true, $sector := "", $validation_level := cast(Ack_Validation_Level) GENERAL_VALIDATION_LEVEL, caller_loc := #caller_location) #expand {
    #assert(verbosity >= .MEDIUM);
    #if verbosity <= validation_level {
        do_log("LOG", false);
    }
}

engine_warning :: ($verbosity: Ack_Validation_Level, fmt: string, args: ..Any, add_newline := true, $sector := "", $validation_level := cast(Ack_Validation_Level) GENERAL_VALIDATION_LEVEL, caller_loc := #caller_location) #expand {
    #assert(verbosity >= .MEDIUM);
    #if verbosity <= validation_level {
        do_log("WARNING", true);
    }
}

// todo: does the bool evaluate before the expansion? if so, may need to pass code
engine_check :: ($assert_level: Ack_Validation_Level, condition: bool, fmt := "", args: ..Any, add_newline := true, $sector := "", $validation_level := cast(Ack_Validation_Level) GENERAL_VALIDATION_LEVEL, caller_loc := #caller_location) -> bool #no_debug #expand {
    #if validation_level > .NONE && assert_level <= validation_level {
        if !condition && assert_helper(fmt, ..args, caller_loc) {
            if fmt.count > 0 {
                do_log("ERROR", true);
            }
            debug_break();
        }
    }
    return condition;
}

render_check :: ($assert_level: Ack_Validation_Level, result: VkResult, fmt := "", args: ..Any, add_newline := true, $sector := "", $validation_level := cast(Ack_Validation_Level) GENERAL_VALIDATION_LEVEL, caller_loc := #caller_location) -> bool #no_debug #expand {
    success := result == .SUCCESS;
    #if validation_level > .NONE && assert_level <= validation_level {
        if !success && assert_helper(fmt, ..args, caller_loc) {
            ack_log("vk error: %", result);
            if fmt.count > 0 {
                do_log("ERROR", true);
            }
            debug_break();
        }
    }
    return success;
}

render_log       :: #bake_arguments engine_log(sector="render", validation_level=RENDER_VALIDATION_LEVEL);
render_warning   :: #bake_arguments engine_warning(sector="render", validation_level=RENDER_VALIDATION_LEVEL);
render_check     :: #bake_arguments engine_check(sector="render", validation_level=RENDER_VALIDATION_LEVEL);

physics_log      :: #bake_arguments engine_log(sector="physics", validation_level=PHYSICS_VALIDATION_LEVEL);
physics_warning  :: #bake_arguments engine_warning(sector="physics", validation_level=PHYSICS_VALIDATION_LEVEL);
physics_check    :: #bake_arguments engine_check(sector="physics", validation_level=PHYSICS_VALIDATION_LEVEL);


#if OS == .WINDOWS {
    Win32 :: #import "Windows";

    user32   :: #system_library "user32";
    kernel32 :: #system_library "kernel32";

    IsWindow :: (window: Win32.HWND) -> Win32.BOOL #foreign user32;
    IsIconic :: (window: Win32.HWND) -> Win32.BOOL #foreign user32;
    SetCursorPos :: (x: s32, y: s32) -> Win32.BOOL #foreign user32;
    SetForegroundWindow :: (window: Win32.HWND) -> Win32. BOOL #foreign user32;
    SetFocus :: (window: Win32.HWND) -> Win32.BOOL #foreign user32;
    ShowCursor :: (show: bool) -> s32 #foreign user32;
    
    GetConsoleTitleW :: (lpConsoleTitle: *s8, nSize: s32) -> s32 #foreign kernel32;
    SetConsoleTitleW :: (lpConsoleTitle: *s8) -> Win32.BOOL #foreign kernel32;
    GetConsoleWindow :: () -> Win32.HWND #foreign kernel32;
    SetConsoleCursorPosition :: (hConsoleOutput: Win32.HANDLE, dwCursorPosition: Win32.COORD) -> Win32.BOOL #foreign kernel32;
    SetConsoleTextAttribute :: (hConsoleOutput: Win32.HANDLE, wAttributes: s16) -> Win32.BOOL #foreign kernel32; 

    FindWindowW :: (lpClassName: *s8, lpWindowName: *s8) -> Win32.HWND #foreign user32;
    GetTickCount :: () -> s32 #foreign kernel32;
    
    GetConsoleScreenBufferInfo :: (hConsoleOutput: Win32.HANDLE, lpConsoleScreenBufferInfo: *Console_Screen_Buffer_Info) -> Win32.BOOL #foreign kernel32;

    ScrollConsoleScreenBufferW :: (hConsoleOutput: Win32.HANDLE, lpScrollRectangle: *Win32.SMALL_RECT, lpClipRectangle: *Win32.SMALL_RECT, dwDestinationOrigin: Win32.COORD, lpFill: *Char_Info) -> Win32.BOOL #foreign kernel32;

    Console_Screen_Buffer_Info :: struct {
        dwSize: Win32.COORD;
        dwCursorPosition: Win32.COORD;
        wAttributes: s16;
        srWindow: Win32.SMALL_RECT;
        dwMaximumWindowSize: Win32.COORD;

    }

    Char_Info :: struct {
        using Char : union {
            UnicodeChar: s16;
            AsciiChar:   s8;
        }
        Attributes: s16;
    }

    CreateWaitableTimerExW :: (lpTimerAttributes: *Win32.SECURITY_ATTRIBUTES, lpName: *u16, dwFlags: s32, dwDesiredAccess: s32) -> Win32.HANDLE #foreign kernel32;

    CREATE_WAITABLE_TIMER_MANUAL_RESET : s32 : 0x1; 
    CREATE_WAITABLE_TIMER_HIGH_RESOLUTION : s32 : 0x2;
    TIMER_MODIFY_STATE : s32 : 0x02;

    SyncObjectSecurityParams :: enum s32 {
        SYNCHRONIZE         :: 0x00100000;
        TIMER_MODIFY_STATE  :: 0x00000002;
        TIMER_ALL_ACCESS    :: 0x001f0003;
    }
}

// base imports
#import "Basic";
#import "Math";
#import "Window_Creation";
#import "Machine_X64";
#import "Compiler";
#import "String";
#import "Hash_Table";
#import "Sort";
#import "md5";
#import "Random";
Program_Print :: #import "Program_Print";
#import "Bit_Operations";
#import "Atomics";
#import "File";
#import "File_Utilities";
#import "Window_Creation";
#import "Flat_Pool";
#import "stb_image";
#import "Process";
#import "Input";

#import "Ack!/render/vulkan-jai";

#scope_file

do_log :: ($type: string, $log_location: bool) #expand {
    header :: #run tprint("% Ack!", type);
    use_header := header;
    #if `sector.count > 0 {
        use_header = tprint("%%", header, `sector);
    }
    do_log_location :: #ifx log_location then Ack_Log_Location.YES else Ack_Log_Location.NO;
    ack_log(fmt=`fmt, args=..`args, add_newline=`add_newline, log_location=do_log_location, verbosity=S64_MAX, caller_loc=`caller_loc, override_header=use_header);
}

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

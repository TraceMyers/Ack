// Window_Creation passthrough
Window_Type                :: Window_Creation.Window_Type;
toggle_fullscreen          :: Window_Creation.toggle_fullscreen;
get_dimensions             :: Window_Creation.get_dimensions;

window: Window_Type;
window_x, window_y, window_width, window_height: s32;

Window_Creation_Settings :: struct {
    name := "Ack! a window!";
    x:      s32 = 0;
    y:      s32 = 0;
    width:  s32 = 1280;
    height: s32 = 720;
}

create_window :: (settings: Window_Creation_Settings) -> bool {
    if window == null {
        window = Window_Creation.create_window(settings.width, settings.height, settings.name, settings.x, settings.y);
    } else {
        engine_warning("window is already non-null but create_window is being called. skipping creation");
    }

    if window == null {
        return false;
    }

    // get initial dimensions because we won't update this until the first resize
    update_cached_window_position_and_dimensions();
    // make_window_take_focus(window);

    return true;
}

update_window :: () {
    window_resizes := get_window_resizes();
    if window_resizes.count > 0 {
        // todo: check why this works more reliably than using resizes in the input list
        update_cached_window_position_and_dimensions();
    }
}

get_window_viewport :: () -> Vector2 {
    return {xx window_width, xx window_height};
}

update_cached_window_position_and_dimensions :: () -> bool {
    success: bool;
    window_x, window_y, window_width, window_height, success = get_dimensions(window, true);
    return success;
}

is_window_open :: () -> bool {
    #if OS == .WINDOWS {
        return xx IsWindow(window);
    }
    return false;
}

is_window_minimized :: () -> bool {
    #if OS == .WINDOWS {
        return xx IsIconic(window);
    }
    return false;
}

make_window_take_focus :: () {
    if OS == .WINDOWS {
        SetForegroundWindow(window);
        Win32.SetCapture(window);
    }
}

get_mouse_cursor_position :: (window_relative := false) -> x: s32, y: s32 {
    x, y: s32;
    #if OS == .WINDOWS {
        pos: Win32.POINT;
        Win32.GetCursorPos(*pos);
        x, y = pos.x, pos.y;
    }
    
    if window_relative {
        x -= window_x;
        y -= window_y;
    }

    return x, y;
}

set_mouse_cursor_position :: (x: s32, y: s32, window_relative := false) {
    use_x, use_y := x, y;

    if window_relative {
        use_x = window_x + x;
        use_y = window_y + y;
    }

    #if OS == .WINDOWS {
        SetCursorPos(use_x, use_y);
    }
}

set_mouse_cursor_visibility :: (visible: bool) {
    #if OS == .WINDOWS {
        if visible {
            ShowCursor(true);
        } else {
            // windows uses a voting system for ShowCursor that expects all applications to agree that the cursor
            // should be hidden or shown, which... I don't know maybe there's a way to make it work.
            // this stuffs the ballot box.
            safety_counter := 100;
            while ShowCursor(false) >= 0 && safety_counter > 0 { 
                safety_counter -= 1; 
            }
        }
    }
}

get_console_window :: () -> Window_Type {
    #if OS == .WINDOWS {
        return GetConsoleWindow();
    } else return null;
}

set_console_cursor_position :: (x: s16, y: s16) {
    if OS == .WINDOWS {
        SetConsoleCursorPosition(window, {x, y});
    }
}

clear_console :: () {
    if OS == .WINDOWS {
        print("\e[1;1H\e[2J");
    }
}

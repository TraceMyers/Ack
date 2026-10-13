update_input :: () {
    gamepad.generate_events = true;

    time_since_refreshed_gamepads := engine.clock.time - refresh_gamepads_timestamp;
    if time_since_refreshed_gamepads > refresh_gamepads_interval {
        refresh_gamepads_timestamp = xx engine.clock.time;
        init_gamepad();
    }

    update_window_events();
    update_gamepad();

    should_quit: bool;

    for events_this_frame {
        if engine.input.event_processor then engine.input.event_processor(it);

        if it.type == .QUIT {
            should_quit = true;
        }
        if it.type == {
        case .KEYBOARD;
            with_active_controller(#code {
                if it.key_pressed {
                    if !controller.key_was_down_previous_frame[cast(int) it.key_code] {
                        call_input_binding(controller_id, it.key_code, .BUTTON_PRESSED);
                    }
                } else {
                    call_input_binding(controller_id, it.key_code, .BUTTON_RELEASED);
                }
            });
        }
    }

    with_active_controller(#code {
        if gamepad.left_trigger > controller.left_trigger_deadzone {
            key_code := Key_Code.GAMEPAD_0_BEGIN + xx Gamepad_Code.LEFT_TRIGGER;
            norm_x := respace(gamepad.left_trigger, {controller.left_trigger_deadzone, 1}, {0, 1});
            call_input_binding(controller_id, key_code, .AXIS_1D, norm_x);
        }

        if gamepad.right_trigger > controller.right_trigger_deadzone {
            key_code := Key_Code.GAMEPAD_0_BEGIN + xx Gamepad_Code.RIGHT_TRIGGER;
            norm_x := respace(gamepad.right_trigger, {controller.right_trigger_deadzone, 1}, {0, 1});
            call_input_binding(controller_id, key_code, .AXIS_1D, norm_x);
        }

        get_gamepad_stick_deadzoned_and_normalized_values :: (stick: Vector2, deadzone: float) -> x: float, y: float {
            norm_x, norm_y: float;
            if stick.x > deadzone {
                norm_x = respace(stick.x, {deadzone, 1}, {0, 1});
            } else if stick.x < -deadzone {
                norm_x = respace(stick.x, {-1, -deadzone}, {-1, 0});
            }
            if stick.y > deadzone {
                norm_y = respace(stick.y, {deadzone, 1}, {0, 1});
            } else if stick.y < -deadzone {
                norm_y = respace(stick.y, {-1, -deadzone}, {-1, 0});
            } 
            return norm_x, norm_y;
        }

        {
            norm_x, norm_y := get_gamepad_stick_deadzoned_and_normalized_values(gamepad.left_stick, controller.left_gamepad_stick_deadzone);
            if norm_x != 0 || norm_y != 0 {
                call_input_binding(controller_id, Key_Code.GAMEPAD_0_BEGIN + xx LEFT_GAMEPAD_STICK_AXIS_CODE, .AXIS_2D, norm_x, norm_y);
            }
        }

        {
            norm_x, norm_y := get_gamepad_stick_deadzoned_and_normalized_values(gamepad.right_stick, controller.right_gamepad_stick_deadzone);
            if norm_x != 0 || norm_y != 0 {
                call_input_binding(controller_id, Key_Code.GAMEPAD_0_BEGIN + xx RIGHT_GAMEPAD_STICK_AXIS_CODE, .AXIS_2D, norm_x, norm_y);
            }
        }

        for 0..enum_highest_value(Key_Code) {
            if (input_button_states[it] & .DOWN) && (input_button_states[it] & .END) == 0 {
                call_input_binding(controller_id, xx it, .BUTTON_HELD);
                controller.key_was_down_previous_frame[it] = true;
            } else {
                controller.key_was_down_previous_frame[it] = false;
            }
        }
    });

    mouse_cursor_pos.x, mouse_cursor_pos.y = get_mouse_cursor_position();
    
    engine.settings.quit |= should_quit;
}

with_active_controller :: ($body: Code) #expand {
    if engine.input.active_controller < 0 || engine.input.active_controller >= engine.input.controllers.items.count {
        return;
    }
    `controller_id := engine.input.active_controller;
    `controller    := *engine.input.controllers[controller_id];
    #insert body;
}

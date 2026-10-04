refresh_gamepads_timestamp: float;
refresh_gamepads_interval := 1.0;
left_trigger_deadzone := 0.3;
right_trigger_deadzone := 0.3;
left_gamepad_stick_deadzone  := 0.3;
right_gamepad_stick_deadzone := 0.3;
mouse_cursor_pos: Vector2i;
look_smooth_speed := 50.0;

LEFT_GAMEPAD_STICK_AXIS_CODE :: Gamepad_Code.LEFT_STICK_UP;
RIGHT_GAMEPAD_STICK_AXIS_CODE :: Gamepad_Code.RIGHT_STICK_UP;

ack_input_init :: (controllers: []Controller) {
    init_gamepad(); // can recall this to refresh connected gamepads
    gamepad.generate_events = true;

    for *controller : controllers {
        controller.any_input_bindings_at_key_code = make_bit_array(enum_highest_value(Key_Code) + 1);
        controller.key_was_down_previous_frame    = make_bit_array(enum_highest_value(Key_Code) + 1);
    }
}

#load "input_binding.jai";
#load "input_update.jai";

Controller :: struct {
    key_was_down_previous_frame: Bit_Array;
    any_input_bindings_at_key_code: Bit_Array;
    input_bindings: Table(u64, Input_Binding);
}

Control_Mode :: enum {
    GAME;
    FREE_FLY;
    #insert -> string {
        builder: String_Builder;
        for ADD_CONTROL_MODES {
            print(*builder, "%;\n", it);
        }
        return builder_to_string(*builder);
    }
}

Input_Type :: enum u16 {
    BUTTON_PRESSED;
    BUTTON_RELEASED;
    BUTTON_HELD;
    AXIS_1D;
    AXIS_2D;
}

button_input_binding_proc              :: #type (key: Key_Code, type: Input_Type);
button_input_binding_with_entity_proc  :: #type (key: Key_Code, type: Input_Type, entity: *user_types.entity_type);
axis_1d_input_binding_proc             :: #type (x: float32);
axis_1d_input_binding_with_entity_proc :: #type (x: float32, entity: *user_types.entity_type);
axis_2d_input_binding_proc             :: #type (x: float32, y: float32);
axis_2d_input_binding_with_entity_proc :: #type (x: float32, y: float32, entity: *user_types.entity_type);

Input_Binding :: struct {
    input_type: Input_Type;
    proc: *void;
    entity_ref: user_types.entity_id_type;
}

to_key_code :: inline (gamepad_code: Gamepad_Code) -> Key_Code {
    return xx gamepad_code + Key_Code.GAMEPAD_0_BEGIN;
}

to_gamepad_code :: inline (key_code: Key_Code) -> gamepad_code: Gamepad_Code, is_gamepad_code: bool {
    if key_code >= Key_Code.GAMEPAD_0_BEGIN && key_code < Key_Code.GAMEPAD_0_END {
        return xx (key_code - Key_Code.GAMEPAD_0_BEGIN), true;
    } else {
        return xx 0, false;
    }
}

set_gamepad_input_binding :: (control_modes: []Control_Mode, gamepad_code: Gamepad_Code, input_type: Input_Type, proc: $proc_type, entity_ref := user_types.null_entity_id) {
    set_input_binding(control_modes, to_key_code(gamepad_code), input_type, proc, entity_ref);
}

set_input_binding :: (control_modes: []Control_Mode, key_code: Key_Code, input_type: Input_Type, proc: $proc_type, entity_ref := user_types.null_entity_id) {
    Input_Binding_Argtype :: enum u8 {
        KEY_CODE;
        INPUT_TYPE;
        ENTITY;
        FLOAT;
    }

    if memcmp(*entity_ref, *user_types.null_entity_id, size_of(user_types.entity_id_type)) != 0 {
        tinfo := cast(*Type_Info_Procedure)proc_type;
        INPUT_BINDING_MAX :: 3;
        argtypes := make_local_static_array(Input_Binding_Argtype, INPUT_BINDING_MAX);

        assert(tinfo.argument_types.count <= 3);

        // in order to support binding inputs to any entity type, doing runtime validation here that the procedure's
        // signature makes sense. basically, it expects an entity type at the *Entity param spot.
        for argtype, arg_i : tinfo.argument_types {
            if argtype.type == .POINTER {
                ptr_tinfo := cast(*Type_Info_Pointer) argtype;
                assert(ptr_tinfo.pointer_to.type == .STRUCT);
                arg_tinfo := cast(*Type_Info_Struct) ptr_tinfo.pointer_to;
                is_entity_type := (cast(*Type) *arg_tinfo).* == user_types.entity_type;
                assert(is_entity_type);
                static_array_add(*argtypes, .ENTITY, INPUT_BINDING_MAX);
            } else if argtype.type == .ENUM {
                arg_tinfo := cast(*Type_Info_Enum) argtype;
                if arg_tinfo.name == "Input_Type" {
                    static_array_add(*argtypes, .INPUT_TYPE, INPUT_BINDING_MAX);
                } else if arg_tinfo.name == "Key_Code" {
                    static_array_add(*argtypes, .KEY_CODE, INPUT_BINDING_MAX);
                } else {
                    assert(false, "invalid enum type parameter in input binding proc");
                }
            } else if argtype.type == .FLOAT {
                assert(argtype.runtime_size == 4);
                static_array_add(*argtypes, .FLOAT, INPUT_BINDING_MAX);
            } else {
                assert(false, "unrecognized argument type for input binding procedure");
            }
        }

        if #complete input_type == {
        case .BUTTON_PRESSED;
            #through;
        case .BUTTON_RELEASED;
            #through;
        case .BUTTON_HELD;
            assert(argtypes.count == 3 && argtypes[0] == .KEY_CODE && argtypes[1] == .INPUT_TYPE && argtypes[2] == .ENTITY, "proc type: %, argtypes: %",  proc_type, argtypes);
            set_input_binding_impl(control_modes, key_code, input_type, cast(button_input_binding_with_entity_proc) proc, entity_ref);
        case .AXIS_1D;
            assert(argtypes.count == 3 && argtypes[0] == .KEY_CODE && argtypes[1] == .FLOAT && argtypes[2] == .ENTITY);
            set_input_binding_impl(control_modes, key_code, input_type, cast(axis_1d_input_binding_with_entity_proc) proc, entity_ref);
        case .AXIS_2D;           
            assert(argtypes.count == 3 && argtypes[0] == .FLOAT && argtypes[1] == .FLOAT && argtypes[2] == .ENTITY);
            set_input_binding_impl(control_modes, key_code, input_type, cast(axis_2d_input_binding_with_entity_proc) proc, entity_ref);
        }

    } else {
        if proc_type == {
        case button_input_binding_proc;  #through;
        case axis_1d_input_binding_proc; #through;
        case axis_2d_input_binding_proc;
            set_input_binding_impl(control_modes, key_code, input_type, proc, entity_ref);
        case;
            assert(false, "can't bind an input to an entity without passing an entity reference");
        }
    }
}

set_input_binding_impl :: (control_modes: []Control_Mode, key_code: Key_Code, input_type: Input_Type, proc: $proc_type, entity_ref := user_types.null_entity_id) {
    assert(proc != null);

    for mode : control_modes {
        using context.world.controllers[mode];

        any_input_bindings_at_key_code[cast(int) key_code] = true;
        input_id := get_input_id(key_code, input_type);

        binding := Input_Binding.{input_type=input_type, proc=xx proc, entity_ref=entity_ref};

        if memcmp(*entity_ref, *user_types.null_entity_id, size_of(user_types.entity_id_type)) != 0 {
            if input_type == {
            case .BUTTON_PRESSED;  #through;
            case .BUTTON_RELEASED; #through;
            case .BUTTON_HELD;
                assert(proc_type == button_input_binding_with_entity_proc);
            case .AXIS_1D;
                assert(proc_type == axis_1d_input_binding_with_entity_proc);
            case .AXIS_2D;
                assert(proc_type == axis_2d_input_binding_with_entity_proc);
            }
        } else {
            if input_type == {
            case .BUTTON_PRESSED;  #through;
            case .BUTTON_RELEASED; #through;
            case .BUTTON_HELD;
                assert(proc_type == button_input_binding_proc);
            case .AXIS_1D;
                assert(proc_type == axis_1d_input_binding_proc);
            case .AXIS_2D;
                assert(proc_type == axis_2d_input_binding_proc);
            }
        }

        table_set(*input_bindings, input_id, binding);
    }
}

clear_input_binding :: (mode: Control_Mode, key_code: Key_Code, input_type: Input_Type) {
    using context.world.controllers[mode];

    input_id := get_input_id(key_code, input_type);
    table_remove(*input_bindings, input_id);
    unmark_key_code_if_no_bindings(mode, key_code);
}

call_input_binding :: (mode: Control_Mode, key_code: Key_Code, input_type: Input_Type, axis_x: float32 = 0, axis_y: float32 = 0) {
    using context.world.controllers[mode];

    if !any_input_bindings_at_key_code[cast(int) key_code] {
        return;
    }

    input_id := get_input_id(key_code, input_type);
    binding  := table_find_pointer(*input_bindings, input_id);

    if binding == null {
        return;
    }
    assert(binding.proc != null);

    if memcmp(*binding.entity_ref, *user_types.null_entity_id, size_of(user_types.entity_id_type)) != 0 {
        entity := user_types.id_to_entity_proc(binding.entity_ref);
        if entity == null {
            ack_log("input binding for input % was cleared because entity % was invalid", binding.entity_ref, log_level=.WARNING);
            clear_input_binding(mode, key_code, input_type);
            return;
        }
        if input_type == {
        case .BUTTON_PRESSED;  #through;
        case .BUTTON_RELEASED; #through;
        case .BUTTON_HELD;
            proc := cast(button_input_binding_with_entity_proc) binding.proc;
            proc(key_code, input_type, entity);
        case .AXIS_1D;
            proc := cast(axis_1d_input_binding_with_entity_proc) binding.proc;
            proc(axis_x, entity);
        case .AXIS_2D;
            proc := cast(axis_2d_input_binding_with_entity_proc) binding.proc;
            proc(axis_x, axis_y, entity);
        }
    } else {
        if input_type == {
        case .BUTTON_PRESSED;  #through;
        case .BUTTON_RELEASED; #through;
        case .BUTTON_HELD;
            proc := cast(button_input_binding_proc) binding.proc;
            proc(key_code, input_type);
        case .AXIS_1D;
            proc := cast(axis_1d_input_binding_proc) binding.proc;
            proc(axis_x);
        case .AXIS_2D;
            proc := cast(axis_2d_input_binding_proc) binding.proc;
            proc(axis_x, axis_y);
        }
    }
}

get_input_id :: inline (key_code: Key_Code, input_type: Input_Type) -> u32 {
    return ((cast(u32) key_code) << 16) | (cast(u32) input_type);
}

#scope_file

unmark_key_code_if_no_bindings :: (mode: Control_Mode, key_code: Key_Code) {
    using context.world.controllers[mode];

    for 0..enum_highest_value(Input_Type) {
        input_id := get_input_id(key_code, cast(Input_Type) it);
        if table_find_pointer(*input_bindings, input_id) != null {
            return;
        }
    }
    any_input_bindings_at_key_code[cast(int) key_code] = false;
}

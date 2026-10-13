#scope_module

scope_set_log_source :: (id: Ack_Log_Source_ID) #expand {
    context.log_source_identifier = xx id;
    `defer context.log_source_identifier = 0;
}

engine_log_base :: (format_string: string, args: .. Any, loc := #caller_location, flags := Log_Flags.NONE, user_flags : u32 = 0, $log_source := Ack_Log_Source_ID.ENGINE, $severity_flag := Log_Flags.NONE) {
    scope_set_log_source(log_source);
    log(format_string, ..args, loc=loc, flags=flags | severity_flag, user_flags=user_flags);
}

engine_log      :: #bake_arguments engine_log_base(log_source=.ENGINE, severity_flag=.NONE);
engine_warning  :: #bake_arguments engine_log_base(log_source=.ENGINE, severity_flag=.WARNING);
engine_error    :: #bake_arguments engine_log_base(log_source=.ENGINE, severity_flag=.ERROR);

physics_log     :: #bake_arguments engine_log_base(log_source=.PHYSICS, severity_flag=.NONE);
physics_warning :: #bake_arguments engine_log_base(log_source=.PHYSICS, severity_flag=.WARNING);
physics_error   :: #bake_arguments engine_log_base(log_source=.PHYSICS, severity_flag=.ERROR);

render_log      :: #bake_arguments engine_log_base(log_source=.RENDER, severity_flag=.NONE);
render_warning  :: #bake_arguments engine_log_base(log_source=.RENDER, severity_flag=.WARNING);
render_error    :: #bake_arguments engine_log_base(log_source=.RENDER, severity_flag=.ERROR);

#if ENABLE_VALIDATION {
    engine_check_base :: (condition: bool, fmt := "", args: ..Any, level := Ack_Validation_Level.NORMAL, $max_validation_level := Ack_Validation_Level.NORMAL, $log_source := Ack_Log_Source_ID.ENGINE, caller_loc := #caller_location) #expand #no_debug {
        if !condition {
            if fmt.count > 0 {
                engine_log_base(fmt, ..args, loc=caller_loc, log_source=log_source, severity_flag=.ERROR);
            }
            if level <= max_validation_level {
                if assert_helper(fmt, ..args, caller_loc) then debug_break();
            }
        }
    }

    engine_check  :: #bake_arguments engine_check_base(max_validation_level=GENERAL_VALIDATION_LEVEL, log_source=.ENGINE);
    physics_check :: #bake_arguments engine_check_base(max_validation_level=PHYSICS_VALIDATION_LEVEL, log_source=.PHYSICS);
    render_check  :: #bake_arguments engine_check_base(max_validation_level=RENDER_VALIDATION_LEVEL, log_source=.RENDER);

} else {
    engine_check_base :: (#discard condition: bool, #discard fmt := "", #discard args: ..Any, #discard level := Ack_Validation_Level.NORMAL, #discard max_validation_level := Ack_Validation_Level.NORMAL, #discard log_source := Ack_Log_Source_ID.ENGINE, #discard caller_loc := #caller_location) #no_debug #expand {}
    engine_check  :: engine_check_base;
    physics_check :: engine_check_base;
    render_check  :: engine_check_base;
}

// -----------------------------------------------------------------------------------------------
// ..._evaluate() procedures always evaluate the condition and return it, even if
// the assert level is not met.

engine_evaluate_base :: (condition: bool, fmt := "", args: ..Any, level := Ack_Validation_Level.NORMAL, $max_validation_level := Ack_Validation_Level.NORMAL, $log_source := Ack_Log_Source_ID.ENGINE, caller_loc := #caller_location) -> bool #expand #no_debug {
    engine_check_base(condition, fmt, ..args, level=level, max_validation_level=max_validation_level, log_source=log_source, caller_loc=caller_loc);
    return condition;
}

engine_evaluate  :: #bake_arguments engine_evaluate_base(max_validation_level=GENERAL_VALIDATION_LEVEL, log_source=.ENGINE);
physics_evaluate :: #bake_arguments engine_evaluate_base(max_validation_level=PHYSICS_VALIDATION_LEVEL, log_source=.PHYSICS);
render_evaluate  :: #bake_arguments engine_evaluate_base(max_validation_level=RENDER_VALIDATION_LEVEL, log_source=.RENDER);

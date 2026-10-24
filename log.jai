// todo: call site rate-limiting (with params) would be pretty easy: just use the code location as the hash

Log_Options :: struct {
    // have the logging system call this proc with the finalized text, if you set it.
    callback: (log_text: string);

    // the path (not including filename) where logs will be stored. can either be relative
    // to the working directory at init or it can be an absolute path.
    file_location := "logs";
    file_time_zone := Time_Zone.LOCAL;
    disable_file_write := false;
};

global_log_options: Log_Options;

// read Ack_Log_Flags body below
#assert(USER_VERBOSITY_LEVELS.count <= xx Ack_Log_Flags.NO_PROCEDURE_NAME);

// predefined to make it easy to bake your own log procedures (see below)
basic_log :: #procedure_of_call log(format_string=""); 

// pass as user flags to log()
Ack_Log_Flags :: enum_flags u32 {
    // user verbosity reserves the lowest half byte (0xf). indexes 0 to 15. 
    // if your program wants separate verbosities for animation, entity update, etc.
    // then give animation an index (say, 1), and entity update an index (say, 2)
    //
    // animation_log     :: #bake_arguments basic_log(user_flags=1);
    // entity_update_log :: #bake_arguments basic_log(user_flags=2);
    //
    // during import, set their respective verbosity levels
    //
    // #import "Ack!"()(USER_VERBOSITY_LEVELS=u8.[0, 1, 2]; 
    // ('default' set to normal, 'animation' set to verbose, 'entity update' set to very verbose)
    //
    // pair with log-level verbosity ratings...
    //
    // animation_log("yadda yadda", flags=.VERBOSE_ONLY);

    // don't print the procedure name
    NO_PROCEDURE_NAME :: 0x10;
    // log the location of the caller even if it's not an error
    FORCE_LOG_LOCATION;
    // only call the callback, don't write to stdout/stderror/file.
    CALLBACK_ONLY;
    // add an extra newline at the end
    ADD_NEWLINE;
}

// used to identify log source for engine only
Ack_Log_Source_ID :: enum u64 {
    ENGINE :: 1;
    PHYSICS;
    RENDER;
}

#if ENABLE_LOGGING {
    ack_log :: (message: string, data: *void, in_info: Log_Info) {
        info := cast(*Ack_Log_Info) *in_info;

        verbosity: Log_Level;
        is_engine_log: bool;

        if cast(Ack_Log_Source_ID) info.source_identifier == {
        case .ENGINE;
            verbosity = xx GENERAL_VERBOSITY_LEVEL;
            is_engine_log = true;
        case .RENDER;
            verbosity = xx RENDER_VERBOSITY_LEVEL;
            is_engine_log = true;
        case .PHYSICS;
            verbosity = xx PHYSICS_VERBOSITY_LEVEL;
            is_engine_log = true;
        case;
            user_verbosity_id := (info.user_flags & 0xf);
            engine_check(xx user_verbosity_id < USER_VERBOSITY_LEVELS.count, "indexing to user verbosity level %, but USER_VERBOSITY_LEVELS (in ack module params) has length %. log() being called from %.", user_verbosity_id, USER_VERBOSITY_LEVELS.count, info.location);
            verbosity = xx USER_VERBOSITY_LEVELS[user_verbosity_id];
        }

        if (info.common_flags & .VERBOSE_ONLY) != 0 {
            if verbosity < .VERBOSE {
                return;
            }
        } else if (info.common_flags & .VERY_VERBOSE_ONLY) != 0 {
            if verbosity < .VERY_VERBOSE {
                return;
            }
        }

        proc_on_call_stack_before_log: string;
        if (info.user_flags & .NO_PROCEDURE_NAME) == 0 && context.stack_trace && context.stack_trace.next && context.stack_trace.next.next {
            if is_engine_log {
                if context.stack_trace.next.next.next {
                    proc_on_call_stack_before_log = context.stack_trace.next.next.next.info.name;
                }
            } else {
                proc_on_call_stack_before_log = context.stack_trace.next.next.info.name;
            }
        }

        to_standard_error   := (info.common_flags & .ERROR) != 0;
        should_log_location := (info.user_flags & .FORCE_LOG_LOCATION) != 0;

        header: string;
        if (info.common_flags & .ERROR) != 0 {
            header = "ERROR";
            should_log_location = true;
        } else if (info.common_flags & .WARNING) != 0 {
            header = "WARNING";
        } else {
            header = "LOG";
        }

        ack_log_impl(message, proc_on_call_stack_before_log, should_log_location, info.location, header, (info.user_flags & .CALLBACK_ONLY) != 0, to_standard_error, (info.user_flags & .ADD_NEWLINE) != 0);
    }
} else {
    ack_log :: (message: string, data: *void, in_info: Log_Info) {}
}

// formatting helpers

fmt_commas :: (x: $T) -> FormatInt #expand #modify { return T.(*Type_Info).type == .INTEGER; } {
    return FormatInt.{value=x, digits_per_comma=3, comma_string=","};
}

fmt_commas :: (x: $T) -> FormatFloat #expand #modify { return T.(*Type_Info).type == .FLOAT; } {
    return FormatFloat.{value=x, thousand_separators=true};
}

fmt_hex :: (x: $T, minimum_digits := 0) -> FormatInt #expand {
    return FormatInt.{value=x, base=16, minimum_digits=minimum_digits};
}

fmt_oct :: (x: $T, minimum_digits := 0) -> FormatInt #expand {
    return FormatInt.{value=x, base=8, minimum_digits=minimum_digits};
}

fmt_bin :: (x: $T, minimum_digits := 0) -> FormatInt #expand {
    return FormatInt.{value=x, base=2, minimum_digits=minimum_digits};
}

fmt_verbose :: (x: $T, draw_type_name := true) -> FormatStruct #expand #modify { return T.(*Type_Info).type == .STRUCT; } {
    return FormatStruct.{
        value                                        = x, 
        draw_type_name                               = draw_type_name, 
        use_long_form_if_more_than_this_many_members = 0, 
        use_newlines_if_long_form                    = true
    };
}

fmt_verbose :: (x: $T) -> FormatArray #expand #modify{ return T.(*Type_Info).type == .ARRAY; } {
    return FormatArray.{
        value                                  = x,
        separator                              = "\n",
        stop_printing_after_this_many_elements = 1000
    };
}

#scope_module

ack_log_impl :: (
    msg: string,
    log_context: string,
    log_location: bool,
    caller_loc: Source_Code_Location,
    header: string,
    only_callback: bool,
    to_standard_error: bool,
    add_newline: bool
) {
    scope_lock(*logging_lock);

    auto_release_temp();

    MAX_HEADER_COUNT :: 8;
    MAX_CONTEXT_COUNT :: 26;
    BRACKETS_COUNT :: 4;
    END_LEAD_SPACE :: 1;
    LEAD_BUFFER_SIZE :: MAX_HEADER_COUNT + MAX_CONTEXT_COUNT + BRACKETS_COUNT;

    lead_buffer: [LEAD_BUFFER_SIZE]u8 = ---;
    lead_buffer_string := string.{0, xx lead_buffer.data};
    print_lead_item_to_buffer_string(*lead_buffer_string, header, MAX_HEADER_COUNT);
    print_lead_item_to_buffer_string(*lead_buffer_string, log_context, MAX_CONTEXT_COUNT);

    use_location: string;
    if log_location {
        use_location = tprint("\n>%", caller_loc);
    }

    fully_processed_text: string;

    optional_newline := ifx add_newline then "\n\n" else "\n";
    printing_log_context := true;

    #if LOG_VERTICAL_MODE {
        if try_replace_context_memory(header, log_context) {
            fully_processed_text = tprint("%\n  % %%", lead_buffer_string, trim(msg), use_location, optional_newline);
        } else {
            fully_processed_text = tprint("  % %%", trim(msg), use_location, optional_newline);
            printing_log_context = false;
        }
    } else {
        fully_processed_text = tprint("% % %%", lead_buffer_string, trim(msg), use_location, optional_newline);
    }

    if global_log_options.callback != null {
        global_log_options.callback(fully_processed_text);
    }

    if !only_callback {
        write_string(fully_processed_text, to_standard_error);
        write_to_log_file(fully_processed_text, printing_log_context);
    }
}

print_char_to_buffer_string :: inline (bufstr: *string, char: u8) {
    bufstr.count += 1;
    bufstr.*[bufstr.count-1] = char;
}

print_lead_item_to_buffer_string :: inline (bufstr: *string, lead_item: string, $MAX_COUNT: s64) {
    print_char_to_buffer_string(bufstr, #char "[");
    remain_space := MAX_COUNT - lead_item.count;
    for c : 0..lead_item.count-1 {
        if c >= MAX_COUNT then break;
        else if remain_space < 0 && (c == MAX_COUNT-2 || c == MAX_COUNT-1) {
            print_char_to_buffer_string(bufstr, #char ".");
        } else {
            print_char_to_buffer_string(bufstr, lead_item[c]);
        }
    }
    print_char_to_buffer_string(bufstr, #char "]");

    for i : 0..remain_space-1 {
        print_char_to_buffer_string(bufstr, #char " ");
    }
}

try_replace_context_memory :: (header: string, context_str: string) -> bool {
    // without a header, there's nothing to remember. every log must be considered unique.
    if header == "" {
        return true;
    }

    if header == last_known_header && context_str == last_known_context {
        omit_context_count += 1;
        if omit_context_count < omit_context_max_before_restate_context {
            return false;
        }
    }

    omit_context_count = 0;
    remember(header, context_str);
    return true;
}

remember :: (header: string, context_str: string) {
    if !initialized_internal_strings {
        last_known_header.data  = last_known_header_buffer.data;
        last_known_context.data = last_known_context_buffer.data;
        initialized_internal_strings = true;
    }
    remember_copy(header,      *last_known_header,  *last_known_header_buffer);
    remember_copy(context_str, *last_known_context, *last_known_context_buffer);
}

remember_copy :: inline (user_string: string, memory: *string, memory_buffer: *[MEMORY_BUFFER_SIZE]u8) {
    copy_size := min(memory_buffer.count, user_string.count);
    memcpy(memory_buffer.data, user_string.data, copy_size);
    memory.count = copy_size;
}

write_to_log_file :: inline (message: string, printing_log_context: bool) {
    if global_log_options.disable_file_write {
        return;
    }
    calendar_time := to_calendar(current_time_consensus(), global_log_options.file_time_zone);
    if logging_file.handle == null {
        if global_log_options.file_location.count > 0 {
            make_directory_if_it_does_not_exist(global_log_options.file_location);
        }
        scope_set_working_directory(global_log_options.file_location, global_log_options.file_location.count > 0);
        file_name := tprint(
            "ack_log__%_%_%__%_%_%__%.txt", 
            calendar_time.year, 
            FormatInt.{value=calendar_time.month_starting_at_0 + 1, minimum_digits=2}, 
            FormatInt.{value=calendar_time.day_of_month_starting_at_0 + 1, minimum_digits=2},
            FormatInt.{value=calendar_time.hour, minimum_digits=2},
            FormatInt.{value=calendar_time.minute, minimum_digits=2},
            FormatInt.{value=calendar_time.second, minimum_digits=2},
            calendar_time.time_zone
        );
        logging_file = file_open(file_name, for_writing=true);
    }
    if logging_file.handle != null {
        // timestamp only goes to the file, not stdout or the callback
        maybe_newline_after := ifx printing_log_context then "" else "\n";
        timestamp_and_message := tprint(
            "%:%:%.% %%",
            FormatInt.{value=calendar_time.hour, minimum_digits=2},
            FormatInt.{value=calendar_time.minute, minimum_digits=2},
            FormatInt.{value=calendar_time.second, minimum_digits=2},
            FormatInt.{value=calendar_time.millisecond, minimum_digits=3},
            maybe_newline_after,
            message
        );
        file_write(*logging_file, timestamp_and_message);
    }
}

// mirroring Log_Info to make user_flags typed as Ack_Log_Flags
Ack_Log_Info :: struct {
    source_identifier:   u64;
    location:     Source_Code_Location;
    common_flags: Log_Flags;
    user_flags:   Ack_Log_Flags;
}

MEMORY_BUFFER_SIZE :: 128;
last_known_header_buffer: [MEMORY_BUFFER_SIZE]u8;
last_known_header: string;
last_known_context_buffer: [MEMORY_BUFFER_SIZE]u8;
last_known_context: string;

omit_context_count: int;
omit_context_max_before_restate_context := 30;

initialized_internal_strings: bool;

logging_lock: Spin_Queue_Mutex;
logging_file: File;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

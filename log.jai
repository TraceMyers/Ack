// have the logging system call this proc with the finalized text, if set
term_log_passthrough_callback: (log_text: string);

// if true, don't log to stdout - only send contextualized log text to the passthrough callback
call_term_log_passthrough_only := false;

// log api
Ack_Log_Level :: enum u8 {
    LOG;
    WARNING;
    ERROR;
}

Ack_Log_Location :: enum u8 {
    AUTO;
    YES;
    NO;
}

ack_log :: (fmt: string, args: ..Any, $log_level := Ack_Log_Level.LOG, $log_location := Ack_Log_Location.AUTO, $verbosity := 1, add_newline := true, caller_loc := #caller_location, override_header := "") #expand {
    #assert(verbosity >= 1);
    #if verbosity >= USER_VERBOSITY_LEVEL {
        header: string;
        do_log_location: bool;
        log_context := #procedure_name();

        #if log_level == {
        case .LOG;
            header = ifx override_header then override_header else "LOG";
            DEFAULT_LOG_LOCATION_BEHAVIOR :: false;
            do_log_location = should_log_location();
        case .WARNING;
            header = ifx override_header then override_header else "WARNING";
            DEFAULT_LOG_LOCATION_BEHAVIOR :: true;
            do_log_location = should_log_location();
        case .ERROR;
            header = ifx override_header then override_header else "ERROR";
            DEFAULT_LOG_LOCATION_BEHAVIOR :: true;
            do_log_location = should_log_location();
        }

        report_impl(fmt, ..args, log_context=log_context, do_log_location, caller_loc, header, add_newline);
    }
}

check :: (condition: bool, fmt := "", args: ..Any, $level := 1) {
    #assert(level >= 1);
    #if level <= USER_VALIDATION_LEVEL {
        assert(condition, fmt, ..args);
    }
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

should_log_location :: () -> bool #expand {
    #if #complete `log_location == {
    case .AUTO;
        return `DEFAULT_LOG_LOCATION_BEHAVIOR;
    case .YES;
        return true;
    case .NO;
        return false;
    }
}

report_impl :: (
    fmt: string,
    args: ..Any,
    log_context: string,
    log_location: bool,
    caller_loc: Source_Code_Location,
    header: string,
    add_newline := true
) {
    auto_release_temp();

    MAX_HEADER_COUNT :: 20;
    MAX_CONTEXT_COUNT :: 26;
    BRACKETS_COUNT :: 4;
    END_LEAD_SPACE :: 1;
    LEAD_BUFFER_SIZE :: MAX_HEADER_COUNT + MAX_CONTEXT_COUNT + BRACKETS_COUNT;

    lead_buffer := talloc(LEAD_BUFFER_SIZE);
    lead_buffer_string := string.{0, xx lead_buffer};
    print_lead_item_to_buffer_string(*lead_buffer_string, header, MAX_HEADER_COUNT);
    print_lead_item_to_buffer_string(*lead_buffer_string, log_context, MAX_CONTEXT_COUNT);

    use_location: string;
    if log_location {
        use_location = tprint("\n>%", caller_loc);
    }

    msg := tprint(fmt, ..args);
    fully_processed_text: string;

    #if LOG_VERTICAL_MODE {
        if try_replace_context_memory(header, log_context) {
            fully_processed_text = tprint("  %\n    % %", lead_buffer_string, msg, use_location);
        } else {
            fully_processed_text = tprint(   "    % %", msg, use_location);
        }
    } else {
        fully_processed_text = tprint("% % %", lead_buffer_string, msg, use_location);
    }

    if term_log_passthrough_callback {
        term_log_passthrough_callback(fully_processed_text);
    }
    if !call_term_log_passthrough_only {
        if add_newline {
            log(fully_processed_text);
        } else {
            print(fully_processed_text);
        }
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
    if header == last_known_header && context_str == last_known_context {
        omit_context_count += 1;
        if omit_context_count >= omit_context_max_before_restate_context {
            omit_context_count = 0;
        }
    } else {
        omit_context_count = 0;
    }

    if omit_context_count > 0 {
        return false;
    } else {
        remember(header, context_str);
        return true;
    }
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

MEMORY_BUFFER_SIZE :: 128;
last_known_header_buffer: [MEMORY_BUFFER_SIZE]u8;
last_known_header: string;
last_known_context_buffer: [MEMORY_BUFFER_SIZE]u8;
last_known_context: string;

omit_context_count: int;
omit_context_max_before_restate_context := 30;

initialized_internal_strings: bool;

// Copyright (c) 2026 Trace Myers
// Licensed under the MIT License. See LICENSE file in the project root for license information.

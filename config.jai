// define your own config types and use this module to manage loading and saving.
// saves as a simple editable text format (todo: pretty print)
//
// usage:
//
// My_Config :: struct {
//      clear_color := Color3f.{r=1};
// }
// config_path := "path/to/config_file";
//
// // during program startup...
// init_config();
// config: My_Config;
// load_config(config_path, *config);
//
// // during program shutdown... 
// save_config(config_path, *config);

// must be called. not done automatically because you should be intentional about what allocator you 
// call this procedure with. creates a statically-sized buffer for string loading. the buffer can't reallocate
// because that'd overcomplicate loading.
init_config :: (max_byte_count_for_all_strings := 16384) {
    // would cause issues since temp is assumed to be free-able during load
    engine_check(.LOW, context.allocator.proc != temp.proc);
    initialized = true;
    array_reserve(*string_buffer, max_byte_count_for_all_strings);
    string_buffer.allocator = no_allocator;
}

save_config :: (filename: string, data: *$T) {
    engine_check(.LOW, initialized);
    auto_release_temp();

    tinfo := cast(*Type_Info_Struct) type_info(T);
    engine_check(.LOW, tinfo.type == .STRUCT);

    save_data: Save_Data;
    save_data.file_builder.allocator = temp;

    // not inlining to avoid code bloat
    no_inline struct_visit(data, *save_data, xx save_config_visitor, VISIT_OPTIONS);
    write_entire_file(filename, *save_data.file_builder);
}

// all string fields are allocated into one buffer. that buffer is returned so all strings can be 
// freed with an array_reset on that buffer. data is re-initialized just because that will make for fewer 
// bugs. data_init pointer provided so that callers can do additional initialization before load.
load_config :: (filename: string, data: *$T, shrink_strings_buffer := true, data_init: (*T) = null) -> []u8 {
    engine_check(.LOW, initialized);
    mark := get_temporary_storage_mark();
    defer if context.allocator.proc != temp.proc then set_temporary_storage_mark(mark);
    defer array_reset_keeping_memory(*string_buffer);

    data.* = {};
    data_init(data);

    file_data, success := read_entire_file(filename,, temp);
    if !success {
        log("WARNING: file % not loaded. config file default initialized", filename);
        return .[];
    }
    
    load_data: Load_Data;
    init(*load_data.table, 512,, temp);
    no_inline parse_file(file_data, *load_data.table);

    // not inlining to avoid code bloat
    no_inline struct_visit(data, *load_data, xx load_config_visitor, VISIT_OPTIONS);

    if string_buffer.count > 0 {
        strings := make_static_array(u8, string_buffer.count);
        memcpy(strings.data, string_buffer.data, strings.count);
        // fixing string pointers. moving them from the module-owned string buffer
        // into the one being returned.
        for load_data.strings {
            offset := (cast,force(s64) it.data) - (cast,force(s64) string_buffer.data);
            it.data = strings.data + offset;
        }
        return strings;
    } else {
        return .[];
    }
}

#scope_module

Config_Item :: struct {
    values: [4]string;
    floats: [4]float32 = .[FLOAT32_NAN, FLOAT32_NAN, FLOAT32_NAN, FLOAT32_NAN];
}

Save_Data :: struct {
    file_builder: String_Builder;
}

Load_Data :: struct {
    table: Table(string, Config_Item);
    strings: [..]*string;
}

parse_file :: (file_data: string, table: *Table(string, Config_Item)) {
    chirp_warning :: (line: string) {
        log("WARNING: improperly formatted config file line %", line);
    }

    for :per_line line : file_data {
        success, left, right := split_from_left(line, #char "=");
        if !success {
            chirp_warning(line);
            continue;
        }

        name  := trim(left);
        value := trim(right);

        item: Config_Item;

        success, left, right = split_from_left(value, #char "[");
        if success {
            values_str: string;
            success, values_str, right = split_from_left(right, #char "]");
            if !success {
                chirp_warning(line);
                continue;
            }

            values_arr := split(values_str, #char ",",, temp);
            for v : values_arr {
                if it_index >= 4 then continue;
                item.values[it_index] = v;
            }

            success, left, right = split_from_left(right, #char "(");
            if !success {
                continue;
            }

            bytes_str: string;
            success, bytes_str, right = split_from_left(right, #char ")");
            if !success {
                chirp_warning(line);
            }

            bytes_arr := split(bytes_str, #char ",",, temp);
            for b : bytes_arr {
                if it_index >= 4 then continue;
                int_val, int_read_success := parse_int(*b, u32);
                if !int_read_success {
                    chirp_warning(line);
                    continue;
                }
                item.floats[it_index] = (cast(*float32) *int_val).*;
            }
        } else {
            item.values[0] = value;
        }

        table_set(table, name, item);
    }
}

load_config_visitor :: (visit: *Struct_Visit, load_data: *Load_Data) -> Struct_Visitor_Command {
    item := table_find_pointer(*load_data.table, view_string(visit.path));

    if item == null {
        if visit.info.type == {
        case .STRUCT;
            info_struct := cast(*Type_Info_Struct) visit.info;
            if info_struct.name == {
            case "Quaternion"; #through;
            case "Color4f";    #through;
            case "Vector4";    #through;
            case "Color3f";    #through;
            case "Vector3";    #through;
            case "Vector2";
                return .CONTINUE;
            }
        }
        return .PUSH_MEMBER_OR_CONTINUE;
    }

    load_float :: (data: *void, value_str: string, raw_float: float) {
        float_value, success := parse_float(*value_str);
        if success {
            // try to use the raw float bytes if possible to avoid drift
            if raw_float != FLOAT32_NAN {
                error_size := abs(raw_float) * LOAD_FLOAT_ERROR_FACTOR;
                difference := abs(raw_float - float_value);
                if difference <= error_size {
                    float_value = raw_float;
                }
            }
            memcpy(data, *float_value, 4);
        }
    }

    if visit.info.type == {
    case .BOOL;
        bool_value, success := parse_bool(*item.values[0]);
        if success {
            memcpy(visit.data, *bool_value, size_of(bool));
        }
    case .ENUM;
        info_enum := cast(*Type_Info_Enum) visit.info;
        if info_enum.names.count > 0 {
            for 0..info_enum.names.count - 1 {
                if info_enum.names[it] == item.values[0] {
                    memcpy(visit.data, *info_enum.values[it], info_enum.runtime_size);
                    break;
                }
            }
        }
    case .INTEGER;
        info_integer := cast(*Type_Info_Integer) visit.info;
        int_value, success := parse_int(*item.values[0]);
        if success {
            memcpy(visit.data, *int_value, info_integer.runtime_size);
        }
    case .FLOAT;
        info_float := cast(*Type_Info_Float) visit.info;
        engine_check(.MEDIUM, info_float.runtime_size == 4);
        load_float(visit.data, item.values[0], item.floats[0]);
    case .STRING;
        str := cast(*string) visit.data;
        str.count = item.values[0].count;
        str.data  = null;
        if str.count > 0 {
            str.data = string_buffer.data + string_buffer.count;
            array_resize(*string_buffer, string_buffer.count + str.count);
            memcpy(str.data, item.values[0].data, str.count);
        }
        return .CONTINUE;
    case .STRUCT;
        info_struct := cast(*Type_Info_Struct) visit.info;
        float_count: int;
        if info_struct.name == {
        case "Quaternion"; #through;
        case "Color4f";    #through;
        case "Vector4";
            float_count = 4;
        case "Color3f";    #through;
        case "Vector3";
            float_count = 3;
        case "Vector2";
            float_count = 2;
        }

        if float_count > 0 {
            array: []float;
            array.count = float_count;
            array.data  = xx visit.data;
            for 0..array.count-1 {
                load_float(*array[it], item.values[it], item.floats[it]);
            }
            return .CONTINUE;
        }
    }

    return .PUSH_MEMBER_OR_CONTINUE;
}

VISIT_OPTIONS :: Struct_Visit_Options.{};

save_config_visitor :: (visit: *Struct_Visit, save_data: *Save_Data) -> Struct_Visitor_Command {

    float_fmt :: (x: float) -> FormatFloat #expand {
        digits_after_decimal := need_digits_after_decimal(x);
        return FormatFloat.{value=x, trailing_width=digits_after_decimal, zero_removal=.NO};
    }

    bytes :: (x: *float) -> u32 #expand {
        return (cast(*u32) x).*;
    }

    if visit.info.type == {
    case .BOOL;
        print(*save_data.file_builder, "% = %\n", view_string(visit.path), (cast(*bool) visit.data).*);
    case .ENUM;
        info_enum := cast(*Type_Info_Enum) visit.info;
        engine_check(.MEDIUM, info_enum.runtime_size <= 8);
        if info_enum.values.count > 0 {
            enum_str := "?";
            enum_value: int;
            memcpy(*enum_value, visit.data, visit.info.runtime_size);
            for 0..info_enum.values.count - 1 {
                if info_enum.values[it] == enum_value {
                    enum_str = info_enum.names[it];
                    break;
                }
            }
            print(*save_data.file_builder, "% = %\n", view_string(visit.path), enum_str);
        }
    case .INTEGER;
        info_integer := cast(*Type_Info_Integer) visit.info;
        engine_check(.MEDIUM, info_integer.runtime_size <= 8);
        int_value: s64;
        memcpy(*int_value, visit.data, visit.info.runtime_size);
        if info_integer.signed {
            print(*save_data.file_builder, "% = %\n", view_string(visit.path), int_value);
        } else {
            print(*save_data.file_builder, "% = %\n", view_string(visit.path), (cast(*u64) *int_value).*);
        }
    case .FLOAT;
        info_float := cast(*Type_Info_Float) visit.info;
        engine_check(.MEDIUM, info_float.runtime_size == 4);
        float_value: float32;
        memcpy(*float_value, visit.data, 4);
        print(*save_data.file_builder, "% = % (%)\n", view_string(visit.path), float_fmt(float_value), bytes(*float_value));
    case .STRING;
        str := cast(*string) visit.data;
        print(*save_data.file_builder, "% = %\n", view_string(visit.path), str.*);
        return .CONTINUE;
    case .STRUCT;
        info_struct := cast(*Type_Info_Struct) visit.info;
        if info_struct.name == {
        case "Quaternion";
            #through;
        case "Color4f";
            #through;
        case "Vector4";
            vec := cast(*Vector4) visit.data;
            print(*save_data.file_builder, "% = [%, %, %, %] (%,%,%,%)\n", view_string(visit.path), float_fmt(vec.x), float_fmt(vec.y), float_fmt(vec.z), float_fmt(vec.w), bytes(*vec.x), bytes(*vec.y), bytes(*vec.z), bytes(*vec.w));
            return .CONTINUE;
        case "Color3f";
            #through;
        case "Vector3";
            vec := cast(*Vector3) visit.data;
            print(*save_data.file_builder, "% = [%, %, %] (%,%,%)\n", view_string(visit.path), float_fmt(vec.x), float_fmt(vec.y), float_fmt(vec.z), bytes(*vec.x), bytes(*vec.y), bytes(*vec.z));
            return .CONTINUE;
        case "Vector2";
            vec := cast(*Vector4) visit.data;
            print(*save_data.file_builder, "% = [%, %] (%,%)\n", view_string(visit.path), float_fmt(vec.x), float_fmt(vec.y), bytes(*vec.x), bytes(*vec.y));
            return .CONTINUE;
        }
    }
    return .PUSH_MEMBER_OR_CONTINUE;
}

initialized: bool;
string_buffer: [..]u8;

// some_thing = 10.001 (x) 
// ... is stored in file. (note that it wouldn't be x, but instead the true value of the float, casted to an int, then printed)
// but the true float value, as represented by the integer in the ()'s, was evaluated to be 10.000997 once loaded and converted. 
// do we trust the text 10.001 or the x converted to float (10.000997)?
// well, 10.001 - 10.000997 = 0.000003
// 10.001 means the number of significant digits was N was 5
// 10^(N-2) = 10^3 = 1,000
// 10.000997 / 1,000 = 0.00100009997
// 0.000003 is less than 0.0010000997, so it's an insignificant change. trust the true value x, assuming the text was not changed.
PRINT_FLOAT_SIGNIFICANT_DIGITS :: 6;
LOAD_FLOAT_ERROR_FACTOR :: #run -> float {
    assert(PRINT_FLOAT_SIGNIFICANT_DIGITS >= 2);
    pow_10 := 1;
    for 0..PRINT_FLOAT_SIGNIFICANT_DIGITS-2 {
        pow_10 *= 10;
    }
    return 1.0 / pow_10;
};

need_digits_after_decimal :: (x: float) -> int {
    if x == 0 return PRINT_FLOAT_SIGNIFICANT_DIGITS;
    return max(PRINT_FLOAT_SIGNIFICANT_DIGITS - round(log_with_base(x, 10)), 0);
}
